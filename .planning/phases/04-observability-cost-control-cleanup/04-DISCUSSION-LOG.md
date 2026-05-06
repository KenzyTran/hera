# Phase 4: Observability, Cost Control, Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-06
**Phase:** 04-Observability, Cost Control, Cleanup
**Areas discussed:** Protocol-bridge approach (Wave 1), Cost circuit-breaker (OBS-05) scope, Per-IP rate limit (OBS-04 part 2), cleanup-verify.sh shape & Cost Explorer integration

---

## Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Protocol-bridge approach (Wave 1) | How to close Phase 3 SC#2: native /invocations vs sidecar proxy vs adopt awslabs sample wholesale | ✓ |
| Cost circuit-breaker (OBS-05) scope | Bare billing alarm + manual response vs Lambda disable presigner vs Lambda full stop runtime | ✓ |
| Per-IP rate limit (OBS-04 part 2) | Skip + rely on concurrency cap vs Lambda reserved_concurrency vs WAF | ✓ |
| cleanup-verify.sh shape & Cost Explorer integration | bash+AWS CLI vs Python+boto3 vs TF state introspection; Cost Explorer in script vs RUNBOOK manual | ✓ |

**User's choice:** All four areas selected.

---

## Protocol-bridge approach (Wave 1)

### Q1: Implementation pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Native /invocations + keep /ws (Recommended) | Add `@app.post("/invocations")` to existing FastAPI app; /ws preserved for local docker-compose. Smallest diff (1-2 files), zero infra change, in-place 4-step deploy. | ✓ |
| Sidecar proxy /invocations -> /ws | Container runs additional process translating AgentCore HTTP envelope to WS frames; agent code zero-touch but Dockerfile complexity + 2-hop debug. | |
| Adopt awslabs sample wholesale | Replace `agent/hera_agent/` with structure from `awslabs/agentcore-samples/.../06-bi-directional-streaming/04-pipecat-sonic-ws`; large refactor + risk to Phase 2 patterns/tests. | |

**User's choice:** Native /invocations + keep /ws (Recommended).
**Notes:** None.

### Q2: Verify gate for plan close

| Option | Description | Selected |
|--------|-------------|----------|
| Local docker run + curl POST /invocations (Recommended) | docker run + curl assert HTTP 200; only when local PASS push image + 1 cdk deploy in-place; no Bedrock streaming smoke. Demo-budget friendly. | ✓ |
| Full bin/smoke-deploy.sh + browser approval | Run existing smoke-deploy.sh end-to-end + browser test at https://dg0w939ktclw6.cloudfront.net/. Closes SC#2 with browser proof but spends Bedrock streaming. | |
| Both — local first then smoke deploy | Iterate locally then 1 cdk deploy + smoke + browser. Safer but extra Bedrock streaming cost. | |

**User's choice:** Local docker run + curl POST /invocations (Recommended).
**Notes:** None.

### Q3: Scope outside agent/

| Option | Description | Selected |
|--------|-------------|----------|
| agent/ + RUNBOOK (Recommended) | Edit agent/hera_agent/main.py + maybe pipeline.py + RUNBOOK.md only. No cdk/, infra/, frontend/. CDK ProtocolConfiguration=HTTP from Plan 03-04 already routes /invocations correctly. | ✓ |
| agent/ + cdk/ stack | Plus check cdk/agentcore/stack.py for env var / protocol config / health check updates. Adds 1 cdk synth/deploy round. | |
| agent/ + cdk/ + frontend/ | Plus update frontend/app.js to send /invocations instead of /ws in production. Broadest scope. | |

**User's choice:** agent/ + RUNBOOK (Recommended).
**Notes:** None.

### Q4: Phase 3 SC#2 closure protocol

| Option | Description | Selected |
|--------|-------------|----------|
| Close SC#2 with smoke probe + RUNBOOK note (Recommended) | Plan 04-01 self-closes SC#2 via single AgentCore data-plane InvokeAgentRuntime smoke against live runtime returning 200; RUNBOOK browser-test note (not a gate). Phase 3 PASS 5/5. | ✓ |
| Keep SC#2 OPEN until user browser test | Plan 04-01 only closes technical gap (404 -> 200); SC#2 stays OPEN until user manually tests browser. More cautious; Phase 3 stays 5/5 plans done with SC#2 separate acceptance. | |
| Skip SC#2 verify, focus on OBS work | Ship technical fix only; no AgentCore data-plane invoke; SC#2 OPEN until instructor demo. Saves Bedrock streaming cost. | |

**User's choice:** Close SC#2 with smoke probe + RUNBOOK note (Recommended).
**Notes:** None.

---

## Cost circuit-breaker (OBS-05) scope

### Q1: Circuit-breaker scope

| Option | Description | Selected |
|--------|-------------|----------|
| Only billing alarm + email, no Lambda (Recommended) | CloudWatch billing alarm $5/day + SNS email subscription; manual response. Trade-off documented. Simplest, no Lambda. | ✓ (later refined) |
| Lambda disable presigner Function URL | SNS -> Lambda -> aws lambda update-function-url-config --auth-type AWS_IAM. Voice loop off but runtime alive. Cheaper than full stop. | |
| Lambda full stop AgentCore Runtime | SNS -> Lambda -> bedrock-agentcore-control update-agent-runtime stopped. Full auto-kill. Most complex. | |

**User's choice:** Initially "Only billing alarm + email" then refined to **billing alarm only, no email/SNS layer** after pushback.

### Q2: Email subscriber + threshold (REVISED — REJECTED as scope creep)

User rejected this question with: "Đâu cần notify email làm gì, càng lúc bạn càng làm nhiều thứ out of scope".

