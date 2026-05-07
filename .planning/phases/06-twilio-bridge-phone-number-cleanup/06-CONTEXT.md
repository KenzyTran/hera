# Phase 6: Twilio Bridge + Phone Number + Cleanup - Context

**Gathered:** 2026-05-07
**Status:** Ready for research and planning

<domain>
## Phase Boundary

Phase 6 adds a phone-channel bridge so dialing a Twilio number reaches the existing AgentCore Runtime (`hera_agent-GIsf2P4ImD`) and Sonic answers in real time, alongside (not replacing) the v1 web widget on the same Runtime. The v1 system is unchanged — same KB `BKXE19AH89`, same AgentCore Runtime, same widget at `https://dg0w939ktclw6.cloudfront.net`, same dashboard/alarms. Phase 6 strictly ADDS resources: one bridge Lambda + API Gateway WebSocket API + IAM, plus operator-driven Twilio resources (number + TwiML Bin) provisioned via console paste-style. Cleanup mirrors v1: `bin/cleanup-verify-twilio.sh` exits 0 only when all v2 resources (AWS + Twilio) are gone.

In scope: new Terraform module `infra/modules/twilio_bridge/` (API Gateway WebSocket API + bridge Lambda + IAM role with `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream` scoped to the existing runtime ARN + CloudWatch log group); bridge handler code that translates Twilio Media Streams events (`start`, `media`, `stop`) into the Sonic bidi-stream contract over a SigV4-signed AgentCore upstream WSS; μ-law 8 kHz <-> Int16 16 kHz two-way resample inside the bridge Lambda only; RUNBOOK Phase 6 paste-blocks for Twilio account setup + number purchase + TwiML Bin creation + voice-webhook wiring; `bin/cleanup-verify-twilio.sh` mirroring `bin/cleanup-verify.sh` pattern with extra Twilio REST API checks for number-released + TwiML-Bin-removed. Out of scope: changes to the agent container / AgentCore Runtime / web widget (v1 untouched per memory `project_v2_twilio_scope`); App Runner / Fargate / new long-running compute; Terraform Twilio provider; Lambda Function URL hosting TwiML; SNS / email notifications on phone-channel cost; per-IP rate limit (AgentCore concurrency cap=2 from D-30 remains the upstream gate); workshop documentation chapter (Phase 7 owns TWIL-DOC); Hugo theme migration (deferred to v2 backlog); production-grade Twilio webhook signature validation hardening beyond the canonical `X-Twilio-Signature` HMAC verification.

</domain>

<decisions>
## Implementation Decisions

(Numbering continues from Phase 4 D-39. Phase 6 starts at D-56. D-40..D-55 are Phase 5 Workshop Documentation decisions.)

### Bridge compute shape (TWIL-02)

- **D-56: Bridge = API Gateway WebSocket API + AWS Lambda.** Cheapest demo-friendly option (~$0/mo idle, pay-per-message + per-invocation). Twilio Media Streams WS terminates at API Gateway WebSocket; APIGW routes (`$connect`, `$disconnect`, `$default`) fire the bridge Lambda per WS message. Trade-off accepted: Pipecat first-party `[twilio]` extra + `TwilioFrameSerializer` rely on a long-running FastAPI server and are NOT used here — the bridge re-implements the frame-forwarding contract from scratch over Lambda. Alternatives (App Runner FastAPI ~$5-7/mo idle, Fargate behind ALB ~$15-30/mo idle, reusing the agent container on App Runner) were rejected on demo-budget grounds (memory `project_demo_budget`).
- **D-57: Bridge Lambda lives in a NEW Terraform module `infra/modules/twilio_bridge/`** (sibling of `widget_presigner/`), NOT extended on top of the existing presigner Lambda. Reason: the widget_presigner Lambda's single responsibility (mint short-lived SigV4-presigned WSS URLs for the browser) stays intact; a v2 deploy failure cannot break v1 widget. Cleanup-verify-twilio.sh asserts only v2 resources gone; widget_presigner is explicitly NOT in its leftover list. Module shape mirrors `widget_presigner/` four-file (versions/variables/main/outputs) + `src/handler.py` for the bridge handler code.
- **D-58: Upstream WSS persistence pattern is research-resolved.** Lambda is stateless but Sonic needs continuous bidi audio; the canonical pattern (DynamoDB connection-id mapping, per-message bridge invocation, or AWS-published Twilio + APIGW WebSocket sample) is a research item the planner consumes from `gsd-phase-researcher`. The decision IS Lambda; the upstream-state mechanism is planner discretion grounded in the latest AWS documented pattern (AGENTS.md "latest APIs as of NOW").

