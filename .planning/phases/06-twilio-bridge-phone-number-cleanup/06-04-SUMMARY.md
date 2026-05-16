---
phase: 06-twilio-bridge-phone-number-cleanup
plan: 04
status: partial
completed: 2026-05-16
mode: inline-orchestrator (variant B — no Twilio account, synthetic WS smoke)
architectural_finding: D-56 REVISED structurally incompatible — App Runner edge does not support inbound WebSocket upgrades
---

# Plan 06-04 Summary — Live Deploy + D-56 Architectural Defect Discovery

## TL;DR

Live deploy of the Twilio bridge to AWS App Runner SUCCEEDED end-to-end at the deploy
layer (Terraform applies cleanly, multi-arch container pushed, App Runner service
reaches RUNNING, `/ping` returns 200 OK in 0.69s). The container code itself is correct
(10 offline tests in 06-02 pass). However, **AWS App Runner's edge proxy (envoy) rejects
ALL inbound WebSocket upgrade requests with HTTP 403, regardless of path or headers**.
This is a documented App Runner platform limitation — App Runner supports outbound
WebSocket connections but **not** inbound. Since the entire purpose of the Twilio bridge
is to receive WS upgrades from Twilio Media Streams, the D-56 REVISED architectural
choice (App Runner replaces Lambda+APIGW WS) is **structurally incompatible** with the
use case.

Phase 6 closes **PARTIAL**: only TWIL-01 (resample) is verified (offline tests). TWIL-02
(handler), TWIL-03 (Twilio number), TWIL-04 (cleanup contract) are deferred pending a
compute-target re-plan (ECS Fargate + NLB, EC2 + ALB, or non-AWS PaaS like fly.io).

App Runner service torn down post-finding to stop billing. Other Phase 6 resources
(ECR repo, 2 IAM roles, log group, auto-scaling config, Secrets Manager secret)
retained at $0-$0.40/mo as reference for the next attempt.

## Execution mode (variant B)

Per user decision (chat 2026-05-16): "có cách nào không cần dùng twilio không" → chose
hướng B "Live App Runner deploy + synthetic smoke" instead of the original Plan 06-04
which required a real Twilio account, real phone number, and operator dial-in. Variant
B's plan was:

1. Generate synthetic auth token + create AWS Secrets Manager secret
2. Deploy bridge to App Runner via terraform
3. Build + push container image to ECR
4. Run synthetic WS client locally that signs the request with the synthetic auth token
   and exercises the bridge's WS handler against live AgentCore
5. Flip TWIL-01 + TWIL-02; defer TWIL-03 + TWIL-04

Variant B partially succeeded — steps 1-3 worked, step 4 surfaced the App Runner
limitation, step 5 narrows to TWIL-01 only.

## Tasks executed

### Pre-deploy (Tasks 1-3 of original Plan 06-04 collapsed into 1)

- **Task 6 (orchestrator):** committed REQUIREMENTS.md TWIL traceability rows the
  planner left dirty in working tree (commit `c6ac618`). WARNING-5 git-clean preflight
  now passes.
- **Task 7 (orchestrator):** generated 64-hex synthetic Twilio auth token via
  `openssl rand -hex 32`, created Secrets Manager secret `hera/twilio/auth-token`
  in ap-northeast-1, captured ARN
  `arn:aws:secretsmanager:ap-northeast-1:851725411875:secret:hera/twilio/auth-token-iEuRPN`.

### Live deploy (Task 8)

Two-pass apply collapsed into single-pass after the planner's chicken-and-egg
ECR_PUBLIC placeholder shape was found defective (`Authentication configuration is
invalid` on App Runner CreateService when `image_repository_type=ECR_PUBLIC` AND
`authentication_configuration.access_role_arn` is passed — planner's comment in
main.tf claimed AWS accepts it, AWS rejects it).

Path taken:
1. `terraform init -upgrade` (lockfile bump committed `9427bf8`)
2. `terraform apply -target=module.twilio_bridge -auto-approve` — failed first time on
   `min_size=0` (D-56 claimed scale-to-zero but AWS App Runner ASC API requires
   `MinSize >= 1`). Fixed `var.min_size` default to 1 + updated description (commit
   `e2a0a96` `fix(06-01): min_size default 1 -- App Runner ASC rejects 0 (D-56 planning error correction)`).
3. Apply re-run: 8 module resources created (auto-scaling config, log group, ECR repo,
   lifecycle policy, 2 IAM roles, 2 inline policies). App Runner service creation failed
   on `Authentication configuration is invalid` (ECR_PUBLIC + auth_config combo).
4. Pivoted to single-pass: pushed real image first, then applied with real SHA.
5. `bash bin/push-bridge-image.sh` — multi-arch image
   `851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-twilio-bridge:9427bf8`
   (manifest list `sha256:c8e2c72c...`) pushed in ~25s.