**Refined decision:** Ship CloudWatch billing alarm at $5/day cap only — no SNS topic, no email subscription, no Lambda. REQ-OBS-05 ("best-effort, document trade-off") satisfied by alarm visibility on dashboard + RUNBOOK manual-response procedure + explicit trade-off statement. Threshold $5/day matches Phase 3 D-29 banner copy hardcode.

**Notes:** This pushback led to a new feedback memory (don't auto-add scope-creep options during discuss-phase). Future questions for Hera should default to the minimal interpretation of REQ.

---

## Per-IP rate limit (OBS-04 part 2)

### Q1: Rate-limit approach

| Option | Description | Selected |
|--------|-------------|----------|
| Skip per-IP, rely on AgentCore concurrency cap=2 (Recommended) | No WAF, no DynamoDB token bucket. AgentCore concurrency cap=2 downstream is the effective rate-limit. Trade-off documented: presigner mints freely, Runtime caps at 2 sessions. | ✓ |
| Lambda reserved_concurrency = 2 | Single TF line. Free. Trade-off: account UnreservedConcurrentExecution floor=10 may reject (Plan 03-04 deviation #2 history). | |
| AWS WAF rate-based rule | WAF Web ACL rate-based (e.g., 100 req/5min/IP) on CloudFront or Function URL. ~$5/month base + per-rule cost. Out of demo budget. | |

**User's choice:** Skip per-IP, rely on AgentCore concurrency cap=2 (Recommended).
**Notes:** None.

---

## cleanup-verify.sh shape & Cost Explorer integration

### Q1: Script language and style

| Option | Description | Selected |
|--------|-------------|----------|
| Bash + AWS CLI (Recommended) | Per bin/verify-kb.sh pattern: set -euo pipefail, command -v preflight, paste-style FCJ workshop friendly. One query+assertion per resource type. No uv needed. | ✓ |
| Python + boto3 | bin/cleanup_verify.py via uv run. Richer code, easier to extend. Adds uv entry-point. | |
| Bash + Terraform state introspection | terraform state list empty + spot-check API calls. Trusts TF state vs API. Risk: state drift. | |

**User's choice:** Bash + AWS CLI (Recommended).
**Notes:** None.

### Q2: Cost Explorer integration

| Option | Description | Selected |
|--------|-------------|----------|
| Resource check only, Cost Explorer = RUNBOOK manual (Recommended) | Script runs immediately post-destroy with resource-existence assertions only. RUNBOOK section "Verify $0 cost after 24h" + paste-line `aws ce get-cost-and-usage`. 2-step quy trình clear. Avoids $0.01/request + 24h lag UX confusion. | ✓ |
| Script gate `--check-cost` flag | Default resource check; --check-cost adds Cost Explorer query. Single script with flag-driven 24h second run. | |
| Both in one shot | Resource check + Cost Explorer in one run. Trade-off: running immediately post-destroy fails Cost Explorer (data not flushed); forces 24h wait + re-run. | |

**User's choice:** Resource check only, Cost Explorer = RUNBOOK manual (Recommended).
**Notes:** None.

### Q3: Automation level

| Option | Description | Selected |
|--------|-------------|----------|
| Operator destroys first, script verify-only (Recommended) | (1) operator paste cdk destroy hera-agentcore, (2) operator paste terraform destroy, (3) operator bin/cleanup-verify.sh — script verify-only. Honors D-24 cleanup-contract. Workshop-clear. | ✓ |
| Script auto-destroys + verifies | Script runs cdk destroy + terraform destroy + verify in one go. Trade-off: hides errors, harder to debug, learner skips quy trình. | |

**User's choice:** Operator destroys first, script verify-only (Recommended).
**Notes:** None.

---

## Claude's Discretion

- Exact CloudWatch dashboard panel JSON shape and metric queries (researcher resolves auto-emitted vs PutMetric).
- Alarm `evaluation_periods` / `period` / `comparison_operator` / `treat_missing_data` defaults.
- Whether OBS module structure is `infra/modules/observability/` or inline in root.
- AgentCore data-plane API verb + payload schema for SC#2 closure smoke (researcher confirms latest API as of NOW).
- /invocations request envelope JSON schema + response streaming shape (researcher mines awslabs sample).
- Pipecat pipeline lifecycle for /invocations (per-request fresh vs persistent reused).
- Phase 4 wave structure (1 plan vs 2 vs 3) — planner picks based on file-disjoint parallelism.
- Optional `--check-cost` flag on cleanup-verify.sh — D-38 says no but planner may add for instructor convenience.

## Deferred Ideas

- SNS topic + email subscription for billing alarm — explicitly skipped (scope creep).
- Lambda cost circuit-breaker (auto-stop or auto-disable) — explicitly skipped (REQ best-effort accepts manual response).
- AWS WAF rate-based rule on CloudFront or presigner Function URL — explicitly skipped (out of demo budget).
- DynamoDB token-bucket per-IP rate limit Lambda — explicitly skipped (added complexity, marginal benefit).
- Cost Explorer baked into cleanup-verify.sh — explicitly skipped (24h lag + $0.01/request fee).
- Python/boto3 cleanup-verify.py — alternative considered, kept bash for uniformity.
- Sonic foundation-model ARN runtime gate (carried from Plan 03-01) — exercised by Plan 04-01 implicitly.
- AgentCore service-quota request from default-10 to D-30's 2 — operational, not IaC.
- CDK bootstrap deploy-role trust policy for non-root operators — operational, not IaC.
- Custom domain + ACM cert for CloudFront — deferred from Phase 3 D-26 to v2.
- Browser-driven SC#2 acceptance test as gate — RUNBOOK note only, not a Plan 04-01 gate.
- Hugo theme migration `learn` -> `relearn` — explicitly v2.
