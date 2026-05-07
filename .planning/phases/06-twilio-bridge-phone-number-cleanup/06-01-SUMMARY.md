---
phase: 06-twilio-bridge-phone-number-cleanup
plan: 01
subsystem: terraform-infra
tags: [twilio, app-runner, iam, ecr, terraform]
dependency_graph:
  requires:
    - infra/modules/widget_presigner (analog only — IAM trust pattern + own log group + chicken-and-egg)
    - infra/modules/agentcore_iam (analog only — confused-deputy + ECR-pull pattern)
    - infra/modules/ecr (analog only — IMMUTABLE + scan_on_push + lifecycle)
    - infra/envs/prod/main.tf (existing module wiring shape; new block appended after observability)
    - infra/envs/prod/variables.tf (existing agentcore_runtime_arn chicken-and-egg analog)
    - infra/envs/prod/outputs.tf (existing presign_url description-prose convention)
  provides:
    - infra/modules/twilio_bridge (new TF module)
    - module.twilio_bridge.service_url (App Runner public hostname; consumed by output twilio_bridge_wss_url)
    - module.twilio_bridge.ecr_repository_url (consumed by Plan 06-03 push-bridge-image.sh)
    - module.twilio_bridge.instance_role_arn (consumed by debug/RUNBOOK)
    - module.twilio_bridge.log_group_name (consumed by Plan 06-03 cleanup-verify-twilio.sh)
    - root output twilio_bridge_wss_url (consumed by Plan 06-03 RUNBOOK paste-block)
    - root output twilio_bridge_ecr_repository_url (consumed by Plan 06-03 push-bridge-image.sh)
    - root variable twilio_auth_token_secret_arn (Plan 06-03 RUNBOOK pre-creates the Secrets Manager secret + operator pastes the Twilio Auth Token)
    - root variable twilio_bridge_image_tag (chicken-and-egg; Plan 06-03 second-pass apply pins SHA after push-bridge-image.sh)
  affects:
    - none (all v1 module blocks bit-identical per D-64)
tech-stack:
  added:
    - aws_apprunner_service (Terraform AWS provider 6.43.0; D-56 REVISED compute target)
    - aws_apprunner_auto_scaling_configuration_version (min_size=0 scale-to-zero LOCKED per D-56)
  patterns:
    - chicken-and-egg image_identifier substitution (Pattern S10) — empty image_tag -> ECR_PUBLIC public.ecr.aws/aws-containers/hello-app-runner:latest placeholder; pinned tag -> private bridge ECR
    - confused-deputy aws:SourceAccount on both trust policies (Pattern S1)
    - own log group with explicit retention + scoped logs:* writes (Pattern S3)
    - zero IAM wildcards except documented ecr:GetAuthorizationToken AWS-mandate (Pattern S2)
key-files:
  created:
    - infra/modules/twilio_bridge/versions.tf
    - infra/modules/twilio_bridge/variables.tf
    - infra/modules/twilio_bridge/main.tf
    - infra/modules/twilio_bridge/iam.tf
    - infra/modules/twilio_bridge/ecr.tf
    - infra/modules/twilio_bridge/outputs.tf
  modified:
    - infra/envs/prod/main.tf (append module "twilio_bridge" block after observability; +22 lines, 0 modifications)
    - infra/envs/prod/variables.tf (append twilio_auth_token_secret_arn + twilio_bridge_image_tag; +13 lines, 0 modifications)
    - infra/envs/prod/outputs.tf (append twilio_bridge_wss_url + twilio_bridge_ecr_repository_url; +10 lines, 0 modifications)
