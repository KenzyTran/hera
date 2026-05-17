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
result: passed 2026-05-17
notes: Closed after extensive debug session. v1 voice loop works end-to-end in production:
  greeting fires on connect, user speech transcribed by Sonic, lookup_product tool dispatched
  to KB Retrieve (~326ms KB+S3 Vectors round-trip), bot synthesizes a KB-grounded answer
  audible to the user, multi-turn conversation supported. Container log evidence in
  /aws/bedrock-agentcore/hera-agent, Bedrock invocation log in /aws/bedrock/invocations
  (Titan embed of "do you have macbook pro?" returning 1024-dim vector confirms vector
  search ran), AgentCore root span in aws/spans with session.id + latency.

  Cumulative fixes from 2026-05-16 + 2026-05-17 sessions:
  - 4c8e52e fix(widget): app.js typeof check broke sed-replace
  - b835d5a fix(widget_presigner): duplicate Access-Control-Allow-Origin
  - 8bee78a fix(agentcore_iam): sonic_model_arn bumped to amazon.nova-2-sonic-v1:0
  - 2a36ec7 fix(agent): Pipecat 1.1.0 -> 1.2.1 restores cancel_on_interruption=False for Sonic
  - 6fbdb7a fix(widget): batch mic to 20ms chunks under AgentCore 250 fps WS limit
  - e52b45a fix(widget_presigner): unique session_id (UUID) in WSS URL
  - 3f4ffba chore(v1): grant bedrock:InvokeModel + InvokeModelWithResponseStream +
    bedrock-agentcore:GetWorkloadAccessToken* on exec role (root cause of silent Sonic stream)
  - 1214e7b feat(agent): watchtower CloudWatch log shipping + exception wrapping
  - Account-level: Bedrock invocation logging enabled, X-Ray Transaction Search ACTIVE,
    AgentCore tracing delivery wired, X-Ray indexing sampling raised 1% -> 100%.

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
passed: 1
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
