---
phase: 04-observability-cost-control-cleanup
plan: 02
subsystem: observability
tags:
  - terraform
  - cloudwatch
  - cross-region
  - dashboard
  - alarms
  - billing
  - obs-01
  - obs-02
  - obs-03
  - obs-04
  - obs-05
requires:
  - phase-04-plan-01-protocol-bridge-live
  - module.agentcore_iam.log_group_name
  - module.widget_presigner.function_name
  - module.widget_hosting.cloudfront_distribution_id
  - var.agentcore_runtime_arn
provides:
  - module.observability
  - aws_cloudwatch_dashboard.hera-prod
  - aws_cloudwatch_metric_alarm.hera-error-rate-prod
  - aws_cloudwatch_metric_alarm.hera-latency-p95-prod
  - aws_cloudwatch_metric_alarm.hera-billing-prod
  - output.observability_dashboard_url
  - output.observability_billing_alarm_arn
affects:
  - infra/envs/prod (provider alias us_east_1 + module observability)
  - RUNBOOK.md (Phase 4 observability walkthrough section)
tech-stack:
  added:
    - aws_cloudwatch_dashboard
    - aws_cloudwatch_metric_alarm (metric_query arithmetic + extended_statistic p95)
    - terraform configuration_aliases for cross-region providers
  patterns:
    - cross-region provider alias for AWS/Billing (us-east-1 only)
    - widget-level region override in dashboard JSON for cross-region panels
    - alarm_actions = [] (D-35 dashboard-only, no SNS/email/Lambda hook)
key-files:
  created:
    - infra/modules/observability/versions.tf
    - infra/modules/observability/variables.tf
    - infra/modules/observability/main.tf
    - infra/modules/observability/outputs.tf
    - .planning/phases/04-observability-cost-control-cleanup/04-02-SUMMARY.md
  modified:
    - infra/envs/prod/main.tf (provider alias us_east_1 + module observability call)
    - infra/envs/prod/outputs.tf (observability_dashboard_url + observability_billing_alarm_arn)
    - RUNBOOK.md (Phase 4 observability walkthrough section)
decisions:
  - "Option A re-plan with -var=agentcore_runtime_arn on the live apply: preserves D-25 4-step lifecycle (presigner stays wired to live runtime hera_agent-GIsf2P4ImD); avoids accidental presigner ARN flip to PLACEHOLDER which would break the voice loop."
  - "Module-output wiring used as named: module.agentcore_iam.log_group_name, module.widget_presigner.function_name, module.widget_hosting.cloudfront_distribution_id all exist verbatim — no upstream module changes needed."
  - "CloudFront TLS bump (TLSv1 -> TLSv1.2_2021) and Lambda description-removal accepted as benign drift, applied in this run. CloudFront drift is the AWS-side override documented in Plan 03-01 SUMMARY (default *.cloudfront.net cert silently downgrades minimum_protocol_version); the bump back is harmless because viewer_protocol_policy=redirect-to-https already enforces TLS."
  - "Billing-alerts toggle (RESEARCH A1) is documented as informational only in RUNBOOK — alarm sits INSUFFICIENT_DATA until the operator flips it; not a gate on apply."
  - "TTFT panel (RESEARCH A3 [needs-verification]) deferred — A3 stays open. AgentCore Latency p50/p95 panel is the latency surface; if A3 resolves positively in a future plan, a TTFT widget can be added."
metrics:
  duration: ~10 min (continuation only — Tasks 5-7)
  total_duration: ~70 min (across both executor invocations: scaffold + dashboard + billing alarm + prod-root wiring + live apply + RUNBOOK + summary)
  tasks_completed: 7
  files_changed: 7
  commits: 7
  completed: 2026-05-06
---

# Phase 4 Plan 02: Observability dashboard + alarms Summary

One-liner: Live CloudWatch dashboard `hera-prod` (5 widgets) + 3 alarms (error_rate, latency_p95 in ap-northeast-1, billing in us-east-1 via second provider alias) shipped via new `infra/modules/observability/` Terraform module wired into prod root with zero new IAM (D-13).

## What shipped