decisions:
  - D-56 REVISED locked: App Runner with min_size=0 (scale-to-zero) is the bridge compute target; HCL min_size variable defaults to 0 with description marking it LOCKED
  - D-65 max_size=2 cap: matches AgentCore concurrency cap=2 (D-30); HCL max_size variable defaults to 2
  - D-66 instance role grants ONLY bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream (no synchronous InvokeAgentRuntime — bridge only opens WSS) on the EXACT live runtime ARN
  - D-67 Twilio Auth Token via Secrets Manager: variable is the SECRET ARN (sensitive=true); App Runner runtime_environment_secrets injects the actual token at runtime; no token in plaintext IaC, env vars, or images
  - D-63 force_delete=true on bridge ECR: bridge is short-lived/re-creatable; cleanup quy trinh requires `terraform destroy` to drop repo cleanly even with images present
  - Chicken-and-egg deviates from widget_presigner's "placeholder ARN" pattern: bridge uses public.ecr.aws/aws-containers/hello-app-runner:latest as the placeholder image (App Runner needs a runnable image to create the service, not just an ARN); ECR_PUBLIC type matches public ECR identifier
metrics:
  duration_minutes: 18
  completed_date: 2026-05-07
  task_count: 3
  files_created: 6
  files_modified: 3
  resources_in_module: 9
  iam_wildcards: 1 (only documented ecr:GetAuthorizationToken AWS-mandate exception in access role)
---

# Phase 6 Plan 01: Twilio Bridge Terraform Module + Root Wiring Summary

**One-liner:** Twilio bridge IaC scaffolding — `infra/modules/twilio_bridge/` (App Runner + 2 IAM roles + ECR + log group, 9 resources) plus 3 root-file extensions in `infra/envs/prod/` wiring the module with chicken-and-egg image-tag pattern; `terraform validate` passes; v1 system bit-identical per D-64.

## What Was Built

Six new Terraform files under `infra/modules/twilio_bridge/`:

| File | Resources/contents | Purpose |
|------|-------------------|---------|
| `versions.tf` | terraform >= 1.9, AWS ~> 6.27 | Provider pin (no archive provider; bridge ships OCI image not Lambda zip) |
| `variables.tf` | 14 input variables | Including `twilio_auth_token_secret_arn` (sensitive D-67), `min_size=0` LOCKED D-56, `max_size=2` D-65 cap |
| `main.tf` | `aws_apprunner_service` + `aws_apprunner_auto_scaling_configuration_version` | Long-running bridge compute; scale-to-zero; chicken-and-egg image_identifier (Pattern S10) |
| `iam.tf` | 2 IAM roles + 2 inline policies + own CloudWatch log group + 4 data blocks | bridge_instance (tasks.apprunner) + bridge_access (build.apprunner); confused-deputy + zero-wildcard scoping |
| `ecr.tf` | `aws_ecr_repository` + `aws_ecr_lifecycle_policy` | hera-twilio-bridge IMMUTABLE + scan_on_push + force_delete=true (D-63) |
| `outputs.tf` | 6 outputs | service_url, service_arn, ecr_repository_url, ecr_repository_arn, instance_role_arn, log_group_name |

Three root-file extensions in `infra/envs/prod/` (pure appends, zero modifications to v1 lines):