### Audio resample location (TWIL-01)

- **D-59: μ-law 8 kHz <-> Int16 16 kHz resample lives ENTIRELY inside the bridge Lambda.** Inbound Twilio media frames are decoded from base64 + μ-law -> Int16 + upsampled 8kHz -> 16kHz before forwarding to AgentCore upstream WSS; outbound Sonic Int16 24 kHz frames (Pipecat default output) are downsampled to 16kHz then 8kHz + encoded to μ-law + base64 + wrapped in Twilio media event before write to the Twilio WS. Agent code, container image, and AgentCore Runtime are NOT modified — v1 contract preserved. Resample lib: planner picks (Python stdlib `audioop` is deprecated in 3.13; `audioop-lts` PyPI shim or `numpy` are likely candidates — researcher confirms current best practice for Lambda Python 3.12 runtime).

### Twilio number + TwiML provisioning (TWIL-03)

- **D-60: Twilio number + voice-webhook + TwiML are operator-paste-style via the Twilio console + RUNBOOK paste-blocks.** No Terraform Twilio provider added. RUNBOOK Phase 6 section walks: (a) create Twilio account, (b) buy number ($1/mo hold), (c) capture API URL via `terraform output twilio_bridge_wss_url`, (d) edit TwiML Bin in console with `<Connect><Stream url="wss://..."/>`, (e) point number's Voice webhook -> TwiML Bin URL, (f) test by dialing. FCJ paste-style consistent with v1 RUNBOOK pattern; learner uses Twilio UI which is already familiar. Trade-off: not deterministic — `terraform destroy` does NOT release the Twilio number; cleanup-verify-twilio.sh checks via Twilio REST API and instructs operator to release in console if leftover.
- **D-61: TwiML XML hosted on Twilio TwiML Bin (free, Twilio-hosted).** No Lambda Function URL serving TwiML. Voice webhook on the Twilio number points directly at the TwiML Bin URL Twilio assigns. Trade-off: when the bridge WSS URL changes (e.g., after `terraform destroy && apply`), operator manually edits the TwiML Bin in console — surfaced as a documented step in RUNBOOK. No AWS resource added for TwiML hosting.

### Cleanup (TWIL-04)

- **D-62: `bin/cleanup-verify-twilio.sh` mirrors `bin/cleanup-verify.sh` pattern verbatim.** `set -euo pipefail`, `command -v aws + jq + curl` preflight gates, paste-style FCJ, exit 2 on missing tools, exit 1 on assertion failure. Read-only — never destroys. AWS-side checks: bridge Lambda `hera-twilio-bridge-prod` gone, API Gateway WebSocket API + stages gone, IAM role + policy + log group `/aws/lambda/hera-twilio-bridge-prod` + `/aws/apigateway/hera-twilio-ws` gone. Twilio-side checks: `curl https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/IncomingPhoneNumbers.json` asserts no number with PhoneNumber matching the configured Hera bridge SID; TwiML Bins API check ditto. Operator pastes TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN as env vars before running.
- **D-63: Operator destroys before running cleanup-verify-twilio.sh; script is verify-only.** Quy trinh: (1) operator releases Twilio number in console + deletes TwiML Bin, (2) `terraform destroy` in `infra/envs/prod` (drops bridge Lambda + APIGW WS + IAM + log groups), (3) `bash bin/cleanup-verify-twilio.sh` confirms zero leftovers across both AWS + Twilio. Mirrors v1 D-39 verify-only contract.

### Demo budget + scope guardrails (carried forward)

