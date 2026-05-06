# Phase 4: Observability, Cost Control, Cleanup - Pattern Map

**Mapped:** 2026-05-06
**Files analyzed:** 11 (3 new sources + 8 modifications across 3 plans)
**Analogs found:** 11 / 11

## File Classification

| New/Modified File | Plan | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|------|-----------|----------------|---------------|
| `agent/hera_agent/main.py` (modify) | 04-01 | controller (FastAPI route) | request-response | self (`@app.get("/ping")` lines 27-33) | exact (in-file) |
| `agent/hera_agent/pipeline.py` (modify, optional) | 04-01 | service (Pipecat adapter) | request-response | self (`run_pipeline` lines 74-147) | exact (in-file) |
| `RUNBOOK.md` (modify, 04-01 deploy section) | 04-01 | docs (operator runbook) | static text | `RUNBOOK.md` `## Phase 3: AgentCore deploy` lines 339-485 | exact |
| `infra/modules/observability/versions.tf` (new) | 04-02 | TF module config | static | `infra/modules/widget_hosting/versions.tf` lines 1-10 | exact |
| `infra/modules/observability/variables.tf` (new) | 04-02 | TF module config | static | `infra/modules/agentcore_iam/variables.tf` lines 1-21 | exact |
| `infra/modules/observability/main.tf` (new) | 04-02 | TF module body | declarative | `infra/modules/agentcore_iam/main.tf` lines 49-52 (log group) + `widget_hosting/main.tf` shape | role-match |
| `infra/modules/observability/outputs.tf` (new) | 04-02 | TF module config | static | `infra/modules/widget_hosting/outputs.tf` lines 1-25 | exact |
| `infra/envs/prod/main.tf` (modify) | 04-02 | TF root | declarative | self (lines 27-30 `module "widget_hosting"`) | exact (in-file) |
| `infra/envs/prod/outputs.tf` (modify, optional) | 04-02 | TF root | static | self (lines 51-69) | exact (in-file) |
| `bin/cleanup-verify.sh` (new) | 04-03 | utility (verify script) | request-response (read-only AWS) | `bin/verify-kb.sh` lines 1-121 | exact |
| `RUNBOOK.md` (modify, 04-03 cleanup section) | 04-03 | docs (operator runbook) | static text | `RUNBOOK.md` `## Cleanup` lines 195-217 + Phase 3 cleanup-order lines 476-485 | exact |

## Pattern Assignments

### `agent/hera_agent/main.py` (modify) — Plan 04-01

**Analog:** `agent/hera_agent/main.py` itself (existing `/ping` shows the FastAPI shape).

**Imports pattern** (lines 11-16, already present — no change needed):
```python
from datetime import datetime, timezone

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from loguru import logger

from hera_agent.pipeline import run_pipeline
```

**Insertion point:** After existing `/ws` endpoint (after line 47), before the `if __name__ == "__main__":` block (line 50).

**Existing route shape to mirror** (lines 27-33):
```python
@app.get("/ping")
async def ping() -> dict:
    """AgentCore Runtime health probe (HTTP 200 -> status=Healthy)."""
    return {
        "status": "Healthy",
        "time_of_last_update": _BOOT_TIME,
    }
```

**Existing pipeline-bridging discipline** (lines 36-47) — single try/except whose only purpose is non-error disconnect handling:
```python
@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    logger.info("WS client connected")
    try:
        await run_pipeline(websocket)
    except WebSocketDisconnect:
        logger.info("WS client disconnected")
```

**New `@app.post("/invocations")` MUST:**
- Use `async def` and a typed return (`-> dict` or a streaming `Response`).
- Add a one-line docstring per the file's style.
- Bridge into pipeline.py exactly like `/ws` does — no new try/except (AGENTS.md root-cause discipline; the existing `WebSocketDisconnect` catch is the only allowed pattern in this module per its inline comment lines 41-43).
- Preserve `/ping` and `/ws` verbatim. Local docker-compose dev still uses `/ws`.

---

### `agent/hera_agent/pipeline.py` (modify, optional adapter) — Plan 04-01