| File | Lines added | Purpose |
|------|-------------|---------|
| `main.tf` | +22 (block 84-104) | `module "twilio_bridge"` after observability; forwards region/account_id/runtime_arn/secret_arn/image_tag |
| `variables.tf` | +13 (block 25-37) | `twilio_auth_token_secret_arn` (sensitive=true, default="") + `twilio_bridge_image_tag` (default="") |
| `outputs.tf` | +10 (block 81-90) | `twilio_bridge_wss_url` (wss:// rewrite of App Runner service_url + /twilio path) + `twilio_bridge_ecr_repository_url` |

**Total Terraform resources at apply:** 9 (matches `must_haves.truths` plan-diff target)

## Commits

| # | Hash | Message |
|---|------|---------|
| 1 | `f87a69d` | `feat(06-01): scaffold twilio_bridge module — versions/variables/ecr/outputs` |
| 2 | `1b4b8f9` | `feat(06-01): add twilio_bridge IAM + App Runner service + auto-scaling config` |
| 3 | `60dbcdb` | `feat(06-01): wire twilio_bridge module into infra/envs/prod root + terraform validate passes` |

## Acceptance Gate Results

| Gate | Result | Evidence |
|------|--------|----------|
| 6 module .tf files exist | PASS | `ls infra/modules/twilio_bridge/` returns ecr.tf, iam.tf, main.tf, outputs.tf, variables.tf, versions.tf |
| `terraform fmt -check` | PASS | exit 0 across all 6 module files + 3 root files |
| Module variable count = 14 | PASS | `grep -c '^variable ' infra/modules/twilio_bridge/variables.tf` = 14 |
| Module output count = 6 | PASS | `grep -c '^output ' infra/modules/twilio_bridge/outputs.tf` = 6 |
| `iam.tf` resource count = 5 | PASS | 2 roles + 2 inline policies + 1 log group |
| `iam.tf` data block count = 4 | PASS | 2 trust policies + 2 inline policies |
| Both trust principals correct | PASS | tasks.apprunner.amazonaws.com (instance) + build.apprunner.amazonaws.com (access) |
| confused-deputy aws:SourceAccount | PASS | grep count = 3 (one per trust policy + one per condition) |
| InvokeAgentRuntimeWithWebSocketStream scoped | PASS | scoped to `var.agentcore_runtime_arn` |
| secretsmanager:GetSecretValue scoped | PASS | scoped to `var.twilio_auth_token_secret_arn` |
| Wildcard audit | PASS | exactly 1 documented Resource=* (ecr:GetAuthorizationToken in access role only) |
| `aws_apprunner_service` shape | PASS | `is_publicly_accessible=true`, `/ping` health, port 8080, runtime_environment_secrets injects TWILIO_AUTH_TOKEN |
| Chicken-and-egg placeholder | PASS | `public.ecr.aws/aws-containers/hello-app-runner:latest` literal present in main.tf |
| min_size=0 / max_size=2 plumbed | PASS | both literals present in variables.tf with proper descriptions; `var.min_size` referenced in aws_apprunner_auto_scaling_configuration_version |
| ECR IMMUTABLE + scan_on_push + force_delete | PASS | all three literals present in ecr.tf |
| Root variables: 6 total (4 original + 2 new) | PASS | grep count = 6 |
| Root output diff = pure additions | PASS | `git diff` shows zero `-` lines (no removals) |
| v1 module/variable/output lines bit-identical | PASS | `git diff infra/envs/prod/{main,variables,outputs}.tf` shows ONLY appended blocks below the existing observability/agentcore_runtime_arn/observability_billing_alarm_arn anchors |
| `terraform init` succeeds (recognizes twilio_bridge module) | PASS | "Initializing modules... twilio_bridge in ../../modules/twilio_bridge" |
| `terraform validate` exits 0 | PASS | "Success! The configuration is valid." |
| No emojis | PASS | `grep -lP '[\\x{1F300}-\\x{1FAFF}\\x{2600}-\\x{27BF}]'` returns nothing for all 6 module + 3 root files |

## Threat Model Verification

All 10 STRIDE entries from the plan's `<threat_model>` are mitigated by the IaC shape:

| Threat ID | Disposition | IaC verification |
|-----------|-------------|------------------|
| T-06-01-01 EoP instance role | mitigate | iam.tf inline statements: 3 SIDs (InvokeAgentRuntimeWebSocketStream + ReadTwilioAuthToken + BridgeOwnLogs); zero `Resource = "*"` in instance role; explicit ARN scoping on every Action |
| T-06-01-02 EoP access role ECR pull | mitigate | iam.tf access role inline: ECR pull actions scoped to `aws_ecr_repository.bridge.arn`; only documented `ecr:GetAuthorizationToken` Resource=* exception (AWS IAM model mandate; same pattern accepted in v1 agentcore_iam) |
| T-06-01-03 cross-account confused-deputy | mitigate | both trust policies: `condition { StringEquals aws:SourceAccount = var.account_id }` (Pattern S1) |
| T-06-01-04 Twilio Auth Token disclosure | mitigate | variable `twilio_auth_token_secret_arn` declared `sensitive = true`; main.tf uses `runtime_environment_secrets` (Secrets Manager fetch at runtime) — token NEVER in plaintext IaC, env vars, or images |
| T-06-01-05 spoofing public ingress | accept (Plan 06-01) / mitigate (Plan 06-02) | `is_publicly_accessible = true` is structurally required for Twilio dial-in; signature validation owned by Plan 06-02 (X-Twilio-Signature HMAC inside container); IaC layer cannot authenticate the caller |
| T-06-01-06 DoS fan-out | mitigate | `max_size = 2` (var default; D-65 cap matches AgentCore D-30); per-instance max_concurrency=5 -> 10 simultaneous WS ceiling, all bounded by Phase 4 $5/day billing alarm |
| T-06-01-07 image supply-chain | mitigate | ECR `image_tag_mutability = IMMUTABLE`, `scan_on_push = true`; access role auth required for private image pulls; first-apply placeholder is AWS-published `aws-containers/hello-app-runner` (verified vendor) replaced on second-pass |
| T-06-01-08 cross-tenant log readability | mitigate | bridge owns `aws_cloudwatch_log_group.bridge` `/aws/apprunner/hera-twilio-bridge-prod`; inline policy `BridgeOwnLogs` scopes `logs:*` to ONLY this log group ARN — bridge cannot write to v1 log groups |
| T-06-01-09 bridge identity pivots to v1 | mitigate | bridge instance role IAM contains ZERO actions on v1 resources (no bedrock:Retrieve, no s3:*, no cloudfront:*, no apigateway:*); v1 attack surface unreachable from bridge identity |
| T-06-01-10 v1 system drift | mitigate | `git diff infra/envs/prod/{main,variables,outputs}.tf` shows ONLY pure appends (45 insertions, 0 deletions, 0 modifications); D-64 honored |

## Live AWS State

UNCHANGED. This plan executed file-side IaC scaffolding only — no `terraform apply`, no `aws ...`, no `cdk ...`. Live AgentCore Runtime (`hera_agent-GIsf2P4ImD` version=3 status=READY), KB `BKXE19AH89`, CloudFront widget `dg0w939ktclw6.cloudfront.net`, observability dashboard, $5/day billing alarm — all preserved bit-identical.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Worktree path correction for file writes**
- **Found during:** Task 1 commit
- **Issue:** Initial Write tool calls used `C:/Users/trant/projects/hera/infra/modules/twilio_bridge/` which is the main repo path, not the worktree. Files landed in main repo working tree and were committed to `master`. Worktree mode requires file paths under `C:/Users/trant/projects/hera/.claude/worktrees/agent-ada99b5a366cad313/`.
- **Fix:** Reverted the accidental master commit `85b59bd` via a non-destructive `git revert` (creates new commit `61709f0`, never rewrites history per #2924 prohibition); rewrote all 4 Task 1 files at the correct worktree path; verified worktree HEAD is on `worktree-agent-ada99b5a366cad313` for every subsequent commit.
- **Files affected:** infra/modules/twilio_bridge/{versions,variables,ecr,outputs}.tf (recreated at worktree path)
- **Commits:** `f87a69d` (Task 1 redone correctly in worktree); `61709f0` (revert in main repo, creates new commit; pre-existing master state preserved)
- **Process improvement:** All subsequent Bash `cd` commands and Write absolute paths used the worktree path explicitly.

### Verification Deferrals

**1. terraform plan dry-run with live AWS credentials**
- **Acceptance gate:** `cd infra/envs/prod && terraform plan -var=... | grep -q '9 to add, 0 to change, 0 to destroy'`
- **Status:** DEFERRED — executor environment lacks AWS credentials. The agent-cwd separation prevented credential reuse from main repo's AWS profile.
- **Why deferred is safe:**
  1. The strict `<verify><automated>` gate (`terraform validate`) PASSED exit 0.
  2. `terraform init` PASSED — module recognized (`twilio_bridge in ../../modules/twilio_bridge`).
  3. The 9-resource count was verified by `grep -c '^resource '` across module files (matches expected: 2 in main.tf + 5 in iam.tf + 2 in ecr.tf = 9).
  4. v1 immutability verified by `git diff --stat` showing 45 insertions / 0 deletions / 0 modifications across the 3 root files.
  5. Plan 06-04 IS the live-deploy plan; the operator running 06-04 will execute `terraform plan` with their credentials and surface any drift before `terraform apply`. This is the natural live drift-catch gate.
- **Re-runnable command:** When AWS credentials are available, run from the project root:
  ```
  cd infra/envs/prod
  TF_VAR_twilio_auth_token_secret_arn="arn:aws:secretsmanager:ap-northeast-1:851725411875:secret:hera/twilio/auth-token-PLACEHOLDER" \
    terraform plan -var=agentcore_runtime_arn=arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD -no-color
  ```
  Expected summary: `Plan: 9 to add, 0 to change, 0 to destroy.`

## Hand-offs

### To Plan 06-02 (parallel, file-disjoint)
Container source code lives under `infra/modules/twilio_bridge/src/` + `Dockerfile` + `pyproject.toml` + `uv.lock`. None of those paths overlap with this plan's outputs. The bridge needs to:
- Expose `/ping` on port 8080 (matches `health_check_configuration.path` set here).
- Read `AWS_REGION` + `AGENTCORE_RUNTIME_ARN` from env vars (set by `runtime_environment_variables`).
- Read `TWILIO_AUTH_TOKEN` from env (Secrets Manager-injected via `runtime_environment_secrets`).
- Implement `/twilio` WebSocket route (matches root output `twilio_bridge_wss_url` path).

### To Plan 06-03 (file-side)
- `bin/push-bridge-image.sh` consumes `terraform output -raw twilio_bridge_ecr_repository_url`.
- `bin/cleanup-verify-twilio.sh` checks for App Runner service `hera-twilio-bridge-prod`, ASC `hera-twilio-bridge-asc-prod`, ECR repo `hera-twilio-bridge`, IAM roles `hera-twilio-bridge-{instance,access}-prod`, log group `/aws/apprunner/hera-twilio-bridge-prod` — all names match those declared in this module's locals + ecr.tf.
- RUNBOOK paste-block captures `terraform output -raw twilio_bridge_wss_url` for the Twilio TwiML Bin `<Stream url=...>`.

### To Plan 06-04 (live deploy)
- 4-step lifecycle (mirrors Phase 3 D-25): (1) `terraform apply` with empty image_tag (App Runner uses placeholder image; service comes up healthy on /ping for the placeholder hello-app-runner), (2) `bin/push-bridge-image.sh` lands real bridge image to ECR, (3) operator pre-creates Secrets Manager secret `hera/twilio/auth-token` and pastes Twilio Auth Token, (4) `terraform apply -var=twilio_bridge_image_tag=<sha> -var=twilio_auth_token_secret_arn=<arn>` second-pass — App Runner does in-place service update to swap image_identifier (no replacement).
- Operator-only steps (Twilio side): purchase phone number, create TwiML Bin with `<Connect><Stream url="wss://...awsapprunner.com/twilio"/>`, point Voice webhook at TwiML Bin URL.
- Smoke: dial number, speak, expect Sonic response within ~3s of utterance (Sonic + KB latency dominates; bridge cold start is ~1-3s and only affects first call after idle).

## Self-Check: PASSED

**Files:**
- FOUND: infra/modules/twilio_bridge/versions.tf
- FOUND: infra/modules/twilio_bridge/variables.tf
- FOUND: infra/modules/twilio_bridge/main.tf
- FOUND: infra/modules/twilio_bridge/iam.tf
- FOUND: infra/modules/twilio_bridge/ecr.tf
- FOUND: infra/modules/twilio_bridge/outputs.tf
- FOUND: infra/envs/prod/main.tf (modified)
- FOUND: infra/envs/prod/variables.tf (modified)
- FOUND: infra/envs/prod/outputs.tf (modified)

**Commits:**
- FOUND: f87a69d feat(06-01): scaffold twilio_bridge module — versions/variables/ecr/outputs
- FOUND: 1b4b8f9 feat(06-01): add twilio_bridge IAM + App Runner service + auto-scaling config
- FOUND: 60dbcdb feat(06-01): wire twilio_bridge module into infra/envs/prod root + terraform validate passes

---

*Plan completed: 2026-05-07T09:19:26Z*
*Phase 6 Wave 1 — Plan 06-01 of 4*
*Next plan: 06-02 (Plan 06-02 is in Wave 1 — file-disjoint parallel; bridge container source code)*