- **D-64: v1 system is strictly NOT modified.** Concretely: no edits to `agent/`, `cdk/`, `infra/modules/{knowledge_base,kb_consumer_policy,agentcore_iam,ecr,widget_hosting,widget_presigner,observability}/`, `frontend/`, or `bin/cleanup-verify.sh`. Smoke gate at end of phase: confirm v1 web widget at `https://dg0w939ktclw6.cloudfront.net` continues to serve a voice loop (browser dial-in concurrency interaction with phone calls is bounded by AgentCore concurrency cap=2 per D-30).
- **D-65: Phone-channel cost is bounded by upstream AgentCore concurrency cap=2 (D-30).** Twilio number monthly hold ~$1/mo + Twilio inbound minutes ~$0.013/min (US/CA). Bridge Lambda has reserved concurrency cap = small (planner picks; e.g., 5) so a leaked number cannot fan out beyond AgentCore's 2-session ceiling anyway. No new CloudWatch alarms added (Phase 4 billing alarm at $5/day still covers Bedrock spend; Twilio cost lives outside AWS billing — RUNBOOK documents the operator-side Twilio usage check).
- **D-66: Bridge Lambda IAM role grants ONLY `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream` on the SPECIFIC live runtime ARN `arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD` + execute-api:ManageConnections on the bridge's APIGW + own log group writes. Zero IAM wildcards (D-13 carry-forward). Trust policy uses `aws:SourceAccount` confused-deputy condition (D-X pattern from Phase 1 / 3).
- **D-67: Twilio webhook signature validation (X-Twilio-Signature HMAC) is REQUIRED at the bridge entry point.** Twilio publishes the signing convention; bridge Lambda verifies signature using the static auth token from a Lambda env var (operator pastes via terraform variable; not committed). Without validation, the WS endpoint is anonymous public + would route arbitrary traffic to AgentCore. This is the minimum hardening — full WAF / per-IP throttle is deferred per memory `project_v2_twilio_scope` (minimal demo scope).

### Locked decisions carried forward (NOT re-litigated here)

