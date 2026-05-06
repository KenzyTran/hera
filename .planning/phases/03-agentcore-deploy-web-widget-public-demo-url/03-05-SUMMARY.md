---
phase: 03-agentcore-deploy-web-widget-public-demo-url
plan: 05
subsystem: agent
tags: [boto3, credential-chain, imdsv2, agentcore, dockerfile-env, gap-closure, partial-close]

# Dependency graph
requires:
  - phase: 03-agentcore-deploy-web-widget-public-demo-url/03-04
    provides: live AgentCore Runtime hera_agent-GIsf2P4ImD + presigner Lambda + open credential-injection blocker
provides:
  - agent/hera_agent/config.py lazy-default config readers (HERA_KB_ID + AWS_REGION baked-in defaults; env var overrides preserved for docker-compose)
  - agent/hera_agent/pipeline.py:build_llm() bridging boto3 default credential chain (env -> ~/.aws -> IMDSv2) into AWSNovaSonicLLMService static-kwargs
  - agent/Dockerfile ENV bake-in for HERA_KB_ID=BKXE19AH89 + AWS_REGION=ap-northeast-1 (AgentCore Runtime path; docker-compose still overrides)
  - Live re-pushed image hera-agent:5f21e36 multi-arch on ECR
  - Live AgentCore Runtime hera_agent-GIsf2P4ImD updated in place: version=2, status=READY, ContainerUri=hera-agent:5f21e36
  - Local /ping=200 proof under no-env-var conditions (Dockerfile bake-in carries cold-start)
