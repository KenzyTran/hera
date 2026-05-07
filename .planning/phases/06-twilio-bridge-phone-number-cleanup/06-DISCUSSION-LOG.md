# Phase 6: Twilio Bridge + Phone Number + Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-07
**Phase:** 06-twilio-bridge-phone-number-cleanup
**Areas discussed:** Bridge compute shape, Audio resample location, Twilio number IaC, TwiML hosting

---

## Bridge compute shape (TWIL-02)

| Option | Description | Selected |
|--------|-------------|----------|
| API Gateway WebSocket + Lambda | Cheapest (~$0/mo idle); per-message Lambda invocations; not Pipecat-native; bridge code re-implements frame forwarding from scratch. | ✓ |
| App Runner + FastAPI bridge | Pipecat-native (TwilioFrameSerializer); ~$5-7/mo idle; auto-scale + auto SSL. | |
| Reuse agent container image on App Runner | Same image two deploys; ~$5-7/mo idle; cleanup includes App Runner. | |
| Fargate behind ALB | Heavy VPC infra; ~$15-30/mo idle; reintroduces what v1 pivoted away from. | |

**User's choice:** API Gateway WebSocket + Lambda
**Notes:** Cheapest path that respects demo-budget memory. Researcher resolves the upstream WSS persistence pattern (Lambda is stateless, Sonic needs continuous bidi audio). Pipecat first-party `[twilio]` extra is NOT used; bridge handler reimplements the byte-level Twilio Media Streams contract directly.

### Follow-up: Bridge Lambda placement

| Option | Description | Selected |
|--------|-------------|----------|
| New Terraform module `infra/modules/twilio_bridge/` | Separate module + Lambda; file-disjoint with v1; cleanup-verify-twilio.sh checks v2-only. | ✓ |
| Extend existing widget_presigner Lambda | One Lambda gains two responsibilities; risk of v2 deploy failure breaking v1 widget. | |

**User's choice:** New module `twilio_bridge`
**Notes:** Single-responsibility separation; v1 widget_presigner stays untouched.

---

## Audio resample location (TWIL-01)

| Option | Description | Selected |
|--------|-------------|----------|
| In bridge Lambda | μ-law 8kHz <-> Int16 16kHz both ways inside the bridge; agent + AgentCore container untouched. | ✓ |
| In AgentCore agent | New transport variant in agent code; rebuild + redeploy agent image; touches v1 agent. | |

**User's choice:** In bridge Lambda
**Notes:** v1 system unchanged; resample lib choice (audioop-lts vs numpy) is planner discretion based on Lambda cold-start + package-size trade-offs.

---

## Twilio number + TwiML provisioning (TWIL-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Operator paste-style via Twilio console + RUNBOOK | FCJ paste-blocks; learner uses Twilio console UI; no new TF provider; `terraform destroy` does NOT release Twilio number (cleanup-verify-twilio.sh asserts via Twilio REST API). | ✓ |
| Terraform Twilio provider (`twilio/twilio`) | Deterministic apply/destroy; pins a non-AWS provider; learner needs TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN. | |

**User's choice:** Operator paste-style via Twilio console + RUNBOOK
**Notes:** FCJ paste-style consistent with v1 RUNBOOK pattern; trade-off documented (operator manually releases Twilio resources before `terraform destroy`).

---

## TwiML hosting

| Option | Description | Selected |
|--------|-------------|----------|
| Twilio TwiML Bin (free, Twilio-hosted) | No AWS resource added; operator edits TwiML in console; URL is fixed by Twilio. Manual edit required when bridge WSS URL changes. | ✓ |
| Lambda Function URL serving TwiML | Deterministic redeploy; one more AWS resource; cleanup adds another check; renders TwiML inline from env var. | |

**User's choice:** Twilio TwiML Bin
**Notes:** Zero new AWS resources for TwiML; trade-off (operator-edit on bridge URL change) documented in RUNBOOK Phase 6 paste-blocks.

---

## Claude's Discretion

- Exact upstream WSS persistence pattern in the bridge Lambda (DynamoDB connection-id mapping vs Lambda warm-state vs invocation-per-frame fresh AgentCore session) — researcher resolves from latest AWS-published Twilio + APIGW WebSocket sample.
- Audio resample library on Lambda Python 3.12 runtime (audioop-lts shim vs numpy vs pure-Python lookup table) — planner picks based on cold-start latency + 250 MB package cap.
- Bridge Lambda reserved concurrency cap value — planner picks (likely 5; bounded by AgentCore cap=2 anyway).
- Exact Terraform module file split inside `infra/modules/twilio_bridge/` (versions/variables/main/outputs/src/handler.py vs split apigw.tf).
- API Gateway WebSocket route layout ($connect + $disconnect + $default minimum; whether `media`/`start`/`stop` need explicit routes — researcher confirms canonical pattern).
- TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN variable wiring (terraform.tfvars vs `TF_VAR_*` env vars).
- Phase 6 plan / wave structure (1 vs 2 vs 3 plans) — planner picks based on file-disjoint parallelism.
- Optional CloudWatch dashboard panel for bridge metrics — REQ does not mandate; planner may add or skip.

## Deferred Ideas

- App Runner + FastAPI bridge (Pipecat-native) — v3 backlog.
- Reusing the agent container on App Runner for the bridge — v3 backlog.
- Fargate behind ALB — v3 / production-deployment backlog.
- Terraform Twilio provider — v3 backlog.
- Lambda Function URL hosting TwiML — v3 backlog.
- Extending widget_presigner Lambda with Twilio routes — architectural anti-pattern note.
- Production-grade Twilio webhook hardening (WAF, rate limit, DDoS, auth-token rotation) — v3 scope.
- SNS/email notification for Twilio-side cost spike — out of scope per `project_v2_twilio_scope`.
- Hugo theme migration `learn` -> `relearn` (THEME-01..02) — v3 backlog.
- Multi-language chatbot speech (I18N-01..02) — v3 backlog.
- Multi-agent routing (ADV-01) — v3 backlog.
- Conversation history persistent (ADV-03 + AUTH-01..02) — v3 backlog.