**Module shape (`infra/modules/observability/`):**
- `versions.tf` — Terraform 1.9+ + AWS ~> 6.27 with `configuration_aliases = [aws.us_east_1]` so the prod root can pass an aliased provider for the cross-region billing alarm.
- `variables.tf` — `name_prefix` / `env` defaults + `region` (no default; caller passes from prod root) + `account_id` + `agentcore_log_group_name` + `agentcore_runtime_arn` + `presigner_function_name` + `cloudfront_distribution_id` + thresholds (`billing_threshold_usd=5`, `error_rate_threshold_pct=5`, `latency_p95_threshold_ms=5000`) + `sonic_model_id="amazon.nova-sonic-v1:0"`.
- `main.tf` — heading comment block + 1 dashboard + 3 alarms.
- `outputs.tf` — `dashboard_name` + `dashboard_url` + `error_rate_alarm_name` + `latency_p95_alarm_name` + `billing_alarm_arn`.

**Cross-region provider-alias pattern:**
- Module `versions.tf` declares `configuration_aliases = [aws.us_east_1]` (the AWS-published shape for cross-region modules).
- Prod root `main.tf` adds a second provider block with `alias = "us_east_1"`.
- Module call passes `providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }`.
- Only the billing alarm sets `provider = aws.us_east_1`; everything else uses the default `aws` provider so it lands in ap-northeast-1.
- Dashboard widget for billing sets widget-level `"region": "us-east-1"` so the cross-region metric is drawn from the ap-northeast-1 dashboard view.

**Resources created (live, terraform apply complete):**

| Resource | Region | Name | Notes |
|---|---|---|---|
| `aws_cloudwatch_dashboard.this` | ap-northeast-1 | `hera-prod` | 5 widgets per RESEARCH section B |
| `aws_cloudwatch_metric_alarm.error_rate` | ap-northeast-1 | `hera-error-rate-prod` | metric_query: `IF(m1>0, 100*m2/m1, 0)`, threshold=5%, period=300, treat_missing_data=notBreaching |
| `aws_cloudwatch_metric_alarm.latency_p95` | ap-northeast-1 | `hera-latency-p95-prod` | extended_statistic=p95, threshold=5000ms, period=300, treat_missing_data=notBreaching |
| `aws_cloudwatch_metric_alarm.billing` | us-east-1 | `hera-billing-prod` | namespace=AWS/Billing, statistic=Maximum, period=21600 (6h, AWS minimum), threshold=$5/day (D-29), treat_missing_data=missing |

All 4 resources have `alarm_actions = []` (D-35 — no SNS, no email, no Lambda hook).

## Live evidence

**Apply summary:**
```
Apply complete! Resources: 4 added, 2 changed, 0 destroyed.
```

The 4 ADDs are the dashboard + 3 alarms above. The 2 CHANGEs are accepted benign drift:
- `module.widget_hosting.aws_cloudfront_distribution.widget`: TLSv1 -> TLSv1.2_2021 (AWS-side override per Plan 03-01 SUMMARY; harmless because viewer_protocol_policy=redirect-to-https already enforces TLS).
- `module.widget_presigner.aws_lambda_function.presign`: stale `description = "Force restart 1778049220"` removed, no functional change.

**Terraform outputs:**
```
observability_dashboard_url     = "https://ap-northeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=hera-prod"
observability_billing_alarm_arn = "arn:aws:cloudwatch:us-east-1:851725411875:alarm:hera-billing-prod"
```

**Live state post-apply:**

| Resource | Region | State |
|---|---|---|
| Dashboard `hera-prod` | ap-northeast-1 | exists (`get-dashboard` returns name) |
| Alarm `hera-error-rate-prod` | ap-northeast-1 | OK, treat_missing=notBreaching |
| Alarm `hera-latency-p95-prod` | ap-northeast-1 | OK, treat_missing=notBreaching |
| Alarm `hera-billing-prod` | us-east-1 | INSUFFICIENT_DATA (expected — operator must flip billing-alerts toggle), threshold=5.0 |
| New IAM roles matching obs/dashboard/alarm | global | 0 (D-13 honored) |

**Voice-loop preservation (extra safety check beyond Plan 04-02 scope):**
```
$ aws lambda get-function-configuration --function-name hera-widget-presign-prod --region ap-northeast-1 --query 'Environment.Variables.AGENTCORE_RUNTIME_ARN' --output text
arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD
```
Presigner Lambda still references the live runtime ARN (NOT `PLACEHOLDER`). The Option A re-plan with `-var=agentcore_runtime_arn` did exactly what it was supposed to: preserved Plan 04-01's voice loop while adding the observability layer.