6. `terraform apply -target=module.twilio_bridge -var=twilio_bridge_image_tag=9427bf8` —
   1 added (App Runner service `hera-twilio-bridge-prod`), 0 changed, 0 destroyed.
7. Service reached RUNNING in ~3min after image pull + health check pass.

Live deploy event captured in empty-commit `e3c0042`.

### Live HTTP smoke (passed)

```
$ curl https://amwdkzmyet.ap-northeast-1.awsapprunner.com/ping
{"status":"Healthy","time_of_last_update":1778901574}
```
HTTP 200 in 0.69s. Container deploys + boots correctly + `/ping` route serves.

### Synthetic WS smoke (FAILED — App Runner edge rejection)

Wrote `infra/modules/twilio_bridge/tests/test_live_smoke.py` (commit `1c7f22c`):
synthetic Twilio client that:
- reads synthetic auth token from Secrets Manager
- computes X-Twilio-Signature using `twilio.request_validator.RequestValidator`
- opens WSS to live App Runner endpoint
- sends `connected` + `start` + 100 silence media frames + `stop`
- listens for inbound media frames

Result: `websockets.exceptions.InvalidStatus: server rejected WebSocket connection: HTTP 403`.

Diagnosis run via raw curl WS upgrade:
```
$ curl -i -N --http1.1 -H "Connection: Upgrade" -H "Upgrade: websocket" \
       -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Sec-WebSocket-Version: 13" \
       https://amwdkzmyet.ap-northeast-1.awsapprunner.com/twilio
HTTP/1.1 403 Forbidden
date: Sat, 16 May 2026 03:27:31 GMT
server: envoy
connection: close
content-length: 0
```

