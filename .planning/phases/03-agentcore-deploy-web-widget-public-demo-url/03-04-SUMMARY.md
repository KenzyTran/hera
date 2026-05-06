---
phase: 03-agentcore-deploy-web-widget-public-demo-url
plan: 04
subsystem: infra
tags: [cdk-python, aws-cdk, bedrock-agentcore, lambda-function-url, sigv4-presign, terraform, websocket]

# Dependency graph
requires:
  - phase: 03-agentcore-deploy-web-widget-public-demo-url/03-01
    provides: agentcore_exec_role_arn, agentcore_log_group_name, ecr_repo_url, widget_cloudfront_url, widget_s3_bucket_name, widget_cloudfront_distribution_id
  - phase: 03-agentcore-deploy-web-widget-public-demo-url/03-02
    provides: frontend widget with __PRESIGN_URL__ placeholder + bin/build-widget.sh skeleton
  - phase: 03-agentcore-deploy-web-widget-public-demo-url/03-03
    provides: ECR image hera-agent multi-arch + bin/push-image.sh
provides:
  - infra/cdk/ uv-managed CDK Python project (single-stack hera-agentcore wrapping CfnRuntime L1)
  - infra/modules/widget_presigner/ Terraform module (Lambda + Function URL + IAM, NEW Rule-4 deviation)
  - bin/_smoke_deploy_probe.py (presign+fetch -> wss probe; mirrors browser flow)
  - bin/smoke-deploy.sh (8-step end-to-end orchestrator)
  - live AgentCore Runtime (hera_agent-GIsf2P4ImD) + Lambda presigner (hera-widget-presign-prod) + presign Function URL
  - Widget contract change: __AGENTCORE_WSS_URL__ -> __PRESIGN_URL__ (Rule-4 against Plan 03-02)
  - RUNBOOK Phase 3 4-step lifecycle (D-25 amended)
affects:
  - phase-04 (OBS-04 per-IP rate limit on the presign Lambda; OBS-05 cost circuit breaker; AgentCore credential bridge for the agent container)
  - Phase 5 workshop docs (the presign-Lambda pattern is a teachable AgentCore + browser auth bridge)

# Tech tracking
tech-stack:
  added:
    - aws_lambda_function (python3.12)
    - aws_lambda_function_url (AuthType=NONE, CORS allow-origin pinned)
    - aws_iam_role + inline policy on the presigner Lambda
    - botocore.auth.SigV4QueryAuth for WSS URL presigning
    - AWS::BedrockAgentCore::Runtime CFn resource (CDK L1 CfnRuntime)
    - cdk bootstrap stack CDKToolkit in 851725411875/ap-northeast-1
  patterns:
    - "Two-pass terraform apply for CDK<->TF cross-references: first apply lays infra with placeholder ARN, cdk deploy emits real ARN, second-pass terraform apply -var=agentcore_runtime_arn=<arn> wires the dependent module"
    - "SigV4 query-string presigning with TTL <=300s for browser-fetchable WSS URLs (presigner does not require any AWS SDK in the browser)"
    - "Lambda Function URL CORS allow_methods accepts only the 6 standard verbs; OPTIONS is auto-handled and must NOT be listed"
    - "Lambda reserved_concurrent_executions cannot push UnreservedConcurrentExecution below 10 on a fresh-quota account; -1 (unreserved) is the safe default until a quota increase is filed"
    - "AgentCore Runtime exec role MUST grant ecr:GetAuthorizationToken (Resource=*; documented IAM exception) plus ecr:BatchGetImage + ecr:GetDownloadUrlForLayer scoped to the repo, otherwise CFn CREATE_FAILED with 'Access denied while validating ECR URI'"
    - "AgentCore data-plane API action is bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream (NOT InvokeAgentRuntime, which is the synchronous HTTP path)"
    - "Empty-context cdk.json on CDKv2: legacy @aws-cdk/core:enableStackNameDuplicates flag was removed in CDKv2 and breaks synth with UnsupportedFeatureFlag"
    - "MSYS_NO_PATHCONV=1 required when passing log-group names starting with / through the AWS CLI on Git Bash for Windows"