- **From Phase 1 (D-01..D-16):** zero IAM wildcards (D-13 — every Action and Resource explicit on bridge Lambda role); region default `ap-northeast-1` override `us-east-1` (D-14); fixed names no `random_id` (D-12 — `hera-twilio-bridge-prod`, `hera-twilio-ws`, etc.); recovery path = `terraform destroy && terraform apply`; Terraform `~> 6.27` primary.
- **From Phase 2 (D-17..D-23):** Pipecat 1.1.0 + Python 3.12 + `aws-nova-sonic` extra (agent unchanged); FastAPI single app shape on AgentCore Runtime (untouched); uv-only Python (bridge Lambda uses uv to manage `audioop-lts` or `numpy` if needed).
- **From Phase 3 (D-24..D-30):** hybrid IaC = Terraform owns everything except the AgentCore Runtime resource which is CDK Python (D-24 — Phase 6 stays purely Terraform; CDK stack untouched); cleanup-contract `cdk destroy` first then `terraform destroy` second (D-24 — Phase 6 cleanup adds operator releases Twilio resources FIRST, then terraform destroy as step 2); $5/day banner copy + threshold (D-29 — Phase 6 does not change banner; web widget banner copy unchanged); AgentCore concurrency cap=2 (D-30 — phone calls compete with browser sessions in this 2-slot budget).
- **From Phase 4 (D-31..D-39):** zero new IAM beyond bridge Lambda role (D-13 carry-forward); `bin/cleanup-verify.sh` pattern (D-37, D-38 24h-deferred Cost Explorer paste-line; Phase 6's cleanup-verify-twilio.sh adopts the same shape but Twilio-aware); operator-destroys-before-verify contract (D-39); empty-commit-with-outputs-in-body pattern for live deploy events.
- **From Phase 5 (D-40..D-55):** Phase 6 is system-only; D-40..D-55 (chapter granularity, snippet drift, screenshot strategy, vi/en parity discipline) belong to Phase 7 workshop chapter — Phase 6 only outputs RUNBOOK paste-blocks + atomic commits; no Hugo content edits.
- **Demo budget rule (project memory 2026-05-06 + 2026-05-07):** prefer skip / defer / minimal-deploy. No new long-running compute. No SNS / email. No Twilio Terraform provider. Each option in this CONTEXT was chosen with that lens.

### Claude's Discretion (planner / researcher / executor decides)

- Exact upstream WSS persistence pattern in the bridge Lambda (DynamoDB connection-id mapping vs Lambda /tmp warm-state vs invocation-per-frame fresh AgentCore session) — researcher resolves from latest AWS-published Twilio + APIGW WebSocket sample (AGENTS.md "latest APIs as of NOW").
- Audio resample library on Lambda Python 3.12 runtime — `audioop-lts` PyPI shim, `numpy`, or pure-Python lookup table — planner picks based on cold-start latency + package size (Lambda 250 MB unzipped layer cap).
- Bridge Lambda reserved concurrency cap value (likely 5 — bounded by AgentCore upstream cap=2 anyway; planner picks a sensible default).
- Exact Terraform module file split inside `infra/modules/twilio_bridge/` (versions/variables/main/outputs/src/handler.py — same shape as widget_presigner; planner may add a separate `apigw.tf` if main.tf grows).
- API Gateway WebSocket route layout (`$connect` + `$disconnect` + `$default` minimum; whether `media`, `start`, `stop` need explicit routes vs `$default` switch on event-type — researcher confirms canonical pattern).
- TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN variable naming + how operator pastes (terraform.tfvars vs env-var `TF_VAR_*`) — planner picks; either is fine.
- bin/cleanup-verify-twilio.sh exact resource list (the categories above are non-negotiable; the per-resource API call shape mirrors bin/cleanup-verify.sh's _check_gone / _check_count_zero helpers).
- Phase 6 plan / wave structure: 1 plan (single bridge + cleanup-verify combined) vs 2 plans (bridge module solo Wave 1, cleanup-verify solo Wave 2) vs 3 plans (TF module + bridge handler + cleanup-verify) — planner picks based on file-disjoint parallelism.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level mandates
- `.planning/PROJECT.md` — core value, locked stack, key decisions table, scope rules, v2.0 milestone definition
- `.planning/REQUIREMENTS.md` — Phase 6 requirement IDs TWIL-01..04 (4 total) + TWIL-DOC traceability (Phase 7)
- `.planning/ROADMAP.md` — Phase 6 goal + 5 success criteria (lines 214-225) + v2.0 phase-shape rationale (lines 245-256)
- `.planning/STATE.md` — current state (milestone v2.0, Phase 6 not started)
- `CLAUDE.md` / `AGENTS.md` — no emojis, uv only, root-cause debugging, no defensive try/except, concise docstrings, latest APIs as of NOW

### Prior phase decisions (carry-forward)
- `.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md` — D-12 (fixed names), D-13 (zero IAM wildcards), D-14 (region defaults).
- `.planning/phases/02-pipecat-voice-agent-local/02-CONTEXT.md` — Pipecat 1.1.0 + Python 3.12; FastAPI app shape (UNCHANGED in Phase 6).
- `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-CONTEXT.md` — D-24 (hybrid IaC), D-25 (deploy lifecycle), D-30 (AgentCore concurrency cap=2).
- `.planning/phases/04-observability-cost-control-cleanup/04-CONTEXT.md` — D-37 (cleanup-verify pattern), D-38 (24h Cost Explorer paste-line), D-39 (verify-only operator-destroys-first contract).

### Existing assets to extend / mirror (NOT modify)
- `infra/modules/widget_presigner/` (versions/variables/main/outputs + src/handler.py) — **STRUCTURAL TEMPLATE** for the new `infra/modules/twilio_bridge/` module. Mirror four-file shape + src/handler.py. Module is NOT modified by Phase 6.
- `infra/modules/widget_presigner/src/handler.py` — pattern source for the bridge handler: SigV4 signing of AgentCore data-plane requests using `botocore.auth.SigV4QueryAuth` against `bedrock-agentcore.ap-northeast-1.amazonaws.com`. Bridge Lambda re-uses the same SigV4 mechanics but for a server-side WSS connect (not a presigned URL minted for browser).
- `infra/envs/prod/main.tf` — Phase 6 adds one more module block `module "twilio_bridge" {}` here (mirrors widget_presigner block); also adds `output "twilio_bridge_wss_url"` to `infra/envs/prod/outputs.tf`.
- `agent/hera_agent/main.py` — **NOT MODIFIED** in Phase 6. Listed for reference only — confirms `/ws` upstream contract the bridge Lambda forwards into.
- `bin/cleanup-verify.sh` — **PATTERN SOURCE** for `bin/cleanup-verify-twilio.sh`: `set -euo pipefail`, command -v preflight, _check_gone helper alternation regex, _check_count_zero helper, MSYS_NO_PATHCONV=1 quirk, exit-code conventions. Mirror verbatim style.
- `RUNBOOK.md` — extend with Phase 6 sections: Twilio account setup paste-blocks, number purchase, TwiML Bin creation + voice-webhook wiring, smoke test (dial number + speak), cleanup quy trinh (release Twilio resources FIRST, then `terraform destroy`, then `bin/cleanup-verify-twilio.sh`).

### Live AWS state (preserved through Phase 6 — NOT touched)
- AgentCore Runtime ARN: `arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD` (version=3, image hera-agent:7e72b66 multi-arch). Bridge Lambda IAM scopes to this exact ARN.
- KB id: `BKXE19AH89` (still served by AgentCore via the agent's existing `lookup_product` tool — phone calls hit the same KB).
- CloudFront widget URL: `https://dg0w939ktclw6.cloudfront.net` (browser channel still works during phone calls; the AgentCore concurrency cap=2 is the shared budget).
- ECR `hera-agent` repo (untouched — Phase 6 deploys no agent image).
- CloudWatch dashboard `hera-prod` + 2 op alarms + 1 billing alarm in us-east-1 (untouched; bridge Lambda emits its own log group; planner may optionally surface bridge metrics on the existing dashboard but this is NOT required by REQ).

### External references
- **Twilio Media Streams docs** — WebSocket protocol envelope, `start` / `media` / `stop` events, base64 + μ-law audio encoding, X-Twilio-Signature HMAC validation. Researcher MUST consume the latest Twilio docs as of NOW (AGENTS.md mandate); the bridge handler implements directly against this spec.
- **AWS API Gateway WebSocket API + Lambda integration docs** — `$connect`, `$disconnect`, `$default` route mappings; ManageConnections SDK pattern for sending messages back to a connection-id; APIGW signs incoming Twilio WS upgrade with no auth (bridge handles auth via `X-Twilio-Signature` HMAC inside Lambda).
- **AWS Bedrock AgentCore data-plane WSS contract** — `/runtimes/<URL-ENCODED-ARN>/ws?qualifier=DEFAULT` over `bedrock-agentcore.ap-northeast-1.amazonaws.com`; SigV4 signed; Sonic 8-min stream cap (Phase 2 D-19, AGT-05) is the natural max session length — bridge does NOT extend this.
- **AWS-published Twilio + APIGW WebSocket sample** — researcher mines for canonical bridge handler shape, especially the upstream WSS persistence pattern (DynamoDB connection-id table vs alternatives).
- **Pipecat 1.1.0 `[twilio]` extra source** — read-only reference for the canonical `TwilioFrameSerializer` byte-level contract (μ-law 8kHz <-> Pipecat audio frames). The bridge does NOT import Pipecat (Lambda is too thin for it) but follows the SAME byte contract so the upstream agent's existing pipeline accepts the audio without modification.
- **Reference architectures (already locked stack):**
  - [Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/)
  - [aws-samples/sample-nova-sonic-websocket-agentcore](https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`infra/modules/widget_presigner/main.tf`** — four-file Terraform module shape (versions / variables / main / outputs + src/handler.py); Lambda + Function URL + IAM trust + inline policy + log group. Phase 6's `infra/modules/twilio_bridge/` mirrors this shape, swapping Function URL for API Gateway WebSocket API + integration + 3 routes ($connect/$disconnect/$default).
- **`infra/modules/widget_presigner/src/handler.py`** — `botocore.auth.SigV4QueryAuth` against `bedrock-agentcore.<region>.amazonaws.com` SERVICE = `bedrock-agentcore`. Bridge Lambda reuses the SigV4 mechanics for the server-side upstream WSS connect (not a presigned URL — direct request signing).
- **`bin/cleanup-verify.sh`** — exact pattern source: `set -euo pipefail`, `command -v aws / jq` preflight with platform install hints, `_check_gone` helper with multi-error-name alternation regex, `_check_count_zero` helper, MSYS_NO_PATHCONV=1 quirk for log-group names, exit-code 2 on missing tools, exit-code 1 on assertion failure, paste-style FCJ.
- **`agent/hera_agent/main.py`** — `/ws` WebSocket upstream the bridge Lambda forwards into (via SigV4-signed AgentCore data-plane WSS, NOT directly — AgentCore wraps it). Listed for reference; NOT modified.
- **`infra/envs/prod/main.tf` lines 50-62 (widget_presigner module block)** — exact pattern for Phase 6's `module "twilio_bridge" {}` block. The `agentcore_runtime_arn` variable is already a TF root variable (Plan 03-04 chicken-and-egg pattern); Phase 6 reuses the same variable wiring.
- **`infra/envs/prod/outputs.tf`** — Phase 6 adds one new output `twilio_bridge_wss_url` here (the APIGW WS endpoint URL, derived from `${aws_apigatewayv2_api.bridge.api_endpoint}/${stage}`). RUNBOOK paste-blocks reference this output.

### Established Patterns
- **TF root + thin module four-file shape** (Phase 1 D-08, repeated in widget_presigner) — versions.tf / variables.tf / main.tf / outputs.tf + src/ for Lambda code. Phase 6 follows.
- **Zero IAM wildcards** (D-13) — bridge Lambda role grants `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream` on the EXACT runtime ARN, `execute-api:ManageConnections` on the EXACT APIGW ARN, log writes on its own log group only.
- **Confused-deputy condition** (`aws:SourceAccount = 851725411875`) on the Lambda trust policy — pattern from widget_presigner Phase 3.
- **No defensive try/except** (AGENTS.md) — bridge handler does NOT wrap AWS / Bedrock / KB calls; only bounded try/except is for the documented Twilio WS protocol close path (mirrors agent's `WebSocketDisconnect` pattern).
- **Atomic conventional commits** scoped to plan id (e.g., `feat(06-01): add twilio_bridge module`).
- **Empty-commit-with-outputs-in-body for live deploy events** (Plan 03-01) — Phase 6's `terraform apply` event uses this pattern.
- **Operator-destroys-then-verifies cleanup contract** (D-39) — Phase 6 extends with operator-releases-Twilio-FIRST step before terraform destroy.
- **Lazy-default config + boto3 default chain credential bridge** (Plan 03-05) — bridge Lambda inherits the IAM role's credentials via boto3 default chain (Lambda runtime injects); no env-var AWS keys.

### Integration Points
- **Twilio -> APIGW WebSocket -> Bridge Lambda** — Twilio dials the configured number; voice webhook returns the TwiML Bin XML which contains `<Connect><Stream url="wss://${apigw_wss_url}"/>`; Twilio opens a WebSocket to the APIGW endpoint; APIGW routes ($connect/$disconnect/$default) fire the bridge Lambda per WS message.
- **Bridge Lambda -> AgentCore Runtime** — bridge Lambda opens a SigV4-signed upstream WSS to `bedrock-agentcore.ap-northeast-1.amazonaws.com/runtimes/<URL-ENC-ARN>/ws?qualifier=DEFAULT` per phone call; resampled audio frames forwarded both ways. This is the SAME upstream the widget uses (via the presigned URL); Phase 6's bridge signs server-side instead of minting a URL for the browser.
- **AgentCore concurrency cap=2** (D-30) is the SHARED upstream budget for browser + phone — a phone call competes with browser sessions for one of the 2 slots. RUNBOOK documents this interaction.
- **bin/cleanup-verify-twilio.sh -> AWS APIs + Twilio REST API** — read-only describe / list calls only; no destroy from script. AWS side: bridge Lambda + APIGW WS + IAM + log groups. Twilio side: `curl https://api.twilio.com/2010-04-01/Accounts/${SID}/IncomingPhoneNumbers.json` asserts no number leftover; TwiML Bins ditto.
- **Phase 6 -> Phase 7 hand-off** — RUNBOOK Phase 6 paste-blocks (Twilio account setup + number purchase + TwiML Bin creation + voice-webhook wiring + smoke test + cleanup) become the screenshot/snippet/verification source for Phase 7's workshop chapter `content/{vi,en}/3-hands-on/3.6-twilio-channel/_index.md` (TWIL-DOC).

</code_context>

<specifics>
## Specific Ideas

- **Live AgentCore Runtime ARN target:** `arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD` (version=3, READY). Bridge Lambda IAM scopes EXACTLY to this ARN (zero wildcards).
- **Live KB id (carried via AgentCore agent code):** `BKXE19AH89` — phone calls hit the same KB through the unchanged agent's `lookup_product` tool. Phase 6 does NOT touch the KB.
- **Bridge fixed name:** `hera-twilio-bridge-prod` (Lambda function), `hera-twilio-ws` (APIGW WebSocket API name), `/aws/lambda/hera-twilio-bridge-prod` (log group), `/aws/apigateway/hera-twilio-ws` (APIGW log group). D-12 fixed names, no `random_id`.
- **Twilio inbound cost reference:** ~$1/mo number hold + ~$0.013/min inbound (US/CA) — RUNBOOK Phase 6 cost-bullet documents this for learner awareness.
- **Sonic 8-min stream cap:** carried from Phase 2 (AGT-05). A phone call longer than 8 minutes triggers Pipecat `SessionContinuationParams(transition_threshold_seconds=360)` rotation in the agent — bridge does NOT need to handle this; the agent's existing logic fires per-WSS-session inside AgentCore.
- **TwiML Bin XML target shape (operator pastes in Twilio console):**
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <Response>
    <Connect>
      <Stream url="wss://<APIGW-WS-URL>/prod" />
    </Connect>
  </Response>
  ```
- **cleanup-verify-twilio.sh AWS resource list (target = empty / 404 / NotFound):**
  - Bridge Lambda `hera-twilio-bridge-prod`
  - APIGW WebSocket API `hera-twilio-ws` (and its stages + integrations + routes)
  - IAM role `hera-twilio-bridge-prod-exec` + inline policy
  - CloudWatch log groups `/aws/lambda/hera-twilio-bridge-prod` + `/aws/apigateway/hera-twilio-ws`
- **cleanup-verify-twilio.sh Twilio resource list (target = empty):**
  - No `IncomingPhoneNumbers` whose `FriendlyName` matches `hera-twilio-bridge` or whose `VoiceUrl` references the configured TwiML Bin SID
  - No `TwimlBin` whose `FriendlyName` matches `hera-bridge-prod`

</specifics>

<deferred>
## Deferred Ideas

(Items raised or implied during discussion that belong outside Phase 6 scope.)

- **Pipecat first-party `[twilio]` extra + TwilioFrameSerializer + App Runner FastAPI bridge** — explicitly skipped per D-56 (~$5-7/mo idle minimum violates demo budget). If a future v3 wants Pipecat-native phone bridge, App Runner is the natural pick — capture for v3 backlog.
- **Reusing the agent container image on App Runner for the bridge** — alternative considered for D-56; rejected on demo-budget grounds. Capture for v3 if dual-deploy pattern proves useful.
- **Fargate behind ALB** — alternative considered for D-56; rejected on heavy infra grounds (~$15-30/mo idle + VPC re-introduction). Capture for production deployment if Hera ever serves real public traffic.
- **Terraform Twilio provider (`twilio/twilio`)** — alternative considered for D-60; rejected on minimal-scope grounds (paste-style is FCJ-friendly + cleaner for learners). Capture for v3 if instructor wants deterministic Twilio destroy.
- **Lambda Function URL hosting TwiML XML** — alternative considered for D-61; rejected on minimal-scope grounds (TwiML Bin is free + Twilio-hosted). Capture for v3 if dynamic TwiML rendering is ever needed.
- **Extending the existing widget_presigner Lambda with Twilio routes** — alternative considered for D-57; rejected on single-responsibility grounds (v2 deploy failure must not break v1 widget). Capture as architectural anti-pattern note.
- **Production-grade Twilio webhook hardening** (full WAF rules, rate limiting, DDoS protection, auth-token rotation automation) — explicitly v3 scope per memory `project_v2_twilio_scope`. D-67 minimum hardening (X-Twilio-Signature HMAC) is the v2 baseline.
- **CloudWatch dashboard panel for bridge Lambda metrics** — planner may optionally add a panel to the existing `hera-prod` dashboard but the REQ does NOT mandate it. If skipped, RUNBOOK documents `aws logs tail /aws/lambda/hera-twilio-bridge-prod --follow` as the operator observability path.
- **SNS/email notification for Twilio-side cost spike** — explicitly out of scope per memory `project_v2_twilio_scope`. Twilio publishes its own usage console; operator monitors there.
- **Phase 7 workshop chapter `3.6-twilio-channel`** — separate phase; Phase 6 only outputs RUNBOOK paste-blocks that Phase 7 then transforms into bilingual chapter content per D-49 / D-50.
- **Hugo theme migration `learn` -> `relearn`** — v3 backlog (THEME-01..02 in REQUIREMENTS.md).
- **Multi-language chatbot speech (I18N-01..02)** — v3 backlog.
- **Multi-agent routing (ADV-01)** — v3 backlog.
- **Conversation history persistent (ADV-03 + AUTH-01..02)** — v3 backlog.

</deferred>

---

*Phase: 06-Twilio Bridge + Phone Number + Cleanup*
*Context gathered: 2026-05-07*