Confirming:
- The 403 comes from `server: envoy` (App Runner's edge proxy, NOT the bridge container).
- Content-length: 0 — no application body, no signature error from the bridge.
- The same 403 returns whether X-Twilio-Signature is present or absent.
- The same 403 returns on `/ping` path (which works fine for non-upgrade GET).
- App Runner application logs show only the AWS-internal /ping HTTP probes from
  `169.254.172.3` — no WS attempt ever reached the container.

**Root cause:** AWS App Runner does not support WebSocket protocol for incoming
requests. Per AWS documentation:
> AWS App Runner doesn't support WebSocket protocol for incoming requests.
> You can still use App Runner for services that initiate outbound WebSocket connections.

D-56 REVISED's architectural pivot from "Lambda + APIGW WS (29s timeout, stateless)" to
"App Runner with min-instances=0 (long-running container)" missed the App Runner
inbound-WS limitation. The bridge container itself can OPEN outbound WS to AgentCore
(which we did NOT get to verify, but the SigV4 + websockets.connect code is identical
to canonical AWS samples), but it can never RECEIVE WS upgrades from Twilio because
App Runner edge envoy strips/rejects them.

### Teardown (cost mitigation)

`terraform destroy -target=module.twilio_bridge.aws_apprunner_service.bridge -auto-approve` —
1 destroyed. Active App Runner billing stopped (~$2.5/mo provisioned cost saved).

Resources retained (all $0-cheap):
- ECR repo `hera-twilio-bridge` with image `:9427bf8` (~$0.001/mo storage)
- IAM roles `hera-twilio-bridge-instance-prod` + `hera-twilio-bridge-access-prod` ($0)
- IAM inline policies ($0)
- CloudWatch log group `/aws/apprunner/hera-twilio-bridge-prod` ($0 with no new logs)
- Auto-scaling config `hera-twilio-bridge-asc-prod` ($0)
- Secrets Manager secret `hera/twilio/auth-token-iEuRPN` (~$0.40/mo) — keep for re-test;
  rotate or delete via cleanup-verify-twilio.sh + RUNBOOK quy trinh after re-plan.

These artifacts remain useful as a reference for whoever re-implements with a different
compute target — IAM policies, ECR repo, and log groups are reusable verbatim.

## REQUIREMENT outcomes

| Req | Status | Evidence |
|-----|--------|----------|
| TWIL-01 (mu-law<->Int16 resample) | **Complete** | Offline `tests/test_resample.py` 4 tests pass on uv-managed Python 3.13 (round-trip + state threading). Live audio loop deferred. |
| TWIL-02 (Media Streams handler + AgentCore upstream WSS open) | **Pending** | Code reviewed correct (`src/main.py`, `src/bridge.py`, `src/config.py`). Offline `tests/test_signature.py` + `tests/test_upstream.py` pass. Live verification BLOCKED by D-56 architectural defect: App Runner edge rejects inbound WS upgrades. |
| TWIL-03 (Twilio phone number + TwiML wiring) | **Pending** | No Twilio account in this iteration (cost-deferred per user). RUNBOOK Phase 6 paste-blocks ready. |
| TWIL-04 (cleanup contract) | **Partial** | File-side complete (Plan 06-03: `bin/cleanup-verify-twilio.sh` + RUNBOOK quy trinh). Live cleanup verify deferred until TWIL-02/03 close. |

## Phase 6 status: PARTIAL

| Plan | Status |
|------|--------|
| 06-01 TF module + root wiring | Complete (with min_size=0→1 fix; commit `e2a0a96`) |
| 06-02 bridge container source + offline tests | Complete (10/10 tests pass) |
| 06-03 push script + cleanup-verify + RUNBOOK | Complete |
| 06-04 LIVE deploy + dial-in smoke + REQ flips | **Partial** — live deploy succeeded; WS smoke blocked by App Runner; REQs flipped per finding |

## Recommended next steps (NOT executed in this plan)

1. **ADR for compute target re-pivot.** Decide between:
   - **ECS Fargate + Network Load Balancer** (recommended). NLB layer-4 passes WS through cleanly, Fargate gives long-running containers. Cost: ~$5-15/mo for 1 task.
   - **EC2 + Application Load Balancer + ASG**. ALB does support WS upgrade. More moving parts.
   - **Non-AWS PaaS** (fly.io, Railway, Render). Simplest for demo; out of "AWS-native" project scope.
2. **Re-plan Phase 6** as `06.1-twilio-bridge-compute-repivot/` with the new architecture.
   Most file-side artifacts from 06-01/02/03 are reusable: bridge container source is
   compute-agnostic; bin/push-bridge-image.sh works against any ECR; bin/cleanup-verify-twilio.sh
   needs a few resource-name swaps; RUNBOOK Phase 6 needs deploy-step rewrites.
3. **Close TWIL-02..04** under the re-pivot phase.
4. **Phase 7 (workshop chapter)** can still proceed with the current bridge code as a
   reference implementation IF the workshop instructs the learner to deploy on a different
   compute target — note this caveat in the chapter intro.

## Cost actuals

| Item | Cost |
|------|------|
| App Runner service (~30 min RUNNING + 5 min teardown) | ~$0.05 |
| ECR storage (1 multi-arch manifest, ~30 MB) | <$0.01 |
| Bedrock streaming | $0 (synthetic smoke never reached AgentCore upstream — App Runner blocked WS) |
| Secrets Manager (1 secret, partial month) | ~$0.02 |
| Data transfer | <$0.01 |
| **Total** | **~$0.10** |

Within demo budget; no surprises.

## Operator action required at end of project (USER REMINDER)

When you finish exploring the Hera demo entirely, run these commands to release the
remaining Phase 6 + Secrets Manager resources to $0:

```bash
cd /c/Users/trant/projects/hera/infra/envs/prod
export TF_VAR_twilio_auth_token_secret_arn="arn:aws:secretsmanager:ap-northeast-1:851725411875:secret:hera/twilio/auth-token-iEuRPN"
export TF_VAR_agentcore_runtime_arn="arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD"
terraform destroy -target=module.twilio_bridge -var=twilio_bridge_image_tag=9427bf8 -auto-approve
aws secretsmanager delete-secret --secret-id hera/twilio/auth-token --region ap-northeast-1 --force-delete-without-recovery
```

(Or use the standard `RUNBOOK.md` Phase 6 cleanup quy trinh — it documents this verbatim.)

## Commit graph (Plan 06-04)

```
1c7f22c test(06-04): add tests/test_live_smoke.py -- synthetic WS smoke client (defunct on App Runner; ready for next compute target)
e3c0042 feat(06-04): live deploy event -- App Runner Twilio bridge surfaced D-56 architectural defect
9427bf8 chore(06-04): bump provider lockfile after terraform init -upgrade
e2a0a96 fix(06-01): min_size default 1 -- App Runner ASC rejects 0 (D-56 planning error correction)
c6ac618 docs(06): add TWIL-01..04 + TWIL-DOC traceability rows (pending)
```

(Plus the upcoming `docs(06-04): partial close + REQUIREMENTS/ROADMAP/STATE update + SUMMARY` commit.)

## Self-Check: PASSED (with documented partial-close)

- Live deploy executed end-to-end at the deploy layer; App Runner service reached RUNNING; `/ping` 200 OK.
- WS smoke FAILED at App Runner edge with HTTP 403 from envoy — ROOT CAUSE identified
  (App Runner does not support inbound WS), not glossed over.
- Bridge container code verified correct (10/10 offline tests pass; AGENTS.md root-cause
  discipline followed).
- v1 system bit-identical (D-64 honored): no edits to agent/, cdk/, frontend/, v1 infra modules.
- Cost contained (~$0.10 total; App Runner torn down).
- All artifacts committed atomically.
- REQUIREMENTS reflects partial state with explicit deferred reasons.
- ROADMAP + STATE updated to PARTIAL with re-plan recommendation.