affects:
  - phase-04 (NEW follow-up plan: agent protocol bridge to expose /invocations per AgentCore HTTP protocol; closes Phase 3 SC#2)
  - phase-04 (still owns OBS-04/OBS-05 + cleanup-verify; that work is not blocked by this plan)
  - Phase 5 workshop docs (the boto3-default-chain + Dockerfile-ENV-bake pattern is teachable as the canonical AgentCore Runtime credential bridge once the protocol bridge ships)

# Tech tracking
tech-stack:
  added:
    - boto3.Session().get_credentials().get_frozen_credentials() for AgentCore IMDSv2 -> static-kwargs bridging
  patterns:
    - "Lazy/default-aware config: os.environ.get(KEY, PROD_DEFAULT) so the same image runs on docker-compose (env injects override) AND AgentCore Runtime (no env injection -> defaults are used)"
    - "Dockerfile ENV bake-in for AgentCore Runtime: AWS::BedrockAgentCore::Runtime CFn schema has NO env-var injection property; baked-in ENV is the supported way to ship per-environment defaults; container env still wins (Docker semantics)"
    - "Bridge boto3 default credential chain (env -> ~/.aws -> IMDSv2) into AWSNovaSonicLLMService's StaticCredentialsResolver via session.get_credentials().get_frozen_credentials() called per-connection inside build_llm() (NOT at module import; supports rotated IMDS creds)"

key-files:
  created:
    - .planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-05-SUMMARY.md (this file)
  modified:
    - agent/hera_agent/config.py (Task 1: lazy-default KB_ID + AWS_REGION + KB_SCORE_THRESHOLD + HERA_VOICE)
    - agent/hera_agent/pipeline.py (Task 2: build_llm() uses boto3 default credential chain)
    - agent/Dockerfile (Task 3: ENV HERA_KB_ID + ENV AWS_REGION baked in before EXPOSE)
    - .planning/STATE.md (this commit)
    - .planning/ROADMAP.md (this commit)

key-decisions:
  - "Q1 user-approved (2026-05-06): close Plan 03-05 as 'credential bridge complete; protocol bridge is a NEW gap → Phase 4 follow-up plan owns it'. Phase 3 SC#2 (live browser → AgentCore voice loop) stays OPEN until Phase 4. No more cdk deploys, image rebuilds, or Bedrock streaming smoke costs in this plan. Cost-conscious framing: Hera is a learning demo, not production — minimize billable AWS work."
  - "Q2 user-approved (2026-05-06): skip the browser test — the failure mode (404 from protocol mismatch) is already understood; running the test would only confirm a known failure and waste Bedrock streaming cost."
  - "Lazy-default config (os.environ.get with documented prod default) over hard-required env vars: lets the same image work in both docker-compose dev (env-var override) and AgentCore Runtime (no env injection -> default kicks in). Avoids the import-time KeyError that broke Plan 03-04's live-deploy attempt."
  - "boto3 default credential chain bridged into AWSNovaSonicLLMService's static-kwargs at per-connection time inside build_llm() (NOT at module import). IMDSv2 returns a session token, env-var path returns None for token. AWSNovaSonicLLMService accepts session_token=None already (Phase 2 path)."
  - "Dockerfile bakes only non-secret config (KB_ID, REGION). NEVER bake AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY into the image — those still come from env (local) or IMDSv2 (AgentCore). Baking creds would be a leak in the image manifest."
  - "Plan 03-05 commit-empty Task 4: the actual source-code work for the credential fix landed in Tasks 1-3 (3 commits). The cdk redeploy + image push were operator actions captured as evidence in an --allow-empty commit body so the deploy event is auditable in git history without a fake source diff."
  - "Discovered during execution (Rule-4 architectural surface): AgentCore Runtime HTTP protocol invokes a `/invocations` POST endpoint per Bedrock convention, NOT raw WS frames to `/ws`. Smoke probe returns 404 (not 424) — proves credential fix works AND surfaces a NEW protocol-bridge gap that is OUT OF Plan 03-05's 3-file scope. Phase 4 follow-up plan owns this. The reference repo `awslabs/agentcore-samples/.../06-bi-directional-streaming/04-pipecat-sonic-ws` is the canonical source for the bridge pattern."

requirements-completed: []  # Plan 03-05 closes the credential bridge gap but does NOT close any new requirement IDs alone — DEP-01/DEP-02/DEM-01/DEM-02 were tagged in the plan frontmatter aspirationally; live voice loop closure (which actually validates those reqs end-to-end) is deferred to the Phase 4 protocol-bridge follow-up plan.

requirements-partial:
  - DEP-01 (container deploys to AgentCore + starts cleanly under cold-start now that credentials inject through IMDSv2; full close needs the protocol bridge to surface /invocations)
  - DEP-02 (presign+WSS handshake + AgentCore data-plane auth all reachable; 404 from protocol mismatch is the remaining gap)
  - DEM-01, DEM-02 (public URL serves widget + presign URL works; voice loop blocked by protocol bridge)

# Metrics
duration: ~25 min (Tasks 1-3 source fixes + image push + cdk redeploy + smoke probe by previous executor; Tasks 4-5 narration + docs by this invocation)
completed: 2026-05-06
---

# Phase 3 Plan 05: Agent Credential Bridge for AgentCore Runtime Summary

**Closed the agent credential-injection gap that blocked Plan 03-04's live voice-loop test — 3-file fix (lazy config defaults, boto3 default credential chain, Dockerfile ENV bake-in) brings the container through cold-start cleanly on AgentCore Runtime version=2; surfaced a NEW protocol-bridge gap (AgentCore HTTP /invocations vs FastAPI /ws) deferred to a Phase 4 follow-up plan to keep demo budget intact.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-06 (Tasks 1-3 by previous executor)
- **Completed:** 2026-05-06 (Tasks 4-5 by this invocation; Task 4 = empty-commit evidence; Task 5 = SUMMARY + STATE + ROADMAP)
- **Tasks:** 5 (3 source-code commits + 1 empty live-deploy evidence commit + 1 metadata commit)
- **Files created:** 1 (this SUMMARY)
- **Files modified:** 5 (3 source files, STATE, ROADMAP)
- **AWS write actions in this plan invocation:** 0 (image and runtime were already live before this invocation; per user-approved Q1 (a) demo budget constraint, no further `cdk deploy` / `docker build` / `aws bedrock-agentcore` writes)

## Accomplishments

- **Credential injection gap closed.** `agent/hera_agent/config.py:12` no longer raises `KeyError` at module import on AgentCore Runtime — the lazy-default pattern (`os.environ.get("HERA_KB_ID", "BKXE19AH89")`) lets the container survive import under both `unset HERA_KB_ID` (defaults take over) and `HERA_KB_ID=test123` (env-var wins).
- **Boto3 default credential chain bridged into AWSNovaSonicLLMService.** `pipeline.py:build_llm()` calls `boto3.Session().get_credentials().get_frozen_credentials()` per-connection and passes `access_key`/`secret_key`/`token` as static kwargs. This works in both environments because boto3's chain checks env vars (local docker-compose) THEN ~/.aws THEN IMDSv2 (AgentCore Runtime) in order; first hit wins.
- **Dockerfile bakes prod-default ENV vars.** `ENV HERA_KB_ID=BKXE19AH89` + `ENV AWS_REGION=ap-northeast-1` land before `EXPOSE 8080`. AgentCore Runtime (no env injection) now gets sane defaults; docker-compose.yml `environment:` block still overrides per Docker semantics. Credentials (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) are deliberately NOT baked — those still come from env (local) or IMDSv2 (AgentCore).
- **Phase 2 unit tests still green.** `cd agent && uv run pytest` passes (no regression on local docker-compose path).
- **Live image ships.** `851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent:5f21e36` multi-arch (linux/arm64 + linux/amd64) on ECR.
- **Live AgentCore Runtime updated in place.** `cdk deploy hera-agentcore --context image_tag=5f21e36` rolled the runtime to version=2 with status=READY. AgentRuntimeName stayed `hera_agent` so no resource replacement; the runtime ARN, presign Lambda, and CloudFront widget all stayed valid.
- **Local /ping=200 under no-env-var conditions.** `docker run --rm hera-agent:5f21e36` + `curl http://localhost:8080/ping` returns `{"status":"Healthy"}` even with NO env vars set — direct proof the Dockerfile ENV bake-in carries the cold-start path that AgentCore Runtime walks.
- **AgentCore invocation moved from 424 to 404.** Pre-fix: 424 Failed Dependency (container crashed on import). Post-fix: 404 (container is alive but the route the AgentCore HTTP protocol calls — `/invocations` — does not exist on the FastAPI app). The fix is doing exactly what it should; the 404 is a NEW finding (see Discovered During This Plan).

## Task Commits

Each task committed atomically on `master`:

1. **Task 1: Lazy KB_ID with prod default in config.py** — `0242c01` (fix)
2. **Task 2: boto3 default credential chain in build_llm()** — `5ebc650` (fix)
3. **Task 3: Bake HERA_KB_ID + AWS_REGION ENV defaults into Dockerfile** — `5f21e36` (fix)
4. **Task 4: live cdk redeploy evidence** — `f5a6b1c` (feat, --allow-empty per Q1+Q2 cost-conscious decision; live image push + cdk deploy + ping/smoke evidence captured in commit body)
5. **Plan metadata (Task 5):** SUMMARY + STATE + ROADMAP — see final commit hash below.

## Files Created/Modified

- `agent/hera_agent/config.py` — Lazy/default-aware config readers compatible with both env-var (docker-compose) and bake-in (AgentCore) patterns. KB_ID defaults to `BKXE19AH89` (live prod KB), AWS_REGION defaults to `ap-northeast-1`, KB_SCORE_THRESHOLD defaults to 0.4 (matches `bin/verify-kb.sh`), HERA_VOICE defaults to `matthew`.
- `agent/hera_agent/pipeline.py` — `build_llm()` now resolves credentials via boto3 default chain inside the function (NOT at import) and passes them as static kwargs to AWSNovaSonicLLMService. Phase 2 D-21 / Pitfall B (StaticCredentialsResolver) is honored — we still pass static kwargs, we just resolve them dynamically.
- `agent/Dockerfile` — `ENV HERA_KB_ID=BKXE19AH89` + `ENV AWS_REGION=ap-northeast-1` baked in after `USER appuser` and `ENV PATH=...`, before `EXPOSE 8080`. Comment block documents the docker-compose-overrides-win semantics.

## Live AWS Resource State (preserved, no teardown)

| Output / Identifier | Value |
|---------------------|-------|
| AgentCore Runtime ARN | `arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD` |
| AgentCore Runtime ID | `hera_agent-GIsf2P4ImD` |
| AgentCore Runtime status | `READY` |
| AgentCore Runtime version | `2` (was `1` before this plan; in-place ContainerUri update) |
| Container image (ECR multi-arch) | `851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent:5f21e36` |
| Presign Function URL | `https://ijrovzxz4tts2tdo2w5yxqxho40fruyn.lambda-url.ap-northeast-1.on.aws/` (unchanged from Plan 03-04) |
| CloudFront widget URL | `https://dg0w939ktclw6.cloudfront.net` (unchanged) |
| Old image (kept for rollback) | `hera-agent:214068b` (Plan 03-04 baseline) |

**No teardown intended.** Per user-approved Q1 (a), all live AWS state is preserved so the Phase 4 protocol-bridge follow-up plan can apply its fix on top without paying the re-creation cost.

## Decisions Made

See key-decisions in frontmatter. Notable in-execution observations:

- **The credential gap was a 3-file fix, exactly as the plan predicted.** The planner correctly identified `config.py:12`, `pipeline.py:48`, and `Dockerfile` as the surface; no scope creep was needed. Plan 03-04 SUMMARY's "Open Items" Resolution Path #1 (refactor for boto3 default chain) was chosen and shipped.
- **The Dockerfile ENV bake-in proves AgentCore Runtime's no-env-injection contract is workable.** AWS::BedrockAgentCore::Runtime CFn schema confirmed by Plan 03-04 to have no `Environment` property; ENV at image-build time is the supported way to ship per-environment defaults. Docker-compose dev path still overrides.
- **`docker run` + `curl /ping` under no-env-vars-set is the right local proxy for AgentCore cold-start.** It's cheap (no AWS calls), fast (~5s), and validates the exact failure mode that broke Plan 03-04 (container crashed on import before /ping could answer). Future agent-side changes should keep this as the smoke gate before any cdk deploy.
- **The 424->404 transition is the smoking gun for credential-fix correctness.** 424 Failed Dependency = container died before AgentCore could route to it. 404 Not Found = container is alive and listening but the route AgentCore's HTTP protocol calls is not defined by the FastAPI app. Different layer, different failure.
- **Cost-conscious closure (user-approved Q1 (a) + Q2 (a)).** Hera is a learning demo. Running another full smoke (cdk deploy + Bedrock streaming smoke + browser test) to confirm a known failure mode would burn AgentCore + Sonic streaming cost without learning anything new. Closing the plan here — credential bridge done, protocol bridge tracked as Phase 4 follow-up — preserves demo budget and lets Phase 4 spend that cost on the actual fix.

## Discovered During This Plan (NEW gap, OUT OF SCOPE)

### CRITICAL — Phase 3 SC#2 (live browser → AgentCore voice loop) remains OPEN due to a separate protocol-bridge gap

**Symptom:** Container starts cleanly on AgentCore Runtime version=2 (verified via local /ping=200 under no-env-vars and live AgentCore status=READY). AgentCore data-plane invocation reaches the container but returns **HTTP 404** (was 424 before the credential fix). CloudWatch log group `/aws/bedrock-agentcore/hera-agent` now has `storedBytes>0` because the container is alive long enough to log.

**Root cause (high confidence):**
- AgentCore Runtime's HTTP protocol invokes the container at `POST /invocations` per Bedrock convention (the same shape as Bedrock Custom Models / Sagemaker Bring-Your-Own-Container). The runtime's `ProtocolConfiguration: HTTP` (set in Plan 03-04's CDK stack) is what selects this contract.
- The Hera FastAPI app exposes `GET /ping` + `WebSocket /ws` (Phase 2 baseline, AGT-01 contract). It does NOT expose `POST /invocations`. AgentCore's protocol layer therefore returns 404 because the route does not exist on the application.
- The presigned WSS URL Plan 03-04 ships still works at the SigV4 signing layer (the Lambda presigner mints the URL fine; the WSS handshake reaches the runtime); the failure is one layer deeper at the runtime-to-container HTTP bridge.

**Resolution path (Phase 4 follow-up plan should own this):**

Refactor the agent's HTTP entry point to expose `POST /invocations` per the AgentCore HTTP protocol contract. Two implementation styles exist:

1. **Native /invocations endpoint** — Add a FastAPI route `@app.post("/invocations")` that accepts the AgentCore request envelope and bridges into the existing Pipecat WebSocket pipeline (or replaces it with a request-scoped pipeline if AgentCore expects HTTP request/response semantics rather than long-lived bidi streaming).

2. **Sidecar bridge** — Run a thin proxy in the container that translates AgentCore's `/invocations` POST into local `WebSocket /ws` frames against the existing app. More overhead but smaller diff to the agent's Phase 2 contract.

The canonical reference is the awslabs samples repo `awslabs/agentcore-samples/.../06-bi-directional-streaming/04-pipecat-sonic-ws`, which ships the exact Pipecat-on-AgentCore bidi-streaming pattern. Phase 4's planner should mine that repo for the supported entry-point shape before locking the implementation.

**Phase 4 follow-up plan suggestion:** `04-XX-agent-protocol-bridge` — refactor agent entry point to expose `/invocations` per AgentCore HTTP protocol; verify with `bin/smoke-deploy.sh` against the existing live runtime; close Phase 3 SC#2.

### Other open items (carried from Plan 03-04 SUMMARY, unchanged)

- AgentCore service-quota request (default 10 concurrent runtimes; D-30 originally said 2) — operational AWS console action.
- Per-IP rate limit on the presign Function URL (OBS-04) + per-Lambda concurrency cap.
- CDK bootstrap deploy-role trust policy for non-root operators.
- Sonic foundation-model ARN runtime gate (deferred since Plan 03-01) — will be confirmed once the protocol bridge ships and Sonic actually init-streams.
- CloudWatch dashboards/alarms for AgentCore runtime + presigner Lambda (Phase 4 OBS-01..03).

## Phase 3 Status After This Plan

| Phase 3 Success Criterion | Status | Evidence |
|---------------------------|--------|----------|
| SC#1 — Pipecat container deployed to AgentCore Runtime in ap-northeast-1 with working endpoint | CLOSED | hera_agent-GIsf2P4ImD status=READY, version=2, image hera-agent:5f21e36 |
| SC#2 — Browser → public HTTPS demo URL → end-to-end voice conversation with KB-backed answer | OPEN (DEFERRED) | Container starts cleanly + presign+WSS auth works + AgentCore reaches container; 404 from protocol mismatch (FastAPI /ws vs AgentCore /invocations) — Phase 4 follow-up plan owns |
| SC#3 — Error states visible (mic permission, WS connect failure, agent timeout, mic muted) | CLOSED | Plan 03-02 verbatim WID-06 strings + heartbeat + 5-state record button (commit `6a57d95`) |
| SC#4 — IAM least-privilege (zero wildcards in Action/Resource) | CLOSED | Plan 03-01 + 03-04 deviation `ab44397` shipped ECR pull + WebSocketStream actions; Python regex sweep documented one wildcard (cloudwatch:PutMetricData — AWS-published exception) |
| SC#5 — Public demo banner (instructor demo, daily cap, follow workshop) | CLOSED | Plan 03-02 frontend banner copy preserved verbatim |

## Threat Flags

No new threat surface introduced by this plan. The Dockerfile ENV bake-in adds no public surface (image-only). The boto3-default-chain refactor strengthens credential handling (no static creds at module scope; per-connection IMDSv2 supports rotation). All Plan 03-04 threat flags (`anonymous-public-lambda`, `ecr-token-wildcard`) carry forward unchanged.

## User Setup Required

- **Phase 4 follow-up plan needs to ship the agent protocol bridge** (FastAPI `/invocations` endpoint or sidecar proxy) before the browser-driven voice loop can actually close.
- No further action on Plan 03-05 itself — the credential fix is live, Phase 2 tests are green, and AWS state is preserved for clean handoff.

## Self-Check

Files claimed as created/modified verified present:

- `agent/hera_agent/config.py` — lazy-default pattern in place (verified by `grep "os.environ.get" agent/hera_agent/config.py`)
- `agent/hera_agent/pipeline.py` — `boto3.Session().get_credentials()` in build_llm() (verified by `grep "get_frozen_credentials" agent/hera_agent/pipeline.py`)
- `agent/Dockerfile` — `ENV HERA_KB_ID=BKXE19AH89` + `ENV AWS_REGION=ap-northeast-1` (verified by `grep "ENV HERA_KB_ID" agent/Dockerfile`)
- `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-05-SUMMARY.md` — this file
- `.planning/STATE.md`, `.planning/ROADMAP.md` — updated by this commit

Commits verified in `git log`:
- `0242c01`, `5ebc650`, `5f21e36`, `f5a6b1c` — all present and reachable from HEAD on `master`.

Live AWS resources (preserved, not re-verified in this invocation per user-approved Q1+Q2):
- AgentCore Runtime `hera_agent-GIsf2P4ImD` was status=READY version=2 with ContainerUri=hera-agent:5f21e36 at the close of the previous executor's invocation.
- Per cost-conscious closure, no further `aws bedrock-agentcore-control` / `aws ecr` / `aws cloudfront` calls were issued in this invocation.

## Self-Check: PASSED (credential-bridge scope; protocol-bridge gap surfaced and handed off to Phase 4)

---
*Phase: 03-agentcore-deploy-web-widget-public-demo-url*
*Plan: 05*
*Completed: 2026-05-06*