## Module-output wiring confirmation

All three existing module outputs were used as named — no adjustment needed:

| Wired-from | Used as | Status |
|---|---|---|
| `module.agentcore_iam.log_group_name` | `agentcore_log_group_name` (reserved for log-based metric panels in a future iteration) | exists verbatim |
| `module.widget_presigner.function_name` | `presigner_function_name` (reserved for an optional Lambda-metrics widget panel) | exists verbatim |
| `module.widget_hosting.cloudfront_distribution_id` | `cloudfront_distribution_id` (reserved for an optional 5xx-rate widget panel) | exists verbatim |
| `var.agentcore_runtime_arn` | `agentcore_runtime_arn` (used as Resource dimension on AWS/Bedrock-AgentCore metrics) | preserved across re-plan |
| `data.aws_caller_identity.current.account_id` | `account_id` (reserved for future use) | preserved |

The `[needs-verification]` flag on module-output wiring (carried from PLAN.md `<verification>`) resolves: all outputs exist with the names assumed in PLAN.md.

## Open `[needs-verification]` resolution

**A1 — Billing-alerts toggle on account 851725411875:** Documented in RUNBOOK as a one-time operator step (informational only, not a gate on apply). Until the operator opens https://console.aws.amazon.com/billing/home#/preferences and ticks "Receive CloudWatch Billing Alerts", the `hera-billing-prod` alarm sits INSUFFICIENT_DATA — which is the correct state for a freshly-deployed alarm with no metric data. Per user decision (continuation prompt), the toggle is informational only and does not gate the apply.

**A3 — TimeToFirstToken emission for Pipecat bidi-streaming Sonic:** Deferred — TTFT panel NOT included in this dashboard to avoid an empty widget. The AgentCore `Latency` p50/p95 panel is the latency surface for now. If A3 resolves positively in a future plan (e.g., Phase 5 or a Phase 4 follow-up), a TTFT widget can be added without re-creating any other resource.

**Module-wiring [needs-verification]:** Resolved positively — see "Module-output wiring confirmation" above.

## Decision rationale: Option A re-plan with runtime ARN var

Initial `terraform plan` (no `-var=agentcore_runtime_arn`) showed presigner-related items in addition to the expected 4 ADDs. The orchestrator surfaced this as a checkpoint:human-verify deviation. User chose Option A (re-plan with `-var=agentcore_runtime_arn=$RUNTIME_ARN`) over alternatives (B: ignore the drift, C: bake the ARN into a tfvars file).

**Why Option A:**
- **Preserves D-25 4-step lifecycle** (Plan 03-04 carry-forward): the presigner Lambda's `AGENTCORE_RUNTIME_ARN` env var is supposed to be in-place updated by the SECOND `terraform apply -var=agentcore_runtime_arn=<arn>` after `cdk deploy hera-agentcore` emits the runtime ARN. Re-planning with the same var is the same pattern.
- **Avoids accidental ARN flip**: without the var, terraform would have flipped the env var to the variable's default value (`PLACEHOLDER` per `infra/envs/prod/variables.tf`), breaking the voice loop the moment the apply landed.
- **No tfvars sprawl**: piping the runtime ARN from `dist/cdk-outputs.json` via `jq` keeps the ARN source-of-truth in the CDK output (where it was minted), not in a parallel tfvars file that could drift.

