---
status: partial
phase: 04-observability-cost-control-cleanup
source: [04-VERIFICATION.md]
started: 2026-05-06
updated: 2026-05-06
---

## Current Test

[awaiting human testing — none of the 5 items block Phase 4 close; all are design-time deferrals or workshop-close events]

## Tests

### 1. Live browser voice loop on https://dg0w939ktclw6.cloudfront.net/
expected: Click record → grant mic permission → ask "Do you have MacBook Pro?" → hear a KB-backed Apple Store answer streamed back. Closes Phase 3 SC#2 visibly to instructor in addition to the data-plane smoke probe (already passed in Plan 04-01).
result: [pending]

### 2. Tick "Receive CloudWatch Billing Alerts" in Billing Preferences (RESEARCH A1)
expected: Open https://console.aws.amazon.com/billing/home#/preferences → Edit Alert preferences → tick "Receive CloudWatch Billing Alerts" → Save. Wait ~15 min. Billing alarm `hera-billing-prod` (us-east-1) transitions out of INSUFFICIENT_DATA within 24h.
result: [pending]

### 3. First organic `bash bin/cleanup-verify.sh` run at workshop close
expected: Run after `cdk destroy hera-agentcore` + `terraform destroy`. All 19 resource checks return OK; script exits 0 with `OK (cleanup): all hera resources removed`. If any FAIL, follow the cleanup-contract hints printed by the script.
result: [pending]

### 4. 24h-deferred Cost Explorer $0 paste-line (D-38)
expected: 24h after workshop-close cleanup, run the paste-line in RUNBOOK Phase 4 cleanup section. Expected output: `"0"` or `"0.0000000000"`. Anything non-zero indicates a leftover billable resource.
result: [pending]

### 5. AgentCore concurrency cap=2 service-quota request (D-30)
expected: Open AWS Service Quotas console for Bedrock AgentCore in ap-northeast-1 → request quota increase OR cap reduction so concurrent runtime sessions = 2 (instead of default 10). Operational console action; not IaC.
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