**Analog:** `pipeline.py` itself — `run_pipeline(websocket)` lines 74-147 is the existing per-connection pipeline-builder; a new `run_invocation(payload)` (or similar) follows the same shape minus the WS transport.

**Existing per-connection-pipeline pattern** (lines 74-147 — extract the structure not the WS specifics):
- Build `transport` (WS-specific — adapter would replace with HTTP/SSE source/sink).
- `llm = build_llm()` (lines 95) — boto3 default-chain bridge stays VERBATIM (Plan 03-05 fix).
- `llm.register_function("lookup_product", ...)` (lines 99-103) — verbatim.
- Seed `LLMContext` with kickoff user message (lines 112-115) — verbatim.
- `LLMContextAggregatorPair` + `Pipeline([...])` + `PipelineTask(...)` (lines 116-135) — verbatim shape.
- `await PipelineRunner(handle_sigint=False).run(task)` (line 147) — verbatim.

**Insertion point:** After `run_pipeline` (after line 147), as a sibling `async def`.

**Adapter MUST:**
- Reuse `build_llm()` verbatim — do NOT introduce a new credential path.
- Keep `cancel_on_interruption=False` for `lookup_product` (Pitfall H comment, lines 96-98).
- No new try/except (root-cause discipline).
- Decision on per-request fresh-pipeline vs reused pipeline is for the planner; this PATTERNS.md only fixes the SHAPE, not the lifecycle.

---

### `RUNBOOK.md` (modify, Plan 04-01 deploy section) — Plan 04-01

**Analog:** `RUNBOOK.md` `## Phase 3: AgentCore deploy` lines 339-485 — the existing paste-style 4-step lifecycle.

**Insertion point:** After line 485 (`Cleanup verification script (cleanup-verify.sh) is Phase 4 work.`), BEFORE line 487 `## Resolved deferrals`.

**Pattern to mirror — Phase 3 step style** (lines 377-389):
```markdown
### Step 2: Build + push the agent image to ECR

\`\`\`bash
bin/push-image.sh
\`\`\`

What this does (Plan 03-03):
1. Resolves `ecr_repo_url` from terraform outputs.
2. ...
```

**New section MUST:**
- Use heading `## Phase 4: Protocol-bridge deploy` (heading-disjoint from Phase 3 — RUNBOOK convention).
- Paste-block format with backtick-fenced bash, one job per block.
- Reference `bin/push-image.sh` and `cdk deploy hera-agentcore --context image_tag=<sha>` verbatim.
- Include browser-test pointer to `https://dg0w939ktclw6.cloudfront.net/` (D-34).
- Document the version=2 -> version=3 in-place upgrade.

---

### `infra/modules/observability/versions.tf` (new) — Plan 04-02