The runtime ARN was extracted from `dist/cdk-outputs.json` (Plan 04-01's continuation agent populated this when it ran `cdk deploy hera-agentcore`), so the apply is reproducible from a clean checkout once Plan 04-01 has run.

## Trade-offs documented in RUNBOOK

**OBS-04 (D-36) — no per-IP rate limit on presigner Function URL:** Effective rate-limit is AgentCore concurrency cap=2 (D-30 operational service quota). What we did NOT add: AWS WAF rate-based rule (~$5/month base, out of demo budget) or DynamoDB token-bucket Lambda (added complexity for marginal benefit at 2-session cap). For a v2 with real public traffic, add WAF or token-bucket.

**OBS-05 (D-35) — no SNS / email / Lambda auto-stop hook on billing alarm:** When the alarm transitions to ALARM, the operator manually stops the AgentCore Runtime (paste-line documented in RUNBOOK) or runs `cdk destroy hera-agentcore`. Trade-off accepted: instructor must monitor dashboard. For a v2 with real public traffic, add SNS topic + email subscription + (optional) Lambda hook.

Both are documented verbatim in `RUNBOOK.md` under `## Phase 4: Observability dashboard walkthrough`.

## Deviations from Plan

None of consequence — plan executed as written across two executor invocations.

The only operational deviation was at the live-apply gate (Task 5): the initial plan run (without `-var=agentcore_runtime_arn`) flagged presigner ARN drift, which the orchestrator surfaced as checkpoint:human-verify. User chose Option A (re-plan with the var); see "Decision rationale" above. This was Rule 3 (auto-fix blocking issues for the next executor) handled via user decision rather than auto-fix because the right behavior depended on user intent (preserve voice loop vs. accept ARN flip).

The CloudFront TLS bump and Lambda description-removal were accepted as benign drift per user direction — they are pre-existing AWS-side state that terraform's plan correctly normalizes; no code change in this plan caused them.

## Commits

| Task | Hash | Type | Subject |
|---|---|---|---|
| 1 | 488b36f | feat | observability module scaffold (versions+variables+outputs) |
| 2 | d448a88 | feat | dashboard + operational alarms (error rate, latency p95) |
| 3 | cbb3121 | feat | billing alarm in us-east-1 (D-29 $5/day cap) |
| 4 | 9b12a29 | feat | wire observability module in prod root with us-east-1 alias |
| 5 | cced9a1 | feat | live terraform apply - 1 dashboard + 3 alarms cross-region |
| 6 | e1c13dd | docs | RUNBOOK Phase 4 observability walkthrough + OBS-04/OBS-05 trade-offs |
| 7 | (this) | docs | plan summary - observability module live (1 dashboard + 3 alarms) |

7 commits total (1 fewer than the plan's "8 atomic commits" estimate because the live-apply event used a single empty-commit pattern; tasks 1-4 were 4 source-code commits; tasks 5-7 are the apply event + RUNBOOK + summary).

## Demo budget impact

Pure terraform create: 1 dashboard + 3 alarms cross-region. Zero Bedrock streaming spend, zero Lambda invocations on the presigner during apply.

Recurring cost: ~$0.10/month total (CloudWatch dashboard $3/month free tier covers 1 dashboard; CloudWatch alarms $0.10 each but $0.10 free tier covers 10 alarms — we have 3). Effectively $0/month under the AWS Free Tier for this account.

## Self-Check

Files created:
- FOUND: infra/modules/observability/versions.tf
- FOUND: infra/modules/observability/variables.tf
- FOUND: infra/modules/observability/main.tf
- FOUND: infra/modules/observability/outputs.tf
- FOUND: .planning/phases/04-observability-cost-control-cleanup/04-02-SUMMARY.md

Files modified:
- FOUND: infra/envs/prod/main.tf (module observability + alias us_east_1)
- FOUND: infra/envs/prod/outputs.tf (observability_dashboard_url, observability_billing_alarm_arn)
- FOUND: RUNBOOK.md (## Phase 4: Observability dashboard walkthrough)

Commits:
- FOUND: 488b36f (Task 1 scaffold)
- FOUND: d448a88 (Task 2 dashboard + op alarms)
- FOUND: cbb3121 (Task 3 billing alarm)
- FOUND: 9b12a29 (Task 4 prod-root wiring)
- FOUND: cced9a1 (Task 5 live apply)
- FOUND: e1c13dd (Task 6 RUNBOOK)

Live AWS resources:
- FOUND: dashboard hera-prod in ap-northeast-1
- FOUND: alarm hera-error-rate-prod in ap-northeast-1 (state OK)
- FOUND: alarm hera-latency-p95-prod in ap-northeast-1 (state OK)
- FOUND: alarm hera-billing-prod in us-east-1 (state INSUFFICIENT_DATA, threshold 5.0)
- FOUND: 0 new IAM roles
- FOUND: presigner Lambda env var AGENTCORE_RUNTIME_ARN = arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD

## Self-Check: PASSED