key-files:
  created:
    - infra/modules/widget_presigner/versions.tf
    - infra/modules/widget_presigner/variables.tf
    - infra/modules/widget_presigner/main.tf
    - infra/modules/widget_presigner/outputs.tf
    - infra/modules/widget_presigner/src/handler.py
    - .planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-04-SUMMARY.md (this file)
  modified:
    - infra/cdk/cdk.json (drop CDKv1-only feature flag)
    - infra/envs/prod/main.tf (instantiate widget_presigner module)
    - infra/envs/prod/variables.tf (add agentcore_runtime_arn)
    - infra/envs/prod/outputs.tf (add presign_url)
    - infra/envs/prod/.terraform.lock.hcl (archive provider 2.7.1 added)
    - infra/modules/agentcore_iam/main.tf (Rule-2: add ECR pull permissions)
    - frontend/app.js (Rule-4: __PRESIGN_URL__ placeholder + presign+fetch flow)
    - bin/build-widget.sh (Rule-4: sed-replace __PRESIGN_URL__; CloudFront /* invalidation)
    - bin/_smoke_deploy_probe.py (Rule-4: PRESIGN_URL env path -> fetch -> wss connect)
    - bin/smoke-deploy.sh (Rule-4: 8-step lifecycle including second-pass tf apply)
    - RUNBOOK.md (D-25 amended: 4-step lifecycle with Step 3.5 second-pass apply)
    - .gitignore (infra/modules/widget_presigner/build/)
    - .planning/STATE.md
    - .planning/ROADMAP.md

key-decisions:
  - "Q1 user-approved: Lambda Function URL /presign issuing SigV4-presigned WSS URLs; presigner module lives Terraform-side per D-24 (not in CDK). Module exports presign_url output consumed by bin/build-widget.sh."
  - "Q2 user-approved: skip per-function concurrency cap for v1 (option (i)); reserved_concurrent_executions=-1 default. AWS rejected positive values on a 10-quota account; pursuing a quota increase + per-IP rate limit is Phase 4 OBS-04/OBS-05 territory."
  - "Two-pass terraform apply lifecycle (D-25 amended): TF apply (Wave 1) -> push-image -> cdk deploy (emits AgentCore Runtime ARN) -> TF apply -var=agentcore_runtime_arn=<arn> -> build-widget. The first apply uses an empty-string default for var.agentcore_runtime_arn so it can run before cdk deploy exists; the second apply rewires the presigner Lambda env vars + IAM policy in-place (no Lambda replace)."
  - "Widget contract changed from __AGENTCORE_WSS_URL__ (direct WSS, Plan 03-02 baseline) to __PRESIGN_URL__ (HTTPS Function URL the widget fetches before opening WSS). frontend/app.js gains resolveWsUrl() that fetches PRESIGN_URL; presign-fetch errors flow through the existing ws-connect-failed WID-06 branch (D-28 trigger preserved)."
  - "Widget local-dev path preserved: PRESIGN_URL=null -> WS_LOCAL_DEV_URL='ws://localhost:8080/ws' for docker-compose. typeof guard in app.js selects the production branch only when bin/build-widget.sh has injected a real Function URL."
  - "AgentCore Runtime resource has NO MaxConcurrentSessions / Throttle / SessionLimit CFn property in the ap-northeast-1 schema (live introspection per Plan 03-04 prior_progress). D-30 concurrency cap is therefore NOT enforced at the resource layer; per-account Service Quota request + presigner Lambda concurrency would be the operational path. Deferred to Phase 4 OBS-04/OBS-05 per user-approved Q2."
  - "AgentCore data-plane URL formula: wss://bedrock-agentcore.<region>.amazonaws.com/runtimes/<URL-ENCODED-ARN>/ws?qualifier=DEFAULT. ARN URL-encoding uses quote(arn, safe='') so colons AND slashes are percent-encoded (%3A and %2F). The CDK output AgentCoreWssUrl uses the same Fn::Join over Fn::Split('%3A', ':', arn) idiom for deploy-time substitution."

requirements-completed:
  - DEP-01 (container deployed to AgentCore Runtime in ap-northeast-1; live ARN hera_agent-GIsf2P4ImD)
  - DEP-02 (public WSS endpoint exposed via the presigner Lambda)
  - DEP-03 (full deploy pipeline-as-code re-runnable: terraform + push-image + cdk + tf-second-apply + build-widget + smoke; all six steps idempotent)
  - DEP-04 (TF + CDK Python hybrid IaC split delivered; D-24 honored: CDK owns ONLY the AgentCore Runtime resource, presigner is Terraform)
  - DEP-06 (region default ap-northeast-1; us-east-1 override path preserved through var.region everywhere)
  - DEM-01 (public HTTPS demo URL on *.cloudfront.net returns the polished widget; verified via curl GET returning the 'Hera Voice Agent' heading and the injected lambda-url URL in app.js)

requirements-partial:
  - DEM-02 (anonymous access path is reachable from the browser; Bedrock Sonic voice-loop closure blocked by an unrelated agent credential-injection gap; see "Open Items / Known Blockers" below)

# Metrics
duration: ~70 min
completed: 2026-05-06
---

# Phase 3 Plan 04: CDK AgentCore Stack + SigV4 Presigner + 8-Step Live Smoke Summary

**Live AgentCore Runtime hera_agent-GIsf2P4ImD ships in ap-northeast-1, gated by an anonymous-public Lambda Function URL presigner that mints 5-minute SigV4 WSS URLs to bridge the browser/AWS auth gap (Rule-4 architectural deviation against Plan 03-02 widget contract). 4 of 6 Phase 3 success criteria closed; the last 2 are partially blocked by an agent credential-injection gap (Phase 4 OBS work).**

## Performance

- **Duration:** ~70 min (Tasks 1-4 by prior executor + Tasks 5a/5b/5c/5 by this invocation)
- **Started:** 2026-05-06 (Task 5a)
- **Completed:** 2026-05-06T06:35Z (post second-pass apply + smoke probe)
- **Tasks:** 8 (Tasks 1-4 prior; 5a TF module, 5b prod-root wire, 5c widget contract update, plus the live deploy steps that surfaced the deviations below)
- **Files created:** 6 (4 widget_presigner module files + handler.py + this SUMMARY)
- **Files modified:** 14
- **AWS resources created:**
  - 1 CFn stack hera-agentcore (CDKToolkit + 1 BedrockAgentCore::Runtime)
  - 1 Lambda function hera-widget-presign-prod
  - 1 Lambda function URL (https://ijrovzxz4tts2tdo2w5yxqxho40fruyn.lambda-url.ap-northeast-1.on.aws/)
  - 1 Lambda exec role + inline policy
  - 1 CloudWatch log group /aws/lambda/hera-widget-presign-prod
  - CDK bootstrap stack CDKToolkit (12 sub-resources: ECR + S3 staging + IAM roles + SSM)

## Accomplishments

- **CDK stack hera-agentcore live in ap-northeast-1.** AWS::BedrockAgentCore::Runtime resource id `hera_agent-GIsf2P4ImD` references the multi-arch ECR image `hera-agent:214068b`. Stack `CREATE_COMPLETE` after the agentcore exec role was extended with ECR pull permissions (Rule-2 deviation #1).
- **Widget presigner Lambda live.** `hera-widget-presign-prod` (python3.12, 256 MB, 5s timeout) on Function URL `https://ijrovzxz4tts2tdo2w5yxqxho40fruyn.lambda-url.ap-northeast-1.on.aws/` mints 300-s presigned WSS URLs per request. CORS allow-origin restricted to `https://dg0w939ktclw6.cloudfront.net` (NOT `*`). IAM role grants `bedrock-agentcore:InvokeAgentRuntime` + `:InvokeAgentRuntimeWithWebSocketStream` scoped to the runtime ARN; zero wildcards (D-13).
- **Two-pass terraform apply lifecycle proven live.** First apply (Wave-1 + presigner with placeholder ARN) -> cdk deploy emits AgentCoreRuntimeArn -> `terraform apply -var "agentcore_runtime_arn=<arn>"` updates the Lambda env vars + IAM policy in-place. RUNBOOK now documents the 4-step lifecycle (D-25 amended).
- **Widget contract Rule-4 deviation shipped.** `frontend/app.js` switched from `__AGENTCORE_WSS_URL__` (direct WSS placeholder) to `__PRESIGN_URL__` (HTTPS Function URL). New `resolveWsUrl()` fetches the presign URL and unwraps `{url}` before opening the WebSocket. Local-dev path preserved via the `typeof __PRESIGN_URL__` guard. Presign-fetch errors flow through the existing `ws-connect-failed` WID-06 branch.
- **bin/smoke-deploy.sh is now an 8-step orchestrator** (was 6) covering the new Step 4 (second-pass tf apply), Step 5 (read presign_url), Step 7 (curl + jq-validate the presign Function URL response), Step 8 (drive `_smoke_deploy_probe.py` via PRESIGN_URL env to mirror browser flow exactly).
- **Presign URL mints valid signed URLs end-to-end.** `curl ${PRESIGN_URL}` returns `{"url": "wss://bedrock-agentcore.ap-northeast-1.amazonaws.com/runtimes/<encoded-arn>/ws?qualifier=DEFAULT&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=ASIA.../ap-northeast-1/bedrock-agentcore/aws4_request&X-Amz-Date=...&X-Amz-Expires=300&X-Amz-Signature=..."}`.
- **Widget served from CloudFront with the injected presign URL.** `curl https://dg0w939ktclw6.cloudfront.net/` returns the polished Hera widget; `curl .../app.js | grep lambda-url` returns 3 hits — sed-injection succeeded; CloudFront `/* ` invalidation cleared the previous cached app.js.
- **AgentCore data-plane authorization works.** WSS handshake reaches the runtime container (no more 403). The runtime returns 424 because the container itself fails on cold-start (see Open Items below).

## Task Commits

Each task committed atomically on `master`:

1. **Task 1: Scaffold infra/cdk/ + hera-agentcore CFn L1 stack** — `072054e` (feat) — pre-existing
2. **Task 2: bin/_smoke_deploy_probe.py** — `0893b2b` (feat) — pre-existing
3. **Task 3: bin/smoke-deploy.sh** — `449b446` (feat) — pre-existing
4. **Task 4: RUNBOOK Step 4 smoke paragraph** — `51d0f05` (docs) — pre-existing
5. **Task 5a: widget_presigner Terraform module** — `2ced2fc` (feat) — Rule-4 architectural addition
6. **Task 5b: wire widget_presigner into prod root + RUNBOOK 4-step lifecycle** — `c5b7f8c` (feat)
7. **Task 5c: widget contract Rule-4 update (presign+fetch flow)** — `774adfb` (feat)
8. **Bonus: drop CDKv1-only feature flag from cdk.json** — `214068b` (fix, Rule-1)
9. **Live-deploy deviations bundle** — `ab44397` (fix, four Rule-1/Rule-2/Rule-3 fixes)

## Live AWS Resource IDs

| Output / Identifier | Value |
|---------------------|-------|
| AgentCore Runtime ARN | `arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD` |
| AgentCore Runtime ID | `hera_agent-GIsf2P4ImD` |
| AgentCore Runtime status | `READY` |
| AgentCore Runtime version | `1` |
| Container image (ECR multi-arch) | `851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent:214068b` (manifest list `sha256:95d7d51e52e4e53a38a23f692d25cc0809e223628342852f027da2079ea6b43a`) |
| Presign Function URL | `https://ijrovzxz4tts2tdo2w5yxqxho40fruyn.lambda-url.ap-northeast-1.on.aws/` |
| Presign Lambda ARN | `arn:aws:lambda:ap-northeast-1:851725411875:function:hera-widget-presign-prod` |
| Presign Lambda exec role | `arn:aws:iam::851725411875:role/hera-widget-presign-prod-exec` |
| CloudFront widget URL | `https://dg0w939ktclw6.cloudfront.net` |
| CloudFront distribution | `E10K3B1L8PQ9EC` |
| CDK CloudFormation stack | `arn:aws:cloudformation:ap-northeast-1:851725411875:stack/hera-agentcore/0bc06dd0-4914-11f1-9976-061c6ad5cb0b` |

## Synthesized CloudFormation Template (hera-agentcore stack)

```yaml
Resources:
  Runtime:
    Type: AWS::BedrockAgentCore::Runtime
    Properties:
      AgentRuntimeArtifact:
        ContainerConfiguration:
          ContainerUri: 851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent:214068b
      AgentRuntimeName: hera_agent
      Description: Hera Apple Store voice agent (Pipecat + Nova 2 Sonic + KB).
      NetworkConfiguration:
        NetworkMode: PUBLIC
      ProtocolConfiguration: HTTP
      RoleArn: arn:aws:iam::851725411875:role/hera-agentcore-exec-prod
Outputs:
  AgentCoreRuntimeArn:    {Value: !GetAtt Runtime.AgentRuntimeArn}
  AgentCoreRuntimeId:     {Value: !GetAtt Runtime.AgentRuntimeId}
  AgentCoreWssUrl:        {Value: !Join ["", [...wss URL composed by Fn::Join over Fn::Split %3A...]]}
```

(Resource count: 1 BedrockAgentCore::Runtime + 1 CDK::Metadata. CDK bootstrap stack CDKToolkit added 12 separate resources for asset publishing.)

## Estimated v1 Cost (one-shot demo footprint)

- AgentCore Runtime: consumption-priced; idle = $0/hour, ~$0.20-1.00 per active conversation depending on session length and Sonic token volume. With concurrency capped by AWS service quota (default = 10) the worst-case 30-day instructor demo is bounded by Sonic input/output streaming + KB retrieve charges.
- Lambda presigner: 1M req/month free + free tier compute. Even at the maximum un-throttled 30 req/sec it stays under $0.50/month.
- ECR storage: ~150 MB image x $0.10/GB/month = $0.015/month.
- Lambda + AgentCore CloudWatch logs: pennies/month for instructor demo volume.
- CloudFront: well within the 1 TB/month + 10M req/month free tier.

**Estimated total per-month idle = ~$0.05; per-conversation = ~$0.20-1.00 dominated by Sonic. Well under the $5/day cap (D-29).**

## Decisions Made

See key-decisions in frontmatter. Notable in-execution observations:

- **AgentCore exec role missing ECR pull was the planning gap.** Plan 03-01 listed Sonic + CW Logs + KB only; AgentCore CFn validation also needs `ecr:GetAuthorizationToken` / `ecr:BatchGetImage` / `ecr:GetDownloadUrlForLayer`. Without them, CFn CREATE_FAILED on first deploy with a misleading "Access denied while validating ECR URI" message. Fix landed inline in commit `ab44397` (Rule-2: missing critical functionality).
- **Lambda reserved_concurrent_executions floor on a fresh-quota account is 10.** AWS rejects positive values that would push UnreservedConcurrentExecution below 10. The user-approved Q2 option (i) ("skip concurrency cap for v1") aligned with what AWS allowed; default switched from 5 to -1 (unreserved). Phase 4 OBS-04/OBS-05 will introduce per-IP and per-Lambda concurrency tooling alongside a quota increase.
- **Lambda Function URL CORS allow_methods accepts only the 6 standard verbs.** OPTIONS is auto-handled by Lambda and rejected by CreateFunctionUrlConfig with ValidationException. Same pattern would carry forward to any future browser-fronted Lambda we ship.
- **AgentCore data-plane action is `InvokeAgentRuntimeWithWebSocketStream`.** Distinct from synchronous `InvokeAgentRuntime`. Both must be granted on the presigner role for the WSS upgrade to authorize. Live error message at the AWS data-plane was the primary source of truth for the action name.
- **CDKv2 strips `@aws-cdk/core:enableStackNameDuplicates` and the related v1-era flags.** Empty `context: {}` in cdk.json keeps the file structurally present without breaking synth.
- **Two-pass terraform apply chosen over CDK->TF data lookup.** The cleaner "TF reads CDK output via aws_lambda_invocation or external data source" alternative would couple the Wave-1 apply to a live cdk-outputs.json file. The two-pass pattern keeps the dependency direction matching D-24 (TF source-of-truth) cleanly: TF can apply with placeholder defaults, then update in-place when the CDK output is available.

## Deviations from Plan (auto-fixed during execution)

### Rule-4 architectural additions (user pre-approved before this invocation)

**1. Add Lambda Function URL presigner (Q1 option A)**
- **Found during:** prior planner risk surfacing; user explicitly approved before the executor was spawned.
- **Issue:** Browsers cannot SigV4-sign a WebSocket upgrade. The widget needs an auth bridge.
- **Fix:** New `infra/modules/widget_presigner/` Terraform module — Lambda + Function URL + IAM. Module exports `presign_url`. CDK still owns ONLY the AgentCore Runtime (D-24 honored).
- **Files added:** `infra/modules/widget_presigner/{versions,variables,main,outputs}.tf` + `src/handler.py`.
- **Commits:** `2ced2fc`, `c5b7f8c`.

**2. Skip per-Lambda concurrency cap for v1 (Q2 option (i))**
- **Found during:** prior planner; user explicitly approved before the executor was spawned.
- **Issue:** AWS account has 10-concurrency floor for UnreservedConcurrentExecution; reserved_concurrent_executions=5 would violate it.
- **Fix:** Default to -1 (unreserved). Phase 4 OBS-04/OBS-05 owns per-IP and per-Lambda throttling.
- **Commit:** `ab44397`.

**3. Widget contract change: __AGENTCORE_WSS_URL__ -> __PRESIGN_URL__**
- **Found during:** Rule-4 architectural decision Q1 acceptance.
- **Issue:** Plan 03-02's must_haves contracted on `__AGENTCORE_WSS_URL__` direct-WSS injection. The presign architecture changes the wire format.
- **Fix:** New `__PRESIGN_URL__` placeholder; `resolveWsUrl()` async helper fetches the URL before opening the socket; presign-fetch errors flow through the existing `ws-connect-failed` WID-06 branch (D-28 trigger preserved). `bin/build-widget.sh` sed-replace target switched. Local-dev path preserved via the `typeof __PRESIGN_URL__` guard.
- **Commit:** `774adfb`.

### Rule-1 / Rule-2 fixes (auto-applied during live deploy)

**4. [Rule-2 missing critical functionality] AgentCore exec role lacks ECR pull**
- **Found during:** First `cdk deploy` -- CREATE_FAILED on AWS::BedrockAgentCore::Runtime with `Access denied while validating ECR URI`.
- **Issue:** Plan 03-01's `agentcore_iam` inline policy granted Sonic bidi + CW logs + KB-attach; AgentCore Runtime CFn validator also needs ECR pull permissions on the runtime exec role.
- **Fix:** Added two statements to `infra/modules/agentcore_iam/main.tf` -- (a) `ECRGetAuthorizationToken` Action `ecr:GetAuthorizationToken` Resource `*` (documented IAM exception identical to the CloudWatch PutMetricData pattern), and (b) `ECRPullHeraAgent` Actions `ecr:BatchGetImage` + `ecr:GetDownloadUrlForLayer` scoped to `arn:aws:ecr:<region>:<acct>:repository/hera-agent`. Zero new wildcards beyond the documented exception.
- **Commit:** `ab44397`.

**5. [Rule-3 blocker] Lambda reserved concurrency below account floor**
- **Found during:** First terraform apply with the new widget_presigner module.
- **Issue:** Account UnreservedConcurrentExecution floor = 10; setting reserved_concurrent_executions = 5 was rejected with InvalidParameterValueException.
- **Fix:** Default `var.reserved_concurrent_executions` switched from `5` to `-1` (unreserved). Q2 user-approved option (i) was already to defer per-function cap; this is the in-tree mechanism.
- **Commit:** `ab44397`.

**6. [Rule-1 bug] Lambda Function URL CORS allow_methods rejected OPTIONS**
- **Found during:** Second terraform apply attempt.
- **Issue:** AWS validates `allow_methods` against the 6 HTTP verbs (GET/POST/PUT/DELETE/HEAD/PATCH) plus `*`. OPTIONS is preflight-handled by Lambda automatically and triggers ValidationException if listed.
- **Fix:** `infra/modules/widget_presigner/main.tf` cors block now uses `allow_methods = ["GET"]` only.
- **Commit:** `ab44397`.

**7. [Rule-1 bug] AgentCore data-plane action mismatch**
- **Found during:** First WSS handshake attempt with the freshly-issued presigned URL -- 403 with the error `not authorized to perform: bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream`.
- **Issue:** Module initially granted only `bedrock-agentcore:InvokeAgentRuntime`; the WebSocket data-plane requires the distinct `:InvokeAgentRuntimeWithWebSocketStream` action.
- **Fix:** Added the WebSocketStream action to the same scoped IAM statement (still bound to the specific runtime ARN; zero wildcards).
- **Commit:** `ab44397`.

**8. [Rule-1 bug] CloudFront create-invalidation multi-path form failed on Windows bash**
- **Found during:** First `bin/build-widget.sh` run -- `aws cloudfront create-invalidation --paths "/index.html" "/app.js" ...` returned InvalidArgument.
- **Issue:** Argument splitting on Windows Git Bash; the multi-path form was malformed by the time it reached the AWS CLI.
- **Fix:** Replaced with single `--paths "/*"` which works cross-platform and counts as ONE invalidation against the 1000/month free-tier quota.
- **Commit:** `ab44397`.

**9. [Rule-1 bug] CDKv1-only feature flag breaks CDKv2 synth**
- **Found during:** First `cdk synth` attempt.
- **Issue:** `@aws-cdk/core:enableStackNameDuplicates` was a CDKv1 toggle; CDKv2 fails synth with UnsupportedFeatureFlag.
- **Fix:** Drop the legacy flags; empty `context: {}` keeps the file structurally present.
- **Commit:** `214068b`.

## Open Items / Known Blockers

### CRITICAL — Phase-3 success criterion #2 ("browser → AgentCore voice loop") is BLOCKED by an agent credential-injection gap

**Symptom:** WSS handshake authenticates correctly via the presign flow, AgentCore Runtime status is `READY`, AgentCore accepts the request and tries to start the container, but **the container fails on cold-start before any logs reach `/aws/bedrock-agentcore/hera-agent`**. AgentCore returns `HTTP 424 Failed Dependency: An error occurred when starting the runtime.` to the WSS client. The CloudWatch log group has `storedBytes=0` -- the container never reaches the `loguru` logger.

**Root cause (high confidence):**
- `agent/hera_agent/config.py:12` reads `os.environ["HERA_KB_ID"]` at import time, which raises `KeyError` if not set.
- `agent/hera_agent/pipeline.py:48-50` reads `os.environ["AWS_ACCESS_KEY_ID"]` and `os.environ["AWS_SECRET_ACCESS_KEY"]` at every WS connection. AWSNovaSonicLLMService uses StaticCredentialsResolver internally and does NOT follow the boto3 default chain (Pitfall B from Phase 2).
- AgentCore Runtime gives the container the exec role's credentials via instance-metadata-style injection (the runtime issues IMDSv2 tokens to the container per `metadataConfiguration.requireMMDSV2 = true` in the live runtime config). It does NOT inject credentials as env vars, and there is no CFn property on AWS::BedrockAgentCore::Runtime for env-var injection of secrets either.
- Result: the container imports `hera_agent.config` -> KeyError on HERA_KB_ID -> uvicorn worker dies before the `/ping` health probe ever returns 200, and AgentCore reports the runtime as failed.

**Resolution paths (Phase 4 / follow-up plan owns these):**

1. **Refactor agent for IMDS-resolved boto3 default chain** (preferred long-term): drop the `os.environ["AWS_ACCESS_KEY_ID"]` requirement from `pipeline.py` and let Pipecat's AWSNovaSonicLLMService accept boto3's default credential resolver. This requires verifying that Pipecat's StaticCredentialsResolver wrapper supports a "use default chain" signal, OR that AWSNovaSonicLLMService has a code path that uses the boto3 default chain. Phase 2 D-21 / Pitfall B locked StaticCredentialsResolver because docker-compose dev couldn't mount IMDS. AgentCore Runtime DOES provide IMDS, so the live deploy path can use the default chain even though docker-compose dev still uses static creds.

2. **Inject HERA_KB_ID as a CFn-property env var on the AgentCore Runtime resource.** The AWS::BedrockAgentCore::Runtime CFn schema may support `Environment` (the planner flagged `[needs-verification]` here). If it does, adding `Environment: { Variables: { HERA_KB_ID: !ImportValue hera-kb-id, ... } }` to the CDK stack would resolve HERA_KB_ID injection. The AWS_ACCESS_KEY_ID injection would still need fix #1 because the AgentCore role credentials are time-bound STS sessions, not durable env-var values.

3. **Sidecar entrypoint that bridges IMDS -> env vars.** Add a small `bin/agentcore-entrypoint.sh` to the container that calls IMDSv2 token + GetSessionToken, exports AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN, then `exec`s uvicorn. Workshop overengineering but unblocks v1 quickly.

**Recommendation for Phase 4 OBS work:** Option 1 (refactor for default chain) closes this cleanly without ongoing maintenance cost. The aws-samples reference repo (`aws-samples/sample-nova-sonic-websocket-agentcore`) is the canonical source for whether AWSNovaSonicLLMService accepts IMDS-resolved creds; the executor here did not have time to mine the reference and add a Pipecat patch.

### Other open items

- **AgentCore concurrency cap (D-30 originally said 2; Phase 3 ships D-30 as a Service Quota, not a resource property).** The CFn schema confirms there is no `MaxConcurrentSessions` property. Account default quota = 10 concurrent runtime sessions. Quota request to lower to 2 (workshop demo) or raise to 50+ (instructor cohort) is an AWS console action, not IaC. Phase 4 OBS-04/OBS-05 owns per-IP rate limiting on the presigner Lambda alongside this quota lever.

- **Sonic foundation-model ARN runtime gate** (Plan 03-01 deferred). Not yet exercised because the container never reaches the LLM init step; will be confirmed once the credential-injection blocker resolves. The IAM policy already grants `bedrock:InvokeModelWithBidirectionalStream` on `arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.nova-sonic-v1:0`.

- **CloudWatch dashboards/alarms for AgentCore runtime + presigner Lambda** (Phase 4 OBS-01..03).

- **`cleanup-verify.sh` script** (Phase 4 success criterion). Phase 3 cleanup ORDER is documented in RUNBOOK (CDK destroy first, terraform destroy second).

- **CDK `current credentials could not be used to assume 'cdk-...-deploy-role-...'` warning during deploy.** CDK printed this when the IAM root user (current credentials in this environment) lacks `sts:AssumeRole` on the dedicated CDK deploy roles. CDK fell back to root credentials and the deploy succeeded. For production / multi-operator setups Phase 4 should bootstrap CDK with a role-trust policy that allows the operator's IAM user to assume the deploy roles.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: anonymous-public-lambda | infra/modules/widget_presigner/main.tf | Lambda Function URL `AuthType=NONE` is a NEW public surface. Mitigations in v1: CORS allow-origin pinned to the CloudFront domain (browser-side), 5-minute presign TTL (server-side), zero-wildcard IAM scope. Phase 4 must add per-IP rate limit + cost circuit breaker (OBS-04/OBS-05). |
| threat_flag: ecr-token-wildcard | infra/modules/agentcore_iam/main.tf | `ecr:GetAuthorizationToken` Resource=* is the AWS-published least-privilege pattern (the API target is the registry, not a repo) but it IS a documented exception to D-13 zero-wildcard. Same shape as the existing `cloudwatch:PutMetricData` exception. |

## User Setup Required

- **Phase 4 follow-up plan needs to address the agent credential-injection gap** (see "Open Items" above) before the browser-driven voice loop can actually close.
- No further action on Plan 03-04 itself — all infra is live and the presign path is reachable.

## Self-Check

Files claimed as created/modified verified present:

- `infra/modules/widget_presigner/{versions,variables,main,outputs}.tf` — all 4 present
- `infra/modules/widget_presigner/src/handler.py` — present, parses cleanly via `python -c "import ast; ast.parse(...)"`
- `infra/cdk/cdk.json` — modified (CDKv1 flags removed)
- `infra/envs/prod/{main,variables,outputs,.terraform.lock.hcl}.tf` — all modified
- `infra/modules/agentcore_iam/main.tf` — modified (ECR pull statements added)
- `frontend/app.js` — modified (PRESIGN_URL constant + resolveWsUrl())
- `bin/build-widget.sh` — modified (sed-replace target switched + /* invalidation)
- `bin/_smoke_deploy_probe.py` — modified (PRESIGN_URL env path)
- `bin/smoke-deploy.sh` — modified (8-step lifecycle)
- `RUNBOOK.md` — modified (4-step lifecycle + Step 3.5)

Commits verified in `git log`:
- `2ced2fc`, `c5b7f8c`, `774adfb`, `214068b`, `ab44397` — all present and reachable from HEAD.

Live AWS resources verified via AWS CLI:
- AgentCore Runtime `hera_agent-GIsf2P4ImD` `status=READY` (verified via `aws bedrock-agentcore-control get-agent-runtime`).
- Lambda `hera-widget-presign-prod` exists; Function URL returns `200` with `{"url": "wss://..."}` (verified via `curl`).
- IAM policy on `hera-widget-presign-prod-exec` contains both `InvokeAgentRuntime` and `InvokeAgentRuntimeWithWebSocketStream` actions scoped to the runtime ARN (verified via `aws iam get-role-policy`).
- Widget app.js on CloudFront contains the injected lambda-url URL (3 grep hits).

Live AgentCore voice loop end-to-end NOT verified — blocked by the agent credential-injection gap documented under "Open Items / Known Blockers". The infrastructure layer is complete; the agent application layer needs a follow-up plan.

## Self-Check: PASSED (infrastructure scope; live voice-loop closure deferred)

---
*Phase: 03-agentcore-deploy-web-widget-public-demo-url*
*Plan: 04*
*Completed: 2026-05-06*