**Analog:** `infra/modules/widget_hosting/versions.tf` lines 1-10 (or any other module's versions.tf — they are identical).

**Copy verbatim** (lines 1-10):
```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
  }
}
```

**Rationale:** Every existing module has the identical `versions.tf`. Phase 4 OBS module follows verbatim — no archive provider needed (no Lambda zip), no extra providers. **Note:** The us-east-1 billing-alarm provider alias is declared in `infra/envs/prod/main.tf` and PASSED IN to the module via `providers = { aws.us_east_1 = aws.us_east_1 }`; the module's `versions.tf` declares both aliases under `configuration_aliases`. See main.tf section below for the alias-declaration excerpt.

**Module versions.tf MUST add `configuration_aliases`:**
```hcl
required_providers {
  aws = {
    source                = "hashicorp/aws"
    version               = "~> 6.27"
    configuration_aliases = [aws.us_east_1]
  }
}
```

---

### `infra/modules/observability/variables.tf` (new) — Plan 04-02

**Analog:** `infra/modules/agentcore_iam/variables.tf` lines 1-21 — passes in caller-resolved `region`, `account_id`, name-prefix/env defaults.

**Pattern to mirror** (`agentcore_iam/variables.tf` lines 1-21):
```hcl
variable "name_prefix" {
  description = "Resource name prefix. Default \"hera\" (project name)."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment suffix for resource names. \"prod\" yields hera-agentcore-exec-prod (D-12 fixed names)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region ... No default — caller passes var.region from the prod root."
  type        = string
}
```

**Module MUST also accept** (no default — caller wires from existing TF/CDK outputs):
- `agentcore_log_group_name` (string, no default) — for log-based metric filters; passed from `module.agentcore_iam.log_group_name`.
- `agentcore_runtime_arn` (string, no default; same Plan 03-04 pattern as `widget_presigner/variables.tf` line 24) — for dashboard panel scoping.
- `presigner_function_name` (string, no default) — Lambda metric scoping; passed from `module.widget_presigner.function_name`.
- `cloudfront_distribution_id` (string, no default) — for CloudFront 5xx panel.
- `billing_threshold_usd` (number, default `5`) — D-29 verbatim hardcode of $5/day.
- `error_rate_threshold_pct` (number, default `5`) — D-25-like default for OBS-02.
- `latency_p95_threshold_ms` (number, default `5000`) — OBS-02 verbatim.

---

### `infra/modules/observability/main.tf` (new) — Plan 04-02

**Analog (resource shape — billing alarm):** `infra/modules/widget_presigner/main.tf` lines 142-153 illustrates the "single resource with `cors {}` block" pattern; the closest concept is `aws_cloudwatch_metric_alarm` in any AWS-published example. **No existing in-tree analog for `aws_cloudwatch_metric_alarm` or `aws_cloudwatch_dashboard`** — researcher's RESEARCH.md is the source for the resource SHAPE; this PATTERNS.md fixes the FILE-LAYOUT and CROSS-REGION provider-alias pattern only.

**Provider-alias pattern (cross-region us-east-1 billing alarm):**

In `infra/envs/prod/main.tf`, add a second `provider "aws"` block AND pass it via the `providers` map on the module call:
```hcl
provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "observability" {
  source = "../../modules/observability"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
  # ... vars ...
}
```

In `infra/modules/observability/main.tf`, the billing alarm uses the alias provider:
```hcl
resource "aws_cloudwatch_metric_alarm" "billing" {
  provider = aws.us_east_1
  # ... AWS/Billing EstimatedCharges, threshold = var.billing_threshold_usd ...
  alarm_actions = []  # D-35: no SNS / no Lambda; dashboard-only.
}
```

**Naming convention** (D-12 fixed names; mirror `agentcore_iam/main.tf` line 42 `"${var.name_prefix}-agentcore-exec-${var.env}"`):
```hcl
name = "${var.name_prefix}-billing-${var.env}"        # hera-billing-prod
name = "${var.name_prefix}-error-rate-${var.env}"     # hera-error-rate-prod
name = "${var.name_prefix}-latency-p95-${var.env}"    # hera-latency-p95-prod
dashboard_name = "${var.name_prefix}-${var.env}"      # hera-prod
```

**Zero-wildcard discipline (D-13 carry-forward):** No new IAM roles created in this module. Dashboard reads metrics by ARN/namespace; no IAM policy needed (CloudWatch dashboards are global-read via console-side IAM). If researcher determines we need a metric-publish role, follow `agentcore_iam/main.tf` lines 110-121 — the `cloudwatch:PutMetricData` Resource=* with `cloudwatch:namespace` StringEquals condition.

**Heading comment block style** (mirror `agentcore_iam/main.tf` lines 1-13 and `widget_hosting/main.tf` lines 1-14):
```hcl
# Observability: CloudWatch dashboard + operational alarms (OBS-01..03)
# + billing alarm (OBS-05 best-effort).
#
# D-13: zero new IAM roles/wildcards (dashboards are read-only via caller IAM).
# D-29: billing threshold = $5/day verbatim (banner copy hardcode).
# D-35: alarm_actions = [] -- no SNS, no Lambda. Dashboard-visible only.
#
# Cross-region provider alias: AWS/Billing EstimatedCharges is only emitted
# in us-east-1, so the billing alarm uses provider = aws.us_east_1 passed
# in via the module's `providers` map.
```

---

### `infra/modules/observability/outputs.tf` (new) — Plan 04-02

**Analog:** `infra/modules/widget_hosting/outputs.tf` lines 1-25.

**Pattern (one output per consumable URL/ARN, full sentence description):**
```hcl
output "dashboard_url" {
  description = "AWS console URL for the Phase 4 CloudWatch dashboard. RUNBOOK Phase 4 dashboard walkthrough section embeds this."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.this.dashboard_name}"
}

output "billing_alarm_arn" {
  description = "us-east-1 billing alarm ARN. Phase 5 workshop content references for screenshot."
  value       = aws_cloudwatch_metric_alarm.billing.arn
}
```

---

### `infra/envs/prod/main.tf` (modify) — Plan 04-02

**Insertion point:** After existing `module "widget_presigner"` block (after line 54).

**Existing module-call pattern to mirror** (lines 27-30 and lines 47-54):
```hcl
module "widget_hosting" {
  source = "../../modules/widget_hosting"
  # bucket_name uses default hera-widget-prod (D-12 fixed name).
}

module "widget_presigner" {
  source = "../../modules/widget_presigner"

  region                = var.region
  account_id            = data.aws_caller_identity.current.account_id
  agentcore_runtime_arn = var.agentcore_runtime_arn
  cors_allow_origin     = module.widget_hosting.cloudfront_url
}
```

**New module call (add after line 54):**
```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "observability" {
  source = "../../modules/observability"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  region                     = var.region
  account_id                 = data.aws_caller_identity.current.account_id
  agentcore_log_group_name   = module.agentcore_iam.log_group_name
  agentcore_runtime_arn      = var.agentcore_runtime_arn
  presigner_function_name    = module.widget_presigner.function_name
  cloudfront_distribution_id = module.widget_hosting.cloudfront_distribution_id
}
```

**Note:** The second `provider "aws"` block can also live at top of file alongside the existing `provider "aws" { region = var.region }` (lines 1-3). Either placement compiles; planner picks.

---

### `infra/envs/prod/outputs.tf` (modify, optional) — Plan 04-02

**Insertion point:** After existing `presign_url` output (after line 69).

**Existing output pattern to mirror** (lines 51-54):
```hcl
output "widget_cloudfront_url" {
  description = "Public widget URL on default *.cloudfront.net (DEM-01)."
  value       = module.widget_hosting.cloudfront_url
}
```

**New output:**
```hcl
output "observability_dashboard_url" {
  description = "AWS console URL for the Phase 4 CloudWatch dashboard. RUNBOOK Phase 4 dashboard walkthrough section embeds this."
  value       = module.observability.dashboard_url
}
```

---

### `bin/cleanup-verify.sh` (new) — Plan 04-03

**Analog:** `bin/verify-kb.sh` lines 1-121 (the canonical pattern source per D-37).

**Header / shebang / `set` flags** (verify-kb.sh lines 1-7):
```bash
#!/usr/bin/env bash
# bin/cleanup-verify.sh - Phase 4 cleanup verification (D-37, D-39).
# Runs AFTER operator-driven `cdk destroy` then `terraform destroy`.
# Exits 0 when ALL phase-1/2/3 resources are gone; non-zero with the
# resource that still exists on first leftover.

set -euo pipefail
```

**Preflight pattern** (verify-kb.sh lines 33-35):
```bash
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found on PATH (RUNBOOK Pre-flight)" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq not found on PATH (RUNBOOK Pre-flight). Install: winget install jqlang.jq (Windows), brew install jq (macOS), apt-get install jq (Debian/Ubuntu)" >&2; exit 2; }
```

**Region default pattern** (verify-kb.sh line 38):
```bash
REGION="${HERA_REGION:-ap-northeast-1}"
```

**Per-resource invert-check pattern (closest analog: verify-kb.sh lines 85-91 invert mode):**
```bash
RESP=$(aws bedrock-agent get-knowledge-base \
  --region "${REGION}" \
  --knowledge-base-id "BKXE19AH89" 2>&1) || true

if echo "${RESP}" | grep -qiE 'AccessDenied|ResourceNotFound|NotFoundException'; then
  echo "OK: KB BKXE19AH89 is gone"
else
  echo "FAIL: KB BKXE19AH89 still exists" >&2
  exit 1
fi
```

**Final OK pattern** (verify-kb.sh lines 88-90):
```bash
echo "OK (cleanup): all hera resources removed"
```

**Resource list to check (D-37 verbatim):**
- KB `BKXE19AH89` — `aws bedrock-agent get-knowledge-base`
- S3 Vectors index `hera-kb-index` + bucket `hera-kb-vectors-prod` — `aws s3vectors get-vector-bucket` / `get-index`
- Source bucket `hera-kb-source-prod` — `aws s3api head-bucket`
- AgentCore Runtime `hera_agent-GIsf2P4ImD` — `aws bedrock-agentcore-control get-agent-runtime`
- CloudWatch log group `/aws/bedrock-agentcore/hera-agent` — `aws logs describe-log-groups --log-group-name-prefix`
- IAM role `hera-agentcore-exec-prod` + KB consumer policy `hera-kb-retrieve-prod` + KB service role — `aws iam get-role` / `get-policy`
- ECR repo `hera-agent` — `aws ecr describe-repositories`
- CloudFront distribution `E10K3B1L8PQ9EC` + widget S3 bucket `hera-widget-prod` — `aws cloudfront get-distribution` / `aws s3api head-bucket`
- Lambda `hera-widget-presign-prod` + Function URL config — `aws lambda get-function` / `get-function-url-config`
- Billing alarm + dashboard — `aws cloudwatch describe-alarms --region us-east-1` / `get-dashboard`

**MUST NOT:**
- Use `python` / `boto3` / `uv run` (D-37: bash + AWS CLI uniform).
- Invoke any destroy command (D-39: verify-only).
- Call Cost Explorer (D-38: that's a 24h-deferred RUNBOOK paste-line, not script scope).
- Use `sed -i ''` (BSD quirk; not used in verify-kb.sh either — see anti-patterns below).

---

### `RUNBOOK.md` (modify, Plan 04-03 cleanup section) — Plan 04-03

**Analog:** `RUNBOOK.md` `## Cleanup` lines 195-217 (Phase 1 minimal cleanup) + `### Cleanup order` lines 476-485 (Phase 3 ordered cleanup).

**Insertion point:** Between line 485 (Phase 3 `### Cleanup order` close) and line 487 (`## Resolved deferrals`). Heading-disjoint with prior phases' `## Cleanup` sections per RUNBOOK convention (each phase owns its own section heading).

**Existing Phase 3 cleanup pattern to mirror** (lines 476-485):
```markdown
### Cleanup order

\`\`\`bash
# Tear down CDK first (so the AgentCore Runtime resource releases its grip on
# the IAM role + log group + image), then Terraform.
cd infra/cdk && uv run cdk destroy hera-agentcore --force && cd ../..
cd infra/envs/prod && terraform destroy && cd ../..
\`\`\`

Cleanup verification script (`cleanup-verify.sh`) is Phase 4 work.
```

**New `## Phase 4: Cleanup quy trinh` MUST contain:**
- Three numbered paste-blocks: (1) `cdk destroy`, (2) `terraform destroy`, (3) `bin/cleanup-verify.sh` (D-39 verify-only).
- A `### Verify $0 ongoing cost (24h after destroy)` subsection with the Cost Explorer paste-line per D-38:
  ```bash
  aws ce get-cost-and-usage \
    --time-period Start=<destroy-date>,End=<+24h> \
    --granularity DAILY \
    --metrics BlendedCost \
    | jq '.ResultsByTime[].Total.BlendedCost.Amount'
  ```
- A `### Billing-alarm manual-stop fallback` subsection per D-35 trade-off (when alarm fires: console -> AgentCore -> stop runtime, OR `aws bedrock-agentcore-control update-agent-runtime ...`).
- An `### OBS-04 trade-off note` per D-36 (presigner is open; rate-limit is enforced by AgentCore concurrency cap=2 downstream).

---

## Shared Patterns

### Atomic conventional commits scoped to plan id

**Source:** Recent git log (most recent on master):
```
docs(04): capture phase context
docs(03): phase 3 verifier report — PASS-WITH-DEFERRAL (4/5 SC, SC#2 → Phase 4)
docs(03-05): close plan 03-05 — credential bridge done; protocol bridge → Phase 4
feat(03-05): live cdk redeploy with credential-bridge fix (Runtime version=2)
fix(03-05): bake HERA_KB_ID + AWS_REGION defaults into Dockerfile for AgentCore
```

**Apply to:** Every commit in Phase 4. Scope = plan id (`feat(04-01):`, `feat(04-02):`, `feat(04-03):`, `docs(04):` for cross-cutting RUNBOOK edits).

### Empty-commit-with-outputs-in-body for live deploy events

**Source:** Plan 03-01 introduced this; `feat(03-05): live cdk redeploy with credential-bridge fix (Runtime version=2)` is the most recent example. Body contains the AgentCore CFn output digest.

**Apply to:** Plan 04-01's single live `cdk deploy hera-agentcore --context image_tag=<sha>` event (version=2 -> version=3). Body should embed the AgentCore Runtime status + image digest from `dist/cdk-outputs.json`.

### Zero IAM wildcards (D-13 carry-forward)

**Source:** `infra/modules/agentcore_iam/main.tf` lines 110-121 — the canonical "documented exception" pattern: `cloudwatch:PutMetricData` with Resource=* IS allowed because the AWS IAM model has no resource-level identifier for this action; scoping is enforced via the `cloudwatch:namespace` StringEquals condition.

```hcl
statement {
  sid       = "CloudWatchEMFMetrics"
  effect    = "Allow"
  actions   = ["cloudwatch:PutMetricData"]
  resources = ["*"]

  condition {
    test     = "StringEquals"
    variable = "cloudwatch:namespace"
    values   = ["hera/agentcore"]
  }
}
```

**Apply to:** All Phase 4 IAM (if any new role is added). Phase 4's expected case is ZERO new IAM — dashboard reads metrics via the operator's CLI identity; alarms have `alarm_actions = []` (D-35 no-action) so no service role is needed.

### Preflight tool gate with platform install hints

**Source:** `bin/verify-kb.sh` lines 33-35 (one-liners) and `bin/push-image.sh` lines 22-33 (per-tool case statement).

**Apply to:** `bin/cleanup-verify.sh`. For Phase 4 verify, the verify-kb.sh one-liner style is the closer analog (only `aws` + `jq` needed; no docker/terraform/buildx).

### Resource-name fixed (D-12; no random_id)

**Source:** Every existing module — `infra/modules/widget_hosting/variables.tf` line 17 `default = "hera-widget-prod"`, `infra/modules/agentcore_iam/main.tf` line 42 `name = "${var.name_prefix}-agentcore-exec-${var.env}"`.

**Apply to:** Observability module names: `hera-prod` dashboard, `hera-billing-prod` / `hera-error-rate-prod` / `hera-latency-p95-prod` alarms.

### No emojis, uv only, no defensive try/except, concise docstrings

**Source:** `CLAUDE.md` / `AGENTS.md` (project mandates). Existing code adheres uniformly — `agent/hera_agent/main.py` lines 41-43 inline-comments the *only* try/except in that module.

**Apply to:** Every new file in Phase 4 — Python (`main.py`, `pipeline.py`), bash (`cleanup-verify.sh`), Terraform comments, RUNBOOK prose.

### RUNBOOK heading-disjoint per phase

**Source:** `RUNBOOK.md` headings list — each phase owns its own top-level section: `## First deploy` (Phase 1), `## Phase 3: AgentCore deploy` (Phase 3), `## Cleanup` (Phase 1) + `### Cleanup order` (Phase 3 sub of Phase 3 section).

**Apply to:** Phase 4 adds two new sections — `## Phase 4: Protocol-bridge deploy` (Plan 04-01) and `## Phase 4: Cleanup quy trinh` (Plan 04-03). Plan 04-02 dashboard walkthrough is a sub-section of `## Phase 4: Protocol-bridge deploy` OR its own `## Phase 4: Observability dashboard walkthrough` — planner picks.

---

## No Analog Found

| File | Role | Reason |
|------|------|--------|
| `infra/modules/observability/main.tf` resource shapes (`aws_cloudwatch_metric_alarm`, `aws_cloudwatch_dashboard`) | TF resource bodies | No CloudWatch alarms or dashboards exist anywhere in the in-tree Terraform yet. RESEARCH.md is the authoritative source for the resource SHAPE; this PATTERNS.md only fixes the FILE LAYOUT and CROSS-REGION provider alias. |
| `agent/hera_agent/main.py` `/invocations` request envelope + response shape | controller route | No prior `@app.post(...)` route in the agent. RESEARCH.md mines awslabs/agentcore-samples 06-bi-directional-streaming for the canonical envelope; this PATTERNS.md only fixes the FastAPI shape and the no-try/except discipline. |

---

## Anti-patterns to avoid

Footguns and rejected paths from prior-phase summaries — Phase 4 must NOT recreate these.

- **`:latest` tag on IMMUTABLE ECR repo** (Plan 03-01): the ECR repo is `image_tag_mutability = IMMUTABLE`; pushing `:latest` is rejected. Use `git rev-parse --short HEAD` per `bin/push-image.sh` lines 53-58.
- **Positive `reserved_concurrent_executions` on a fresh-account Lambda** (Plan 03-04 Task 5 Q2): AWS enforces a 10-concurrency floor for `UnreservedConcurrentExecution`; on accounts with quota=10 any positive value raises `InvalidParameterValueException`. `widget_presigner` defaults to `-1` (`variables.tf` line 47). Phase 4 OBS work touches no Lambda; this is a carry-forward warning if cleanup-verify ever needs to re-create a temporary helper Lambda.
- **CDKv1 feature-flag in cdk.json** (Plan 03-04): silently breaks CDKv2 synth. Phase 4 does NOT touch `infra/cdk/cdk.json`; the existing flags are correct.
- **`sed -i ''` BSD/GNU split** (Plan 03-04): BSD `sed` requires a suffix arg for `-i`; GNU `sed` does not. `bin/build-widget.sh` lines 75-77 dodges this by writing to a temp file then `mv`. **Apply to `bin/cleanup-verify.sh`:** do NOT use `sed -i` at all (verify is read-only — no need for in-place edits).
- **AWSNovaSonicLLMService relying on boto3 default chain** (Plan 03-05): `AWSNovaSonicLLMService` uses `StaticCredentialsResolver`; bridging to boto3 default chain at per-connection time (`pipeline.py` `build_llm()` lines 44-71) is the locked Phase 3 fix. **Plan 04-01 MUST reuse `build_llm()` verbatim** in any per-request adapter — do NOT re-introduce the credential-chain bug.
- **Baking `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` into the Dockerfile** (Plan 03-05): rejected. Dockerfile bakes only `HERA_KB_ID` + `AWS_REGION`. Phase 4 Plan 04-01 rebuilds the same image — same bake rules apply.
- **Cost Explorer call inside the script** (D-38 rejection): `bin/cleanup-verify.sh` MUST NOT call `aws ce get-cost-and-usage`. 24h ingestion lag + $0.01/request fee + UX confusion. RUNBOOK paste-line is the documented quy trinh.
- **Adding `null_resource` automation around AWS CLI calls** (Plan 01-03 D-05/D-07 carry-forward): the AWS CLI is the teaching surface in this workshop project. Phase 4 OBS module must NOT use `null_resource` to "trigger" dashboard creation — it's a pure declarative resource.
- **SNS / email subscription / Lambda auto-stop hook for billing alarm** (D-35 rejection): `alarm_actions = []` is mandatory. RUNBOOK manual-stop fallback IS the trade-off.
- **AWS WAF rate-based rule on CloudFront** (D-36 rejection): out of demo budget (~$5/month base). AgentCore concurrency cap=2 downstream is the documented rate-limit surface.

---

## Metadata

**Analog search scope:** `agent/hera_agent/`, `infra/modules/`, `infra/envs/prod/`, `infra/cdk/hera_agentcore/`, `bin/`, `RUNBOOK.md`, `.planning/phases/03-*/03-*-SUMMARY.md`.

**Files scanned:** 23 (4 agent .py, 6 module dirs x 4 files = 24 module .tf, 3 root .tf, 1 cdk stack.py, 5 bin/.sh, 1 RUNBOOK.md, 1 git log).

**Pattern extraction date:** 2026-05-06.
