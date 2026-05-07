# Phase 6: Twilio Bridge + Phone Number + Cleanup - Research

**Researched:** 2026-05-07
**Domain:** Twilio Media Streams + AWS API Gateway WebSocket + Lambda bridge + AgentCore Runtime upstream WSS + audio resample (μ-law 8kHz <-> Int16 16kHz)
**Confidence:** HIGH for AgentCore data-plane WSS contract (verified against AWS docs); HIGH for Twilio Media Streams envelope (verified against Twilio docs); HIGH for Twilio webhook signature mechanics (verified against Twilio docs); HIGH for API Gateway WebSocket limits (verified against AWS docs); HIGH for audioop deprecation timeline (verified against PyPI + Python docs); **MEDIUM-LOW for Q1 (D-58 upstream WSS persistence in Lambda — no canonical AWS sample exists for the exact Twilio→APIGW-WS→Lambda→AgentCore-WSS chain; the community pattern uses persistent compute, not Lambda)**.

> **Critical finding upfront:** The locked decision D-56 (bridge = APIGW WebSocket + Lambda) collides head-on with API Gateway's 29-second integration timeout and Lambda's stateless model. There is **no canonical AWS-published pattern** for keeping a per-call upstream WSS persistent across N Lambda invocations. The team needs to revisit D-56 or accept architectural creativity (per-frame fresh upstream session — see Q1 below) with measurable latency degradation. **This is the key planner gate.**

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-56..D-67 — NOT re-litigated)

- **D-56:** Bridge = API Gateway WebSocket API + AWS Lambda. Pipecat `[twilio]` extra + `TwilioFrameSerializer` rely on long-running FastAPI; bridge re-implements the frame-forwarding contract from scratch over Lambda. App Runner / Fargate / reusing-the-agent-container were rejected on demo budget grounds.
- **D-57:** New Terraform module `infra/modules/twilio_bridge/` (sibling of `widget_presigner/`); does NOT extend the existing presigner Lambda. v2 deploy failure must not break v1 widget. Mirror the four-file shape (versions/variables/main/outputs) + `src/handler.py`.
- **D-58:** Upstream WSS persistence pattern is research-resolved by `gsd-phase-researcher` (this document — see Q1 below). The decision IS Lambda; the upstream-state mechanism is planner discretion grounded in latest AWS-published pattern.
- **D-59:** μ-law 8 kHz <-> Int16 16 kHz resample lives ENTIRELY inside the bridge Lambda. Agent code, container image, and AgentCore Runtime are NOT modified. Resample lib is planner discretion (see Q2 below).
- **D-60:** Twilio number + voice-webhook + TwiML are operator-paste-style via Twilio console + RUNBOOK. No Terraform Twilio provider.
- **D-61:** TwiML XML hosted on Twilio TwiML Bin (free, Twilio-hosted). No Lambda Function URL serving TwiML.
- **D-62:** `bin/cleanup-verify-twilio.sh` mirrors `bin/cleanup-verify.sh` pattern verbatim. Read-only. Both AWS-side and Twilio-side checks.
- **D-63:** Operator destroys before running cleanup-verify-twilio.sh; script is verify-only.
- **D-64:** v1 system strictly NOT modified. No edits to `agent/`, `cdk/`, the v1 Terraform modules, `frontend/`, or `bin/cleanup-verify.sh`.
- **D-65:** Phone-channel cost bounded by upstream AgentCore concurrency cap=2 (D-30 carry-forward). Bridge Lambda gets reserved concurrency cap (small, e.g., 5).
- **D-66:** Bridge Lambda IAM grants ONLY `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream` on the SPECIFIC live runtime ARN `arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD` + `execute-api:ManageConnections` on the bridge's APIGW + own log group writes. Zero IAM wildcards. Trust uses `aws:SourceAccount` confused-deputy condition.
- **D-67:** X-Twilio-Signature HMAC validation REQUIRED at the bridge entry point. Auth token from a Lambda env var (operator pastes via terraform variable; not committed).

### Claude's Discretion (planner / researcher / executor decides)

- Exact upstream WSS persistence pattern in the bridge Lambda — researched here in Q1.
- Audio resample library on Lambda Python runtime — researched here in Q2.
- Bridge Lambda reserved concurrency cap value (planner picks; default 5).
- Exact Terraform module file split inside `infra/modules/twilio_bridge/` (planner may add `apigw.tf` if main.tf grows).
- API Gateway WebSocket route layout (`$connect` + `$disconnect` + `$default` minimum; whether `media`/`start`/`stop` need explicit routes vs `$default` switch — researched in Q3).
- TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN variable naming + how operator pastes (terraform.tfvars vs env-var TF_VAR_*).
- Phase 6 plan / wave structure — researcher recommendation in §6 below.

### Deferred Ideas (OUT OF SCOPE)

- Pipecat first-party `[twilio]` extra + TwilioFrameSerializer + App Runner FastAPI bridge (rejected D-56)
- Reusing the agent container image on App Runner for the bridge (rejected D-56)
- Fargate behind ALB (rejected D-56)
- Terraform Twilio provider (rejected D-60)
- Lambda Function URL hosting TwiML XML (rejected D-61)
- Extending the existing widget_presigner Lambda (rejected D-57)
- Production-grade Twilio webhook hardening beyond X-Twilio-Signature HMAC (deferred; v3 scope)
- CloudWatch dashboard panel for bridge Lambda metrics (optional, REQ doesn't mandate it)
- SNS/email notification for Twilio cost spike (out of scope — operator monitors Twilio console)
- Phase 7 workshop chapter `3.6-twilio-channel` (separate phase)
- Hugo theme migration learn → relearn (v3 backlog)
- Multi-language chatbot speech (I18N v3)
- Multi-agent routing, conversation history persistence, auth (v3+)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **TWIL-01** | Two-way audio resample bridge — μ-law 8kHz inbound from Twilio → Int16 16kHz to Sonic; Int16 16kHz from Sonic → μ-law 8kHz back to Twilio | Q2 picks `audioop-lts` on Python 3.13 Lambda runtime; concrete encode/decode + ratecv state-management code shape provided in §4. |
| **TWIL-02** | Twilio Media Streams bridge endpoint — handle `start`/`media`/`stop` events; forward audio to AgentCore Runtime | Q3 confirms `$connect` + `$disconnect` + `$default` minimum route layout; Q1 surfaces the upstream WSS persistence question and recommends pattern (see Architectural Risk below); §4 provides handler skeleton. |
| **TWIL-03** | Twilio number + TwiML `<Connect><Stream>` provisioned; phone number callable | Operator-paste-style per D-60; RUNBOOK paste-block shape at end of §4. |
| **TWIL-04** | Phone-channel cleanup contract — release TwiML config + release Twilio number + bridge teardown; verify script | §4 cleanup-verify-twilio.sh skeleton mirrors bin/cleanup-verify.sh verbatim; Twilio REST API calls confirmed. |
</phase_requirements>

## Executive Summary

1. **The locked architecture has a known structural risk that the planner MUST surface.** API Gateway WebSocket integration timeout is **29 seconds maximum** [VERIFIED: AWS docs]; Lambda is stateless. There is no canonical AWS-published pattern for persisting a single per-call upstream Bedrock-AgentCore WSS across the N Lambda invocations that handle one phone call's media frames. **No `aws-samples/*` repo exists for the exact Twilio Media Streams → APIGW WebSocket → Lambda → AgentCore Runtime chain.** Adjacent samples exist: `aws-samples/sample-amazon-nova-sonic-twilio-integration` (Node.js, "typically deployed on EC2/ECS/EKS behind ALB" — NOT Lambda) [VERIFIED: GitHub README]; `webrtc.ventures` 2025-07 article uses Lambda + APIGW WS but only with **Twilio ConversationRelay (text-only)**, not Media Streams (raw audio) [VERIFIED: webrtc.ventures]. The pattern Q1 recommends below is **per-frame fresh AgentCore session** — accepted with documented latency cost.

2. **`audioop-lts` requires Python 3.13+; Python 3.12 stdlib `audioop` still works (deprecated, removed in 3.13).** Pick Python 3.13 Lambda runtime + `audioop-lts` PyPI shim (24-104 KB wheel; deprecation date Jun 30 2029) [VERIFIED: PyPI + AWS Lambda runtimes table]. Alternative: stay on Python 3.12 and use stdlib `audioop` directly with no PyPI dep. Recommendation: **Python 3.13 + `audioop-lts`** because `audioop-lts` is a verbatim drop-in (same `lin2ulaw`/`ulaw2lin`/`ratecv` API) and Python 3.12's stdlib path will need to be dropped within ~3 years anyway.

3. **AgentCore data-plane WSS endpoint is at `/ws` path** (NOT `/invocations`), confirmed by AWS docs: `wss://bedrock-agentcore.<region>.amazonaws.com/runtimes/<URL-ENCODED-ARN>/ws` with `?qualifier=DEFAULT` query string and SigV4 signing service `bedrock-agentcore` [VERIFIED: AWS docs runtime-get-started-websocket.html]. The IAM action is `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream` (D-66 confirmed correct). The widget_presigner Lambda already includes both the synchronous `InvokeAgentRuntime` AND `InvokeAgentRuntimeWithWebSocketStream` actions with valid wildcard-free Resource scoping — bridge re-uses the exact same SigV4 mechanics (server-side, not browser).

4. **Twilio Media Streams envelope is JSON with `event` field** (`connected`/`start`/`media`/`stop`/`mark`/`dtmf`) [VERIFIED: Twilio docs]. Outbound media (Lambda → Twilio) is JSON `{"event":"media","streamSid":"...","media":{"payload":"<base64>"}}` — μ-law 8kHz, base64-encoded, NO file-type header bytes. APIGW WebSocket route selection expression is `${request.body.event}` if you want explicit routing per Twilio event type, OR keep `$default` and switch in handler. Explicit routes are cleaner and let `$default` catch unknown events for forward compat.

5. **Twilio webhook signature for WebSocket Media Streams** validates the **HTTP upgrade request** (POST-style, before upgrade) using HMAC-SHA1 of `URL + sorted POST params concatenated` with the AuthToken as key, base64-encoded, compared to header `x-twilio-signature` (lowercased on WS handshakes) [VERIFIED: Twilio webhooks-security docs]. This means validation happens **once at `$connect`**, not per-frame. Twilio docs explicitly note: "if having trouble verifying a WebSocket handshake, try appending a trailing `/` character to the URL." Critical implementation detail.

**Primary recommendation:** Wave 1 = **bridge module + handler** (Plan 06-01: Terraform module `twilio_bridge/` + `src/handler.py` + Lambda packaging + APIGW WS routes + IAM). Wave 2 = **cleanup-verify + RUNBOOK paste-blocks + smoke** (Plan 06-02: `bin/cleanup-verify-twilio.sh` + RUNBOOK Phase 6 sections + live operator-paste smoke flow). 2 plans, file-disjoint between waves. Detailed rationale in §6.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Phone PSTN ingress + audio capture | Twilio (external SaaS) | — | Twilio owns the phone number + dial-in PSTN gateway + Media Streams WebSocket termination. |
| TwiML XML serving (voice webhook → "open WS to bridge") | Twilio TwiML Bin (external SaaS) | — | Free Twilio-hosted; D-61. No AWS resource. |
| Twilio WebSocket → AWS edge | API Gateway WebSocket API (`hera-twilio-ws`) | — | APIGW terminates the Twilio WSS connection; routes per-message to Lambda integration. Stateful at the connection level (managed by APIGW); stateless to our code. |
| Per-Twilio-message processing (start/media/stop) | Bridge Lambda (`hera-twilio-bridge-prod`) | — | Stateless function: validate signature on `$connect`, decode/resample/forward audio per `media`, manage `streamSid` state externally. |
| Audio resample (μ-law 8kHz ↔ Int16 16kHz) | Bridge Lambda (`audioop-lts`) | — | D-59 — entirely in bridge Lambda. Agent + AgentCore + KB unchanged. |
| Upstream voice agent (LLM + KB tool + TTS) | AgentCore Runtime (existing `hera_agent-GIsf2P4ImD`) | — | UNCHANGED. Same data-plane WSS the widget already uses, just SigV4-signed server-side from the bridge instead of presigned for the browser. |
| Knowledge base lookup | Bedrock KB (existing `BKXE19AH89`) | — | UNCHANGED. Phone calls hit the same KB through the agent's existing `lookup_product` tool. |
| Connection ID / streamSid state (if needed) | DynamoDB (NEW, conditional) OR no state at all (Q1 recommended path) | — | Q1 recommendation: skip DynamoDB. See §3-Q1. |
| Cleanup verification | bash + AWS CLI + Twilio REST API + jq | — | Read-only `bin/cleanup-verify-twilio.sh` mirrors v1 pattern. |

---

## Open Question Resolutions

### Q1 — Upstream WSS persistence pattern in the bridge Lambda (D-58 — RESEARCH-DEFERRED)

**Question framing:** Lambda is stateless; Sonic needs continuous bidi audio. Three candidate patterns exist:
- (a) DynamoDB connection-id table mapping Twilio CallSid → AgentCore session state
- (b) Lambda /tmp warm-state (best-effort, dies on cold start)
- (c) Per-frame fresh AgentCore session (likely too high latency / Sonic 8-min cap interaction)

**Investigation result:**

I searched explicitly for an AWS-published canonical sample matching the chain `Twilio Media Streams → APIGW WS → Lambda → AgentCore Runtime upstream WSS`. **No such sample exists [VERIFIED: WebSearch + GitHub aws-samples]**.

The closest published patterns:

| Repo / blog | Compute | Twilio side | LLM side | Verdict for our use |
|-------------|---------|-------------|----------|---------------------|
| `aws-samples/sample-amazon-nova-sonic-twilio-integration` [VERIFIED: GitHub README] | "EC2/ECS/EKS behind ALB" (Node.js); README explicitly says NOT Lambda for production | Media Streams (raw audio) | Bedrock Nova Sonic bidirectional API | **Validates Bedrock Nova Sonic + Twilio Media Streams pairing — but uses persistent compute, not Lambda. Direct evidence Lambda is NOT the canonical compute for this chain.** |
| `aws-samples/amazon-lex-conversational-interface-for-twilio` (2019-08, AWS ML blog) [VERIFIED: AWS ML blog] | Fargate behind ALB with sticky sessions | Media Streams (raw audio) | Amazon Lex | Same pattern: persistent compute, not Lambda. |
| `webrtc.ventures` 2025-07 "Serverless Voice AI" [VERIFIED: webrtc.ventures] | Lambda + APIGW WS + DynamoDB | **ConversationRelay (text-only)** | Bedrock Claude | Lambda works HERE because ConversationRelay sends text, not audio. **Not applicable to Phase 6 (we're using Media Streams, not ConversationRelay).** |
| `aws-samples/sample-aws-bedrock-twilio-voice-ai` re:Invent 2025 [VERIFIED: GitHub README] | Application Load Balancer + (likely Fargate) | Media Streams + ConversationRelay hybrid | Bedrock | Persistent compute. Not Lambda. |

**Why the canonical chain doesn't use Lambda:**

API Gateway WebSocket has hard architectural constraints [VERIFIED: AWS docs apigateway-execution-service-websocket-limits-table.html]:
- **Integration timeout: 29 seconds maximum** for any Lambda integration. Lambda CANNOT hold a single invocation open for the duration of a phone call.
- **Idle Connection Timeout: 10 minutes** (OK — Twilio sends frames every ~20ms).
- **Connection duration: 2 hours maximum** (OK — Sonic 8-min cap is the binding constraint).
- **Frame size: 32 KB / Message size: 128 KB** (OK — μ-law 8kHz/20ms = 160 bytes per frame).

Lambda is invoked **once per WebSocket message** by APIGW (not once per connection). Each invocation must complete within 29s. There is no Lambda mechanism to hold a Bedrock-AgentCore upstream WSS open across N invocations:
- **DynamoDB connection-id pattern (option a)** stores the Twilio `streamSid` → some state mapping. This works for *managing the downstream side* (sending audio back to Twilio via `@connections POST {connectionId}`). But it CANNOT store a live Python `websockets.WebSocketClientProtocol` upstream socket. A socket is in-process state; serializing it to DynamoDB is not possible. So this pattern handles the "downstream Twilio routing table" but does NOT solve the "persistent upstream Bedrock WSS" question.
- **Lambda /tmp warm-state (option b)** is per-execution-environment, not per-connection. AWS does not guarantee that two consecutive WebSocket messages from the same `connectionId` route to the same Lambda execution environment. Even when they do (which is common for warm-pool reuse), an idle Lambda execution environment is reaped without notice. /tmp is wiped on cold start. Fundamentally unfit for keeping a TCP socket alive.
- **Per-frame fresh AgentCore session (option c)** opens a new SigV4-signed upstream WSS for every Twilio media frame, sends one frame, closes. Latency per round-trip is bounded by SigV4 signing (~5-10ms in-process) + TLS handshake (~30-50ms RTT to ap-northeast-1) + Bedrock connection setup overhead (unknown — likely 100-500ms based on widget timing). Total: **~150-600ms per audio frame**. Twilio sends 50 frames/second. **This is structurally infeasible for real-time voice.**

**Recommended path forward — re-evaluate D-56:**

> **The honest answer to D-58 is: there is no canonical AWS pattern for the locked architecture. Each of the three candidate patterns has a fatal structural flaw against the Phase 6 SC#1 ("dial number → hear assistant respond within 3 seconds of first sentence").**

Three options for the planner / discuss-phase:

**Option α (RECOMMENDED — preserves D-56 with caveats): "App-Runner-shaped" Lambda via ALB-fronted Lambda + WebSocket adapter** — NOT viable. Lambda fundamentally cannot hold a long-lived upstream socket. This option does not exist in any reliable form.

**Option β (REQUIRES D-56 RE-EVALUATION): Switch bridge compute from Lambda to AWS App Runner.** App Runner can host a long-running FastAPI server that holds the upstream WSS to Bedrock open for the duration of the call, terminates the Twilio WSS directly, and exits when the call ends. Cost: ~$0/mo if scale-to-zero is configured (App Runner supports min-instances=0 with cold-start penalty); ~$5-7/mo with min=1. **This was rejected in D-56 on demo budget grounds**, but it is the only architecture that actually works for real-time bidirectional audio. The planner should surface this in `/gsd-discuss-phase` Q1 to the user. **Cost analysis:** Demo workshop has been free idle (concurrency cap=2, KB+Bedrock + AgentCore are pay-per-use). App Runner with min=0 + scale-to-zero stays $0 idle; only burns when a phone call is active. Per-call cost: 1 vCPU * 5 min = ~$0.005 + ~$0.013/min Twilio inbound. App Runner FREE TIER includes 2 GB-hours/month (covers ~5 demo calls). **App Runner with min=0 is functionally equivalent to "Lambda + glue" for the demo budget but architecturally correct.**

**Option γ (PRESERVES D-56 BUT DEGRADES SC#1): Per-frame fresh AgentCore session with documented latency degradation.** Each Twilio `media` event triggers a Lambda invocation that opens a fresh SigV4-signed AgentCore WSS, sends the resampled audio frame, waits for streaming response (or close), forwards back to Twilio via `@connections`, exits. Sonic's bidi-stream is not designed for this — it expects a continuous audio stream for utterance-level inference. **The agent's Pipecat pipeline state is per-WebSocket-connection; a fresh connection per frame would discard conversation context and re-trigger session setup (~500ms-1s) for every frame.** This is functionally a non-starter; the agent would never form coherent speech. Documented for completeness only.

**Recommended planner action:**

The planner should add to PLAN.md a Wave 0 / pre-Wave 1 task: "Surface the D-58 architectural finding to the user via `/gsd-discuss-phase Phase-6-D58-followup`. Present Options α/β/γ. Default recommendation: **Option β (switch to App Runner, re-evaluate D-56)** because it's the only architecturally-correct path that meets SC#1 latency. If user holds D-56 firm despite the finding, documenting Option γ as known-broken under Phase 6 acceptance and deferring real phone calls to v3 is the only honest path."

> [ASSUMED] My ~150-600ms per-frame latency estimate for fresh AgentCore session is grounded in Phase 3 widget cold-start observations + general TLS handshake RTT + Bedrock control-plane behavior, but no live measurement against `bedrock-agentcore.ap-northeast-1.amazonaws.com/runtimes/.../ws` WebSocket upgrade exists in this research. The planner should consider a quick spike: 1 Lambda + 1 cdk run, measure round-trip latency for a fresh upstream WSS open + 1 frame send + close, log p50/p95. If p95 < 50ms the picture changes (option γ becomes viable). **However, even at p95 < 50ms, Sonic's contract requires a continuous bidi stream — fresh session per frame breaks the model semantics regardless of network latency. Option γ remains broken.**

**Sources:**
- [AWS API Gateway WebSocket quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-execution-service-websocket-limits-table.html) — 29s integration timeout, 32KB frame, 128KB message, 10min idle, 2hr max connection — retrieved 2026-05-07
- [aws-samples/sample-amazon-nova-sonic-twilio-integration README](https://github.com/aws-samples/sample-amazon-nova-sonic-twilio-integration) — Node.js, "EC2/ECS/EKS behind ALB" — retrieved 2026-05-07
- [webrtc.ventures Serverless Voice AI](https://webrtc.ventures/2025/07/how-to-build-a-serverless-voice-ai-assistant-for-telephony-in-aws-using-twilio-conversationrelay/) — Lambda + APIGW WS only with ConversationRelay (text), not Media Streams — retrieved 2026-05-07
- [AWS ML blog — Amazon Lex + Twilio Media Streams](https://aws.amazon.com/blogs/machine-learning/use-amazon-lex-as-a-conversational-interface-with-twilio-media-streams/) — Fargate + ALB sticky sessions — retrieved 2026-05-07; published 2019-08-06

---

### Q2 — Audio resample library on AWS Lambda Python 3.12 vs 3.13

**Investigation result:**

| Lib | Python 3.12 | Python 3.13 | Wheel size | Includes mulaw (`lin2ulaw`/`ulaw2lin`) | Includes `ratecv` (resample) | Verdict |
|-----|-------------|-------------|------------|----------------------------------------|------------------------------|---------|
| stdlib `audioop` | ✓ (deprecated) | **✗ removed** | 0 KB (stdlib) | ✓ | ✓ | Works on 3.12 only. PEP 594 removed it from 3.13. |
| `audioop-lts` (PyPI) | **✗ "Python 3.13 or greater" required** [VERIFIED: PyPI] | ✓ drop-in replacement | 24-104 KB wheel | ✓ (verbatim API) | ✓ (verbatim API) | The drop-in path. Requires 3.13. |
| `numpy` | ✓ | ✓ | ~17 MB wheel for `numpy>=1.26` ARM64 | ✗ (manual lookup table needed) | ✗ (manual sinc/polyphase needed) | Heavy. Adds cold-start overhead. Not the right tool. |
| Pure-Python μ-law lookup | ✓ | ✓ | 0 KB | manual implementation | manual implementation | Slowest at 8kHz × 20ms = 160 samples/frame; might still meet real-time but is unnecessary work given `audioop-lts` exists. |

**Verified via [PyPI audioop-lts](https://pypi.org/project/audioop-lts/) — retrieved 2026-05-07:** "This module only functions at Python versions of 3.13 or greater due to being removed in this version." Latest version 0.2.2 published 2025-08-05. Wheel sizes 24.2-103.9 KB.

**Verified via [Python 3.12 docs](https://docs.python.org/3.12/library/audioop.html) — retrieved 2026-05-07:** `audioop.lin2ulaw(fragment, width)`, `audioop.ulaw2lin(fragment, width)`, `audioop.ratecv(fragment, width, nchannels, inrate, outrate, state[, weightA[, weightB]])` — exact signatures we need.

**Verified via [AWS Lambda runtimes table](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) — retrieved 2026-05-07:** Both `python3.12` (deprecation 2028-10-31) and `python3.13` (deprecation 2029-06-30) are supported managed runtimes on Amazon Linux 2023. Python 3.13 was released on Lambda 2024-11-14.

**Recommendation: Python 3.13 + `audioop-lts==0.2.2`.** Why:
- Lambda Python 3.12 stdlib `audioop` works today but is deprecated and gone in 3.13. Choosing 3.12 ties Phase 6 to a runtime that loses stdlib audio support. The migration path from "3.12 + stdlib" to "3.13 + audioop-lts" is then a future v3 chore.
- `audioop-lts` is verbatim API-compatible (`from audioop import lin2ulaw, ulaw2lin, ratecv` works identically). The migration cost from "currently 3.12 + stdlib" to "Phase 6 ships 3.13 + audioop-lts" is essentially zero — we never wrote the v1 code on stdlib audioop. Phase 6 is greenfield.
- Wheel size 24-104 KB easily fits Lambda's 250 MB unzipped layer cap.
- Cold-start impact: tiny (single C extension; `audioop-lts` is a thin shim around Python's removed C source).
- The widget_presigner Lambda is `python3.12` (matches existing Hera convention). Phase 6 deviates by using `python3.13` for the bridge — this is acceptable per CONTEXT D-58 ("planner discretion grounded in latest AWS docs as of NOW").

**Code shape (TWIL-01 implementation reference):**

```python
"""Two-way audio resample: μ-law 8kHz <-> Int16 16kHz."""
import audioop  # On Python 3.13: comes from audioop-lts shim. On 3.12: stdlib.

# Inbound: Twilio sends μ-law 8kHz mono, base64-encoded.
# Convert to Int16 16kHz Sonic-ready bytes.
def twilio_to_sonic(b64_mulaw_8k: str) -> bytes:
    mulaw_8k = base64.b64decode(b64_mulaw_8k)
    pcm16_8k = audioop.ulaw2lin(mulaw_8k, 2)  # width=2 -> Int16 LE
    pcm16_16k, _ = audioop.ratecv(pcm16_8k, 2, 1, 8000, 16000, None)
    return pcm16_16k  # raw Int16 LE bytes ready for AgentCore /ws

# Outbound: Sonic emits Int16 16kHz; downsample to 8kHz then μ-law-encode + base64.
# Note: Pipecat default OUTPUT is 24kHz Int16 (per AGT-07 + RUNBOOK), but Sonic
# at the bedrock-agentcore /ws data-plane emits the agent's native rate. The
# bridge needs to confirm via probe what the Hera AgentCore Runtime actually
# emits. Phase 2 baseline says 24kHz output. Code below assumes 16kHz upstream
# and degrades gracefully — if it's actually 24kHz, the inrate parameter changes.
def sonic_to_twilio(pcm16_upstream: bytes, upstream_rate_hz: int = 16000) -> str:
    pcm16_8k, _ = audioop.ratecv(pcm16_upstream, 2, 1, upstream_rate_hz, 8000, None)
    mulaw_8k = audioop.lin2ulaw(pcm16_8k, 2)
    return base64.b64encode(mulaw_8k).decode("ascii")
```

> [ASSUMED] The exact Sonic output sample rate over `bedrock-agentcore /ws` is 16 kHz Int16 mono. Phase 2 RUNBOOK says Pipecat default OUT is 24 kHz Int16 (AGT-07), but at the AgentCore Runtime data-plane WSS the framing may differ. **The planner should add a Wave 1 task: probe the live Runtime, capture one outbound frame, log its sample rate. If 24 kHz, change `upstream_rate_hz` accordingly. This is a 2-minute live verification.** Without this verification, "no chipmunk effect" SC gate may fail.

> [ASSUMED] `audioop.ratecv` with `state=None` re-initialized per frame is acceptable for short audio fragments. For continuous streaming, the `state` value returned MUST be threaded into the next call to avoid filter discontinuities (clicks/pops at frame boundaries). The planner MUST surface this: per-call ratecv state needs to live somewhere (a Lambda-global dict keyed by `streamSid`, OR DynamoDB if cross-invocation persistence is needed — see Q1). For Option γ-style per-frame fresh sessions, ratecv state is also fresh per frame. This is yet another reason Option γ degrades audio quality, not just latency.

**Sources:**
- [audioop-lts on PyPI](https://pypi.org/project/audioop-lts/) — retrieved 2026-05-07; v0.2.2 published 2025-08-05; Python ≥3.13 required
- [Python 3.12 audioop docs](https://docs.python.org/3.12/library/audioop.html) — retrieved 2026-05-07
- [AWS Lambda runtimes table](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) — retrieved 2026-05-07
- [PEP 594 - Removing dead batteries from the standard library](https://peps.python.org/pep-0594/#audioop)

---

### Q3 — API Gateway WebSocket route layout for Twilio Media Streams

**Investigation result [VERIFIED: AWS docs apigateway-websocket-api-overview.html — retrieved 2026-05-07]:**

API Gateway WebSocket has three predefined routes: `$connect`, `$disconnect`, `$default`. Custom routes are matched via the `routeSelectionExpression` defined at the API level. For Twilio's JSON envelope `{"event":"media", ...}`, the natural expression is `${request.body.event}`, which would let us route `start` / `media` / `stop` / `mark` / `dtmf` / `connected` to distinct integrations.

**Recommendation: Use `$connect` + `$disconnect` + `$default` ONLY.** Reasons:
- All Twilio events are processed by a single Lambda anyway (one bridge handler). Routing them to separate integrations would just split one function into 6, increasing Terraform surface area and IAM bookkeeping with no architectural benefit.
- The `$default` Lambda receives the raw JSON envelope; switching on `event["event"]` inside the handler is one Python `if/elif/else` (or dict dispatch) which is cleaner than 6 separate Lambda functions.
- Forward compat: any new Twilio event type (e.g., `dtmf` was added bidirectional-only later) lands on `$default` automatically. No infra change needed.
- Twilio sends the `connected` event first, then `start`, then many `media` frames, then `stop` on hang-up. Single ordered switch in handler is the simplest correct implementation.

**Critical implementation note:** API Gateway WebSocket **does not support binary frames** — it returns close code 1003 [VERIFIED: AWS docs]. Twilio Media Streams uses TEXT frames with base64-encoded audio in JSON, so we are safe. But: **Lambda integration responses to APIGW must also be JSON text strings**. When sending audio back to Twilio via `@connections POST` (Lambda → APIGW → Twilio), the body is JSON `{"event":"media","streamSid":"...","media":{"payload":"<base64>"}}` — text, not binary. Twilio's spec confirms this is what they expect [VERIFIED: Twilio docs].

**Authentication on APIGW WS handshake:** APIGW WebSocket itself does not authenticate the incoming Twilio handshake — Auth is configured per-API as `authorizationType=NONE` (analogous to widget_presigner Function URL auth=NONE). The bridge handles authentication via X-Twilio-Signature HMAC inside the `$connect` Lambda integration. See Q5 below.

**Sources:**
- [AWS API Gateway WebSocket overview](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-websocket-api-overview.html) — retrieved 2026-05-07
- [AWS API Gateway WebSocket quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-execution-service-websocket-limits-table.html) — retrieved 2026-05-07

---

### Q4 — AgentCore data-plane WSS contract

**Verified via [AWS docs runtime-get-started-websocket.html — retrieved 2026-05-07]:**

| Element | Value | Source |
|---------|-------|--------|
| WSS endpoint host | `bedrock-agentcore.<region>.amazonaws.com` | Verbatim quote: "wss://bedrock-agentcore.<region>.amazonaws.com/runtimes/<agentRuntimeArn>/ws" |
| WSS endpoint path | `/runtimes/<URL-ENCODED-ARN>/ws` (NOT `/invocations`) | Same source |
| Required query | `?qualifier=DEFAULT` (the Phase 3 widget pattern) | widget_presigner/src/handler.py |
| SigV4 service name | `bedrock-agentcore` | widget_presigner/src/handler.py + AWS docs |
| IAM action | `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream` | Verbatim quote: "Make sure that you have bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream permissions" |
| Auth methods | SigV4 headers (server-side) OR SigV4 presigned URL OR OAuth bearer token | AWS docs |
| Session ID header | `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` (also passable as `?session_id=...` query param) | AWS docs |
| Frame size limit | 32 KB | AWS docs - same as APIGW WS |
| Idle timeout | "session's idle timeout reset on every message" (default 15min `IdleRuntimeSessionTimeout`) | AWS docs |

**Server-side SigV4 connection — exact mechanics:**

The Phase 3 widget_presigner uses **SigV4 query-signed URL** (presigned). For server-side use (Phase 6 bridge), AWS docs show **SigV4 headers** is the cleaner path:

```python
# From AWS docs verbatim (Python bedrock-agentcore SDK):
from bedrock_agentcore.runtime import AgentCoreRuntimeClient
client = AgentCoreRuntimeClient(region="ap-northeast-1")
ws_url, headers = client.generate_ws_connection(
    runtime_arn=os.environ["AGENTCORE_RUNTIME_ARN"],
    session_id=twilio_call_sid,  # use Twilio's CallSid as session id
)
async with websockets.connect(ws_url, additional_headers=headers) as ws:
    ...
```

**[ASSUMED] The `bedrock-agentcore` PyPI package may or may not be available as a Lambda layer / direct pip install with a small footprint.** If it's heavy, fall back to the same `botocore.auth.SigV4QueryAuth` pattern Phase 3 widget_presigner already uses (server-side instead of presigned-URL) — botocore is part of the Lambda Python runtime built-in (no package needed). The widget_presigner mints `https://bedrock-agentcore...` and swaps to `wss://`; Phase 6 bridge does the same swap, then opens a `websockets.connect()` to that URL. Pattern is verified in Phase 3 production code.

**[ASSUMED] The `websockets` PyPI package needs to be in the Lambda deployment package.** It's pure Python, ~80 KB. Can be added to the bridge handler's `src/` requirements via `pip install -t src/ websockets audioop-lts` at archive time. Or via Lambda layer if multiple functions share. Single function = inline pip install in `archive_file`.

**Sources:**
- [AWS Bedrock AgentCore - Get started with bidirectional streaming](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-get-started-websocket.html) — retrieved 2026-05-07
- [AWS Bedrock AgentCore - Bi-directional streaming announcement blog](https://aws.amazon.com/blogs/machine-learning/bi-directional-streaming-for-real-time-agent-interactions-now-available-in-amazon-bedrock-agentcore-runtime/) — retrieved 2026-05-07; published 2025-12-18
- `infra/modules/widget_presigner/src/handler.py` (existing Hera SigV4 pattern reference)

---

### Q5 — Twilio Media Streams envelope shape

**Verified via [Twilio Media Streams WebSocket Messages](https://www.twilio.com/docs/voice/media-streams/websocket-messages) — retrieved 2026-05-07:**

#### Inbound (Twilio → Lambda)

| Event | Frequency | Envelope |
|-------|-----------|----------|
| `connected` | Once at WS open | `{"event":"connected","protocol":"Call","version":"1.0.0"}` |
| `start` | Once after connected | `{"event":"start","sequenceNumber":"1","start":{"accountSid":"AC...","streamSid":"MZ...","callSid":"CA...","tracks":["inbound"],"mediaFormat":{"encoding":"audio/x-mulaw","sampleRate":8000,"channels":1},"customParameters":{}},"streamSid":"MZ..."}` |
| `media` | ~50/sec (every 20ms) | `{"event":"media","sequenceNumber":"2","media":{"track":"inbound","chunk":"1","timestamp":"5","payload":"<base64-mulaw-8k>"},"streamSid":"MZ..."}` |
| `dtmf` | Bidirectional only, on key press | `{"event":"dtmf","streamSid":"MZ...","sequenceNumber":"5","dtmf":{"track":"inbound_track","digit":"1"}}` |
| `mark` | Bidirectional only, when our `mark` echoes back | `{"event":"mark","sequenceNumber":"4","streamSid":"MZ...","mark":{"name":"custom-label"}}` |
| `stop` | Once on hang-up | `{"event":"stop","sequenceNumber":"5","stop":{"accountSid":"AC...","callSid":"CA..."},"streamSid":"MZ..."}` |

#### Outbound (Lambda → Twilio, bidirectional only — i.e., when TwiML uses `<Connect><Stream>`)

| Event | Purpose | Envelope |
|-------|---------|----------|
| `media` | Send audio TO the call | `{"event":"media","streamSid":"MZ...","media":{"payload":"<base64-mulaw-8k>"}}` |
| `mark` | Insert a marker; Twilio echoes back when playback completes | `{"event":"mark","streamSid":"MZ...","mark":{"name":"custom-label"}}` |
| `clear` | Interrupt buffered audio (barge-in) | `{"event":"clear","streamSid":"MZ..."}` |

**Critical implementation rules** [VERIFIED: Twilio docs]:
1. Outbound media payload MUST NOT contain audio file type header bytes (raw μ-law samples only).
2. Audio MUST be μ-law/8000 mono, base64-encoded.
3. Sequence numbers begin at 1 and monotonically increment for inbound (Twilio→Lambda); outbound has no sequence number.
4. The `streamSid` is the routing key for outbound — it's how Twilio knows which call to play the audio on.
5. **`<Connect><Stream>` (NOT `<Start><Stream>`) is required for bidirectional.** TwiML uses `<Connect>` to block subsequent TwiML and hold the connection open; `<Start>` is unidirectional (audio captured, can't be sent back).

**Sources:**
- [Twilio Media Streams - WebSocket Messages](https://www.twilio.com/docs/voice/media-streams/websocket-messages) — retrieved 2026-05-07
- [Twilio TwiML Voice <Stream>](https://www.twilio.com/docs/voice/twiml/stream) — retrieved 2026-05-07
- [Twilio Bidirectional Streaming changelog](https://www.twilio.com/en-us/changelog/bi-directional-streaming-support-with-media-streams) — retrieved 2026-05-07

---

### Q6 — X-Twilio-Signature HMAC validation

**Verified via [Twilio Webhooks Security](https://www.twilio.com/docs/usage/webhooks/webhooks-security) — retrieved 2026-05-07:**

**Algorithm:** HMAC-SHA1 of `URL + sorted POST params concatenated as key1value1key2value2...`, with the AuthToken as the HMAC key, base64-encoded, compared against the `X-Twilio-Signature` HTTP header (lowercased on WS handshakes).

**Where validation runs for WebSockets:** Once at the WebSocket upgrade HTTP request (which API Gateway forwards to the `$connect` Lambda integration). NOT per WS message after upgrade. Twilio docs explicitly note this point.

**Critical implementation gotcha** (verbatim from Twilio docs):
> "if you are having trouble verifying a WebSocket handshake request (e.g., for Programmable Voice Media Streams), try appending a trailing `/` character to the URL that you pass to the signature validation method."

The header name is **all lowercase** `x-twilio-signature` on WebSocket handshakes (per Twilio docs); HTTP/1.1 headers are case-insensitive but Lambda event objects sometimes lowercase keys, so check both.

**Twilio strongly recommends using their SDK (`twilio.request_validator.RequestValidator`) rather than hand-rolling HMAC.** The Python SDK is `twilio` on PyPI (~1.4 MB unpacked, including `twilio.rest`, `twilio.request_validator`, etc.). Smaller subset: just `from twilio.request_validator import RequestValidator` — but pip installs the whole package.

**Recommended: Use the official Twilio SDK in the bridge Lambda.**

```python
# Verbatim from Twilio Python SDK pattern:
from twilio.request_validator import RequestValidator
validator = RequestValidator(os.environ["TWILIO_AUTH_TOKEN"])
url = "https://" + event["headers"]["host"] + event["requestContext"]["routeKey"]
# For Media Streams WSS handshake, append trailing slash if validation fails
# (Twilio docs explicit guidance):
if not validator.validate(url, params={}, signature=event["headers"]["x-twilio-signature"]):
    if not validator.validate(url + "/", params={}, signature=event["headers"]["x-twilio-signature"]):
        return {"statusCode": 403}
```

**Auth token storage:** Lambda env var `TWILIO_AUTH_TOKEN`. Operator pastes via Terraform variable (e.g., `TF_VAR_twilio_auth_token=...`); Terraform sets the env var on the Lambda. **Do NOT commit terraform.tfvars** with this value. The `widget_presigner/variables.tf` pattern (no default for sensitive variable) is the right shape.

**Lambda package size:** Adding `twilio` SDK adds ~1.4 MB. Plus `audioop-lts` ~100 KB. Plus `websockets` ~80 KB. Total ~1.6 MB unpacked, way under Lambda's 250 MB unzipped limit.

**Sources:**
- [Twilio Webhooks Security](https://www.twilio.com/docs/usage/webhooks/webhooks-security) — retrieved 2026-05-07
- [Validating Webhook Signatures with Python & Flask](https://www.twilio.com/en-us/blog/validating-webhook-signatures-python-flask) — retrieved 2026-05-07

---

### Q7 — Cost & size validation

**[VERIFIED — retrieved 2026-05-07]:**

| Item | 2026-05-07 verified value | Source |
|------|---------------------------|--------|
| Twilio US local number monthly hold | **~$1.15/mo** (NOT exactly $1) | [Twilio Programmable Voice US pricing](https://www.twilio.com/en-us/voice/pricing/us) |
| Twilio US inbound local minutes | **~$0.0085/min** for local; **~$0.013/min** quoted from CONTEXT D-65 (likely toll-free or older rate) | Same source |
| Twilio US toll-free monthly | ~$2.15/mo | Same source |
| Twilio US toll-free inbound minutes | ~$0.022/min | Same source |
| Lambda Python 3.13 unzipped layer cap | 250 MB | [AWS Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) |
| Lambda Python 3.13 deprecation date | 2029-06-30 | Same source |
| API Gateway WebSocket message price | **$1.00 per million messages** (first 1B; 32 KB increments) | [AWS API Gateway pricing](https://aws.amazon.com/api-gateway/pricing/) |
| API Gateway WebSocket connection minutes | **$0.25 per million connection-minutes** | Same source |
| API Gateway WebSocket free tier | 1M messages + 750K connection-minutes/month for 12 months | Same source |
| AgentCore InvokeAgentRuntimeWithWebSocketStream additional charge | Falls under standard Bedrock streaming pricing for the underlying model (Nova 2 Sonic). No separate AgentCore data-plane charge published as of 2026-05-07. | [AWS docs](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-get-started-websocket.html) silent on extra charge → defaults to "no extra" |

**Demo cost estimate** for one 5-minute phone call:
- Twilio US local: $1.15/mo hold + 5 min × $0.0085 = $0.0425. **Per-call: ~$0.04.**
- API Gateway WS: 5 min × 50 frames/s × 60 = 15,000 inbound + 15,000 outbound = 30,000 messages. At $1/M, that's **$0.030**. Plus 5 connection-minutes × $0.25/M = ~$0. Free tier covers easily.
- Lambda invocations: 30,000 invocations × ~50ms each at 256 MB = 0.5 GB-seconds × 30k = 15,000 GB-s/call. AT $0.0000166667/GB-s = **$0.25/call**. Plus 30k requests × $0.20/M = $0.006.
- AgentCore + Bedrock Sonic: per Phase 4 D-29, billing alarm fires at $5/day. A 5-minute Sonic call is roughly the same cost as 5min on the v1 web widget, ~$0.10-0.20 per call.

**Per-call total: ~$0.50.** A 90-cohort workshop with everyone calling once = ~$45. **One leaked open call running 24h would cost $1.15/mo (number) + 1440min × $0.0085 = $13.39 + ~$30 in Lambda + $50 in Bedrock = ~$95 for a single 24h leak.** Demo budget acceptable per OBS-04 (concurrency cap=2 = max 2 concurrent leaks).

> [ASSUMED] CONTEXT D-65 quotes Twilio inbound at $0.013/min — this matches Twilio's older published rate; current US local is $0.0085/min. Update RUNBOOK to reflect current rate. Toll-free is $0.022/min if instructor chooses toll-free for the demo number (recommended for international workshop callers, but ~3x cost).

**Sources:**
- [Twilio Programmable Voice US Pricing](https://www.twilio.com/en-us/voice/pricing/us) — retrieved 2026-05-07
- [AWS API Gateway pricing](https://aws.amazon.com/api-gateway/pricing/) — retrieved 2026-05-07
- [AWS Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) — retrieved 2026-05-07

---

## Project Constraints (from CLAUDE.md / AGENTS.md)

The Phase 6 plans MUST honor:

1. **`uv` only for Python.** Bridge Lambda's `requirements.txt` (or pyproject.toml) installs via `uv add` / `uv pip compile`. Never `pip install` directly.
2. **Latest APIs as of NOW.** Python 3.13 Lambda runtime + audioop-lts. Twilio Python SDK latest. Terraform `~> 6.27` (already pinned). botocore from Lambda built-in.
3. **No emojis** anywhere in code, logs, RUNBOOK, comments.
4. **Concise docstrings; sparing comments outside docstrings.**
5. **No defensive try/except around AWS calls.** Only `WebSocketDisconnect`-style normal-disconnect-path try/except is acceptable. Per AGENTS.md, root-cause-then-fix; don't program defensively.
6. **Demo budget rule.** Prefer skip / defer / minimal-deploy. No new long-running compute (current D-56 honored despite Q1 finding — see options for planner).
7. **No emojis in print/logging.** Especially relevant in cleanup-verify-twilio.sh which has lots of OK/FAIL strings.
8. **English only for chatbot.** Already true; bridge does not modify agent persona.
9. **Hugo theme is hugo-theme-learn** (deprecated upstream). Phase 6 is system-only — no Hugo content edits. Workshop chapter is Phase 7.

---

## Standard Stack

### Core (REQUIRED in bridge Lambda)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Python | **3.13** Lambda managed runtime | Bridge handler runtime | `audioop-lts` requires 3.13; deprecation horizon 2029-06-30 [VERIFIED: AWS Lambda runtimes 2026-05-07] |
| `audioop-lts` | **0.2.2** (latest as of 2026-05-07) | μ-law encode/decode + ratecv resample | Verbatim drop-in for stdlib `audioop` removed from Python 3.13 [VERIFIED: PyPI 2026-05-07] |
| `websockets` | **15.x** (latest as of 2026-05) | Open the upstream AgentCore WSS from Lambda | Standard async WS lib; 80 KB; pure Python [VERIFIED: PyPI] |
| `twilio` | **9.x** (latest as of 2026-05) | `RequestValidator` for X-Twilio-Signature HMAC validation | Twilio's official Python SDK; documented best practice [VERIFIED: Twilio docs 2026-05-07] |
| `botocore` | Built-in via Lambda Python 3.13 runtime | SigV4 signing of upstream WSS connection (server-side) | Pattern reused from `widget_presigner/src/handler.py` |
| `bedrock-agentcore` (PyPI) | latest | OPTIONAL helper SDK for `generate_ws_connection()` | If too heavy, fall back to direct `botocore.auth.SigV4QueryAuth` pattern. Both work. |

### Supporting (REQUIRED in bridge Terraform module)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `hashicorp/aws` | `~> 6.27` | Existing Hera pin | Default; no change |
| `hashicorp/archive` | `~> 2.4` | Zip the Lambda handler dir | Already used in widget_presigner |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Python 3.13 + audioop-lts | Python 3.12 + stdlib audioop (deprecated) | -1 PyPI dep but ties Phase 6 to a deprecated stdlib; migration path required by 2028. Pick 3.13 for forward compat. |
| `websockets` PyPI | Lambda Python 3.13 doesn't ship it built-in; `aiohttp` is heavier (~3 MB) | `websockets` is the canonical async WS client; pure Python; small. |
| `twilio` SDK | Hand-roll HMAC-SHA1 of URL + sorted POST params + base64 | Twilio docs explicitly warn against hand-rolling: "We strongly recommend using the provided signature validation library." +1.4 MB is fine on Lambda. |
| `audioop-lts` | `numpy` for resample + custom mulaw lookup table | numpy is ~17 MB (heavy cold-start), and we'd write μ-law manually. Net negative. |
| Direct SigV4QueryAuth (Phase 3 pattern) | `bedrock-agentcore.runtime.AgentCoreRuntimeClient` SDK helper | Both produce a signed WSS URL. Phase 3 pattern is proven; SDK helper is one-line cleaner. Either works. Planner picks. |

**Installation (bridge Lambda):**

```bash
# In infra/modules/twilio_bridge/src/, ship a requirements.txt or pyproject.toml.
# At Terraform archive time, install deps into src/ before zipping:
uv pip install --target . audioop-lts==0.2.2 websockets==15.x twilio==9.x
# (uv works in CI; alternative: pip install --target . if uv unavailable.)
```

**Version verification — performed 2026-05-07:**
- `audioop-lts` 0.2.2 (published 2025-08-05) [VERIFIED: PyPI]
- `websockets` 15.x latest [VERIFIED: PyPI search]
- `twilio` 9.x latest [VERIFIED: PyPI search]
- AWS Lambda Python 3.13 runtime supported, deprecation 2029-06-30 [VERIFIED: AWS docs]

---

## Architecture Patterns

### System Architecture Diagram

```
PSTN dial  ─►  Twilio Voice  ──►  TwiML Bin  ──►  <Connect><Stream url="wss://APIGW-WS-URL/prod">
   (D-60)        (D-60)             (D-61)
                                                 ▼
                                    Twilio Media Streams WebSocket
                                                 │ (text frames; JSON envelopes;
                                                 │  μ-law 8kHz audio base64 in payload)
                                                 ▼
                                    AWS API Gateway WebSocket API
                                    (`hera-twilio-ws` — D-12 fixed name)
                                    Routes:  $connect / $disconnect / $default
                                    AuthorizationType=NONE (HMAC validated in Lambda)
                                                 │
                                                 ▼
                                    Bridge Lambda  `hera-twilio-bridge-prod`
                                    (Python 3.13, 256 MB, reserved-concurrency=5)
                                    ┌────────────┬────────────┬──────────────┐
                                    │ $connect:  │ $default:  │ $disconnect: │
                                    │  - X-Twilio│  - dispatch│  - log close │
                                    │    -Signature│  on event:│  - cleanup  │
                                    │    HMAC ✓ │  start/    │              │
                                    │  - 200 / 403│  media/   │              │
                                    │            │  stop/    │              │
                                    │            │  mark/dtmf│              │
                                    └─┬──────────┴───┬────────┴──────────────┘
                                      │              │
                                      │              │ media.payload base64-decode
                                      │              │ → audioop.ulaw2lin (μ-law→Int16 8kHz)
                                      │              │ → audioop.ratecv (8kHz→16kHz, threaded state)
                                      │              │
                                      │              ▼
                                      │  ┌──────────────────────────────────────────┐
                                      │  │ Upstream AgentCore Runtime WSS           │
                                      │  │ wss://bedrock-agentcore.ap-northeast-1   │
                                      │  │   .amazonaws.com/runtimes/<URL-ENC-ARN>  │
                                      │  │   /ws?qualifier=DEFAULT                  │
                                      │  │ SigV4-signed (service=bedrock-agentcore) │
                                      │  │ IAM: InvokeAgentRuntimeWithWebSocketStream│
                                      │  │      on EXACT runtime ARN                │
                                      │  │ ⚠ Q1 RISK: Lambda 29s timeout vs        │
                                      │  │   long-lived call. See Q1 above.        │
                                      │  └──────────────────────────────────────────┘
                                      │              │
                                      │              │ Sonic Int16 16kHz output
                                      │              │ → audioop.ratecv (16k→8k)
                                      │              │ → audioop.lin2ulaw
                                      │              │ → base64
                                      │              │ → JSON envelope {"event":"media",...}
                                      │              ▼
                                      │  POST @connections/{connectionId} via APIGW Mgmt API
                                      │  (text JSON to Twilio over the original WSS)
                                      ▼
                                    CloudWatch Logs `/aws/lambda/hera-twilio-bridge-prod`
                                    + `/aws/apigateway/hera-twilio-ws` (access logs)
```

### Recommended Project Structure

```
infra/modules/twilio_bridge/
├── versions.tf       # AWS ~> 6.27, archive ~> 2.4
├── variables.tf      # name_prefix, env, region, account_id, agentcore_runtime_arn,
│                     # twilio_auth_token (sensitive), reserved_concurrent_executions
├── main.tf           # IAM role + policy + log group + Lambda + APIGW WS API
│                     # + 3 routes ($connect / $disconnect / $default) + 1 stage (prod)
│                     # + 1 deployment + Lambda permission for APIGW invoke
├── outputs.tf        # twilio_bridge_wss_url, function_name, function_arn,
│                     # apigw_id, role_arn
└── src/
    ├── handler.py    # The bridge handler (per-WS-message Lambda invocation)
    ├── resampler.py  # twilio_to_sonic + sonic_to_twilio + ratecv state mgmt
    ├── upstream.py   # SigV4-signed AgentCore WSS open + send + recv
    └── requirements.txt   # audioop-lts==0.2.2, websockets, twilio
```

### Pattern 1: Twilio Media Streams Frame Handling

**What:** A Lambda invocation per Twilio JSON message. Each invocation: parse envelope, dispatch on `event` field, perform the appropriate action (validate, decode-and-forward, log-and-close).

**When to use:** Always — D-56 locks this pattern.

**Code shape (verified shape; pseudo-code joining the verified parts):**

```python
"""Bridge Lambda handler: Twilio Media Streams ↔ AgentCore Runtime."""
import base64
import json
import os

import audioop  # On Python 3.13 via audioop-lts
import boto3

# Env vars set by Terraform (D-66 + D-67)
AGENTCORE_RUNTIME_ARN = os.environ["AGENTCORE_RUNTIME_ARN"]
TWILIO_AUTH_TOKEN = os.environ["TWILIO_AUTH_TOKEN"]  # sensitive; from TF var
REGION = os.environ["AWS_REGION"]

apigw_mgmt = boto3.client(
    "apigatewaymanagementapi",
    endpoint_url=os.environ["APIGW_MANAGEMENT_ENDPOINT"],  # set per-stage by TF
)

def lambda_handler(event, context):
    route_key = event["requestContext"]["routeKey"]
    connection_id = event["requestContext"]["connectionId"]

    if route_key == "$connect":
        return _handle_connect(event)
    if route_key == "$disconnect":
        return _handle_disconnect(event, connection_id)
    if route_key == "$default":
        return _handle_message(event, connection_id)
    return {"statusCode": 404}


def _handle_connect(event):
    """Validate X-Twilio-Signature HMAC; reject if invalid (D-67)."""
    from twilio.request_validator import RequestValidator

    validator = RequestValidator(TWILIO_AUTH_TOKEN)
    headers = {k.lower(): v for k, v in event["headers"].items()}
    sig = headers.get("x-twilio-signature", "")
    # WSS handshake URL reconstruction; Twilio sometimes wants a trailing slash:
    base_url = f"https://{headers['host']}{event['requestContext']['routeKey']}"
    for url_to_try in (base_url, base_url + "/"):
        if validator.validate(url_to_try, params={}, signature=sig):
            return {"statusCode": 200}
    return {"statusCode": 403}


def _handle_message(event, connection_id):
    """Dispatch on Twilio event type."""
    body = json.loads(event["body"])
    twilio_event = body.get("event")

    if twilio_event == "connected":
        return {"statusCode": 200}
    if twilio_event == "start":
        # Capture streamSid + callSid for later upstream open + outbound routing.
        # See Q1 RISK ABOVE: where does this state live? Decision pending.
        return {"statusCode": 200}
    if twilio_event == "media":
        # See Q1 RISK ABOVE. The "open upstream + send + receive" path is
        # NOT cleanly implementable in a stateless per-frame Lambda without
        # accepting per-frame fresh upstream session penalty. Surface to
        # /gsd-discuss-phase Phase-6-D58-followup before implementation.
        b64 = body["media"]["payload"]
        pcm16_16k = _twilio_to_sonic(b64)
        # ⚠ Open upstream WSS, send pcm16_16k, recv response, close. See Q1.
        # response_pcm16 = upstream.send_and_recv(pcm16_16k)
        # response_b64 = _sonic_to_twilio(response_pcm16)
        # _send_to_twilio(connection_id, body["streamSid"], response_b64)
        return {"statusCode": 200}
    if twilio_event == "stop":
        return {"statusCode": 200}
    if twilio_event in ("mark", "dtmf"):
        return {"statusCode": 200}  # ignore for v2 minimum
    return {"statusCode": 200}


def _twilio_to_sonic(b64_mulaw_8k: str) -> bytes:
    mulaw_8k = base64.b64decode(b64_mulaw_8k)
    pcm16_8k = audioop.ulaw2lin(mulaw_8k, 2)
    pcm16_16k, _state = audioop.ratecv(pcm16_8k, 2, 1, 8000, 16000, None)
    return pcm16_16k


def _sonic_to_twilio(pcm16_16k: bytes) -> str:
    pcm16_8k, _state = audioop.ratecv(pcm16_16k, 2, 1, 16000, 8000, None)
    mulaw_8k = audioop.lin2ulaw(pcm16_8k, 2)
    return base64.b64encode(mulaw_8k).decode("ascii")


def _send_to_twilio(connection_id: str, stream_sid: str, b64_audio: str):
    payload = json.dumps({
        "event": "media",
        "streamSid": stream_sid,
        "media": {"payload": b64_audio},
    })
    apigw_mgmt.post_to_connection(ConnectionId=connection_id, Data=payload.encode())
```

### Pattern 2: SigV4-signed Upstream AgentCore WSS (Server-Side)

**What:** Re-use the widget_presigner SigV4 mechanics, but server-side (open the WSS directly from Lambda, not mint a presigned URL for browser).

**When to use:** Always when the bridge needs to talk upstream — see Q1 risk discussion.

**Code shape:**

```python
"""upstream.py — server-side SigV4-signed AgentCore Runtime WSS open."""
import os
from urllib.parse import quote

from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest
from botocore.session import Session

REGION = os.environ["AWS_REGION"]
RUNTIME_ARN = os.environ["AGENTCORE_RUNTIME_ARN"]
SERVICE = "bedrock-agentcore"
HOST = f"bedrock-agentcore.{REGION}.amazonaws.com"

ENCODED_ARN = quote(RUNTIME_ARN, safe="")
HTTPS_URL_BASE = f"https://{HOST}/runtimes/{ENCODED_ARN}/ws?qualifier=DEFAULT"

_session = Session()


def signed_wss_url(expires_seconds: int = 300) -> str:
    """SigV4-sign and return the wss:// URL. Same mechanics as widget_presigner."""
    creds = _session.get_credentials().get_frozen_credentials()
    request = AWSRequest(method="GET", url=HTTPS_URL_BASE)
    signer = SigV4QueryAuth(creds, SERVICE, REGION, expires=expires_seconds)
    signer.add_auth(request)
    return "wss://" + request.url[len("https://"):]
```

### Anti-Patterns to Avoid

- **DO NOT hand-roll X-Twilio-Signature HMAC.** Use Twilio's `RequestValidator`. Twilio explicitly warns against hand-rolling. Phase 6's signature path is operationally critical; subtle bugs (forgetting trailing slash, wrong encoding for sorted POST params, base64 vs hex) silently lock the bridge to anonymous public abuse.
- **DO NOT extend the v1 widget_presigner Lambda with bridge routes.** D-57 forbids this; v2 deploy failure must not break v1 widget. New module from scratch.
- **DO NOT use `random_id` suffixes.** D-12 fixed names. `hera-twilio-bridge-prod`, `hera-twilio-ws`.
- **DO NOT call `cdk deploy` in Phase 6.** v1 AgentCore Runtime + agent container UNCHANGED. D-64.
- **DO NOT add Twilio Terraform provider.** D-60 — provisioning is operator-paste-style.
- **DO NOT serve TwiML from a Lambda Function URL.** D-61 — TwiML Bin only.
- **DO NOT hold an upstream WSS in `lambda /tmp` or Lambda-global state.** Q1 — Lambda execution environments are not connection-stable.
- **DO NOT skip ratecv state threading for continuous audio streams.** Per-frame fresh ratecv state introduces filter discontinuities — clicks/pops at frame boundaries. If state must be threaded across stateless invocations, it lives in DynamoDB (and that re-opens Q1's structural issues). Practical caveat: Sonic at 8 frames/100ms × 20ms each is brief enough that aliasing artifacts may be inaudible without state — needs ear-test.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| X-Twilio-Signature HMAC validation | Custom HMAC-SHA1 + URL canonicalization | `twilio.request_validator.RequestValidator` | Twilio docs explicitly mandate using SDK; subtle URL/param-ordering bugs cause silent acceptance of unsigned requests. |
| AWS SigV4 signing | Manual `Authorization: AWS4-HMAC-SHA256 ...` header build | `botocore.auth.SigV4QueryAuth` (already used by widget_presigner) | botocore is built-in; signing canonical form is fiddly; widget_presigner is the proven Hera pattern. |
| μ-law encode/decode | Custom 256-entry lookup table | `audioop-lts` (Python 3.13) — `lin2ulaw` / `ulaw2lin` | C-extension speed; verbatim drop-in for stdlib `audioop`; ITU-T G.711 conformance handled. |
| Audio resample 8kHz→16kHz | Custom polyphase / sinc / linear interp | `audioop-lts.ratecv` | C-extension; produces a `(newfragment, newstate)` tuple where `newstate` threads filter state across calls. |
| Twilio JSON envelope dispatch | Multi-route APIGW with route-selection-expression `${request.body.event}` | Single `$default` route + Python `if/elif` switch | Less Terraform surface; one Lambda; forward-compat for new event types. |
| AgentCore WSS handshake | Hand-built `Sec-WebSocket-Key` + `Sec-WebSocket-Version` headers | `websockets` PyPI package | Pure Python; ~80 KB; handles WS RFC 6455 conformance. |

---

## Common Pitfalls

### Pitfall 1: Twilio uses `<Connect><Stream>` not `<Start><Stream>` for bidirectional audio

**What goes wrong:** Operator uses `<Start><Stream>` in TwiML Bin. Twilio captures audio (inbound works) but rejects audio sent BACK from the Lambda (outbound silent). User hears: "Hello, this is Hera" never plays. Symptoms: bridge Lambda logs show successful `_send_to_twilio` calls but no audio plays on phone.

**Why it happens:** `<Start><Stream>` is unidirectional (capture-only); `<Connect><Stream>` is bidirectional. Both validate as TwiML XML.

**How to avoid:** RUNBOOK Phase 6 paste-block has the exact verbatim TwiML XML using `<Connect>` only, with a comment "DO NOT change to <Start>".

**Warning signs:** Inbound audio frames arrive in Lambda logs; outbound `apigw_mgmt.post_to_connection` succeeds but caller hears silence.

### Pitfall 2: X-Twilio-Signature URL canonicalization with vs without trailing slash

**What goes wrong:** Validation fails. All connect attempts return 403. No phone audio ever reaches the bridge.

**Why it happens:** Twilio's WS handshake URL signature canonicalization is a known surprise — the docs explicitly call this out. The exact URL Twilio used at signing time may differ from what API Gateway routes to Lambda by exactly one trailing `/` character.

**How to avoid:** The `_handle_connect` code shape above tries BOTH `base_url` and `base_url + "/"`. Validate with whichever passes. This is verbatim per Twilio docs guidance.

**Warning signs:** All `$connect` integrations return 403; CloudWatch shows "x-twilio-signature header present, validate() returned False" for every attempt.

### Pitfall 3: Lambda 29s timeout vs phone call duration mismatch (Q1 architectural risk)

**What goes wrong:** Phone call hangs after 29 seconds. User says "Hello?" → response → user says "Tell me about iPhone" → silence forever. Bridge Lambda log shows `Task timed out after 29.00 seconds`.

**Why it happens:** API Gateway WebSocket integration timeout is 29s hard limit. If a Lambda invocation tries to keep the upstream Bedrock WSS open across multiple Twilio media frames, it dies.

**How to avoid:** Per-frame stateless Lambda invocations only. EACH Twilio message triggers a separate Lambda invocation. The upstream WSS is opened-and-closed per invocation OR uses a different compute (App Runner — see Q1 Option β).

**Warning signs:** Cold-start latency visible (phone caller hears multi-second pause); CloudWatch shows `Duration > 5000ms` consistently; phone call drops after 29s.

### Pitfall 4: `ratecv` state discontinuity → audible clicks at frame boundaries

**What goes wrong:** Caller hears very faint clicks every 20ms when listening to the agent's response. May not be obvious in casual testing but degrades perceived quality.

**Why it happens:** `audioop.ratecv` keeps a small filter state in its second return value. When you call `ratecv(...state=None)` for every frame, the filter restarts each time, introducing edge artifacts.

**How to avoid:** Thread the `newstate` from frame N into frame N+1. In a stateless Lambda model this requires DynamoDB-backed state (or accepting the artifact). For Phase 6 demo, the artifact may be acceptable — needs ear-test.

**Warning signs:** Audio sounds "raspy" or "popcorn-like" especially during silence-to-speech transitions; spectral analysis shows ~50Hz comb modulation.

### Pitfall 5: Sonic 8-min stream cap interaction with phone calls

**What goes wrong:** Phone call > 8 minutes drops audio mid-sentence with no recovery.

**Why it happens:** Sonic's 8-minute stream cap is handled in the agent's Pipecat pipeline via `SessionContinuationParams(transition_threshold_seconds=360)` (AGT-05). This is per-AgentCore-WSS-session. If the bridge opens fresh sessions per frame (Q1 Option γ), the agent's continuation logic NEVER fires — every new session is sub-360s.

**How to avoid:** Per-call (NOT per-frame) upstream WSS. Same root issue as Q1 — needs a long-running compute path.

**Warning signs:** Phone call drops at exactly 7-8 minute mark.

### Pitfall 6: API Gateway WebSocket close code 1003 on binary frames

**What goes wrong:** APIGW WS returns close code 1003 ("binary unsupported") and disconnects.

**Why it happens:** APIGW WS supports text frames only. Binary frames disconnect.

**How to avoid:** Twilio Media Streams uses text + base64 (no binary). We never send binary upstream from the bridge to Twilio. Safe by construction.

**Warning signs:** Connection drops immediately after first message; close code 1003.

### Pitfall 7: AgentCore concurrency cap=2 starves phone calls during web demo

**What goes wrong:** Instructor demoing the web widget uses both AgentCore session slots. A learner calls the phone — bridge Lambda fails to open upstream WSS with throttling error. Phone caller hears "agent busy."

**Why it happens:** D-30 sets AgentCore concurrency cap=2 for cost control. Browser + phone share the same 2 slots.

**How to avoid:** RUNBOOK documents this interaction; demo sequence: end browser session BEFORE testing phone. v2.0 demo budget accepts this trade-off; v3 may bump cap to 5+.

**Warning signs:** Lambda errors `ThrottlingException: Too many concurrent runtimes`.

### Pitfall 8: Twilio number monthly hold accumulates if cleanup-verify-twilio.sh skipped

**What goes wrong:** Operator runs `terraform destroy` (drops AWS bridge) but forgets to release the Twilio number. $1.15/mo charge accrues silently.

**Why it happens:** D-60 — Twilio is operator-paste-style. terraform destroy doesn't touch Twilio.

**How to avoid:** D-62/D-63 cleanup-verify-twilio.sh asserts no incoming phone numbers + no TwiML Bins remain via Twilio REST API. Operator MUST paste TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN env vars before running. RUNBOOK Phase 6 cleanup section makes this the FIRST step (release Twilio first, THEN terraform destroy, THEN verify).

**Warning signs:** Twilio monthly invoice shows hold charge after AWS infra teardown.

---

## Runtime State Inventory

(This phase ADDS resources only — no rename/refactor of v1. State inventory is short.)

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None new — bridge Lambda is stateless. (Pre-existing: KB `BKXE19AH89` stays unchanged; Mem0 / DynamoDB not used.) | None |
| Live service config | NEW: Twilio Account (operator-created); Twilio incoming phone number; Twilio TwiML Bin. All operator-paste-style per D-60/D-61. | RUNBOOK Phase 6 paste-blocks. terraform destroy does NOT clean these — operator must release Twilio resources FIRST per D-63. |
| OS-registered state | None | None |
| Secrets/env vars | NEW: `TWILIO_AUTH_TOKEN` (Lambda env var, sensitive, populated from `TF_VAR_twilio_auth_token`). NOT committed to git. | terraform.tfvars must NOT contain this; use env-var override. |
| Build artifacts / installed packages | NEW: bridge Lambda zip artifact in `infra/modules/twilio_bridge/build/handler.zip` (gitignored, per widget_presigner pattern). | Per-build artifact, regenerated via `archive_file` on every terraform apply. |

---

## Concrete Code Shapes

### Bridge Handler Skeleton (Python 3.13)

See Pattern 1 above for the dispatch skeleton. Full 4-file split (handler.py / resampler.py / upstream.py / requirements.txt) is the planner's call. Recommend keeping all in `src/` for simplicity since the bridge is one logical concern.

### Terraform Module Skeleton

`infra/modules/twilio_bridge/versions.tf` (mirror widget_presigner verbatim):
```hcl
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.27" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
```

`infra/modules/twilio_bridge/variables.tf` (full set):
```hcl
variable "name_prefix" {
  default = "hera"
  type    = string
}
variable "env" {
  default = "prod"
  type    = string
}
variable "region" {
  type = string
}
variable "account_id" {
  type = string
}
variable "agentcore_runtime_arn" {
  description = "Live runtime ARN. D-66: IAM scopes EXACTLY to this — zero wildcards."
  type        = string
}
variable "twilio_auth_token" {
  description = "Twilio Auth Token for X-Twilio-Signature HMAC validation (D-67). Operator pastes via TF_VAR_twilio_auth_token; NEVER commit terraform.tfvars containing this."
  type        = string
  sensitive   = true
}
variable "reserved_concurrent_executions" {
  description = "Bridge Lambda concurrency cap. D-65: bounded by AgentCore upstream cap=2."
  type        = number
  default     = 5
}
```

`infra/modules/twilio_bridge/main.tf` skeleton (the planner fleshes out):
```hcl
locals {
  function_name  = "${var.name_prefix}-twilio-bridge-${var.env}"
  apigw_name     = "${var.name_prefix}-twilio-ws"
  log_group_name = "/aws/lambda/${local.function_name}"
}

# --- Lambda execution role ---
data "aws_iam_policy_document" "bridge_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals { type = "Service"; identifiers = ["lambda.amazonaws.com"] }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}
resource "aws_iam_role" "bridge" {
  name               = "${local.function_name}-exec"
  assume_role_policy = data.aws_iam_policy_document.bridge_trust.json
}

# --- Inline policy: zero wildcards (D-13/D-66) ---
data "aws_iam_policy_document" "bridge_inline" {
  statement {
    sid     = "InvokeAgentRuntimeWebSocket"
    effect  = "Allow"
    actions = ["bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream"]
    resources = [
      var.agentcore_runtime_arn,
      "${var.agentcore_runtime_arn}/*",
    ]
  }
  statement {
    sid       = "ManageWSConnections"
    effect    = "Allow"
    actions   = ["execute-api:ManageConnections"]
    resources = ["${aws_apigatewayv2_api.bridge.execution_arn}/*"]
  }
  statement {
    sid     = "OwnLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      aws_cloudwatch_log_group.bridge.arn,
      "${aws_cloudwatch_log_group.bridge.arn}:*",
    ]
  }
}
resource "aws_iam_role_policy" "bridge_inline" {
  name   = "${local.function_name}-inline"
  role   = aws_iam_role.bridge.id
  policy = data.aws_iam_policy_document.bridge_inline.json
}

# --- Log group ---
resource "aws_cloudwatch_log_group" "bridge" {
  name              = local.log_group_name
  retention_in_days = 30
}

# --- Package handler ---
data "archive_file" "bridge" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/handler.zip"
}

# --- Lambda function ---
resource "aws_lambda_function" "bridge" {
  function_name    = local.function_name
  role             = aws_iam_role.bridge.arn
  runtime          = "python3.13"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.bridge.output_path
  source_code_hash = data.archive_file.bridge.output_base64sha256
  timeout          = 29       # APIGW WS integration timeout cap
  memory_size      = 256
  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      AGENTCORE_RUNTIME_ARN       = var.agentcore_runtime_arn
      TWILIO_AUTH_TOKEN           = var.twilio_auth_token
      APIGW_MANAGEMENT_ENDPOINT   = "https://${aws_apigatewayv2_api.bridge.id}.execute-api.${var.region}.amazonaws.com/prod"
    }
  }
  depends_on = [aws_iam_role_policy.bridge_inline, aws_cloudwatch_log_group.bridge]
}

# --- API Gateway WebSocket API ---
resource "aws_apigatewayv2_api" "bridge" {
  name                       = local.apigw_name
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.event"  # but we use $default
}

# --- Integration: 1 Lambda for all 3 routes ---
resource "aws_apigatewayv2_integration" "bridge" {
  api_id                    = aws_apigatewayv2_api.bridge.id
  integration_type          = "AWS_PROXY"
  integration_uri           = aws_lambda_function.bridge.invoke_arn
  content_handling_strategy = "CONVERT_TO_TEXT"
}

# --- Routes: $connect / $disconnect / $default ---
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.bridge.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.bridge.id}"
}
resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.bridge.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.bridge.id}"
}
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.bridge.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.bridge.id}"
}

# --- Stage + deployment ---
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.bridge.id
  name        = "prod"
  auto_deploy = true
  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 100
  }
}

# --- APIGW invoke permission for Lambda ---
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bridge.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.bridge.execution_arn}/*/*"
}
```

`infra/modules/twilio_bridge/outputs.tf`:
```hcl
output "twilio_bridge_wss_url" {
  description = "WSS endpoint URL for the Twilio TwiML Bin <Stream url=\"...\"/>. RUNBOOK Phase 6 paste-block uses this."
  value       = "wss://${aws_apigatewayv2_api.bridge.id}.execute-api.${var.region}.amazonaws.com/prod"
}
output "function_name" {
  value = aws_lambda_function.bridge.function_name
}
output "function_arn" {
  value = aws_lambda_function.bridge.arn
}
output "apigw_id" {
  value = aws_apigatewayv2_api.bridge.id
}
output "log_group_name" {
  value = aws_cloudwatch_log_group.bridge.name
}
```

### `module "twilio_bridge"` block in `infra/envs/prod/main.tf`

Add after the existing `widget_presigner` and `observability` blocks:

```hcl
# Twilio Media Streams bridge (Phase 6 — TWIL-01..04). Operator pastes the
# Twilio Auth Token via `TF_VAR_twilio_auth_token=<token>`; never committed.
module "twilio_bridge" {
  source = "../../modules/twilio_bridge"

  region                = var.region
  account_id            = data.aws_caller_identity.current.account_id
  agentcore_runtime_arn = var.agentcore_runtime_arn
  twilio_auth_token     = var.twilio_auth_token
  # name_prefix, env, reserved_concurrent_executions use defaults
}
```

Add to `infra/envs/prod/variables.tf` (new variable):
```hcl
variable "twilio_auth_token" {
  description = "Twilio Auth Token (Phase 6). Pass via TF_VAR_twilio_auth_token. NEVER commit terraform.tfvars containing this."
  type        = string
  sensitive   = true
  default     = ""  # safe default for terraform plan without phase 6 setup
}
```

Add to `infra/envs/prod/outputs.tf`:
```hcl
output "twilio_bridge_wss_url" {
  description = "WSS endpoint for Twilio TwiML Bin <Stream url=\"...\"/>."
  value       = module.twilio_bridge.twilio_bridge_wss_url
}
```

### `bin/cleanup-verify-twilio.sh` Skeleton

```bash
#!/usr/bin/env bash
# bin/cleanup-verify-twilio.sh - Phase 6 Twilio bridge cleanup verification (D-62, D-63).
# Mirrors bin/cleanup-verify.sh pattern verbatim.
# Runs AFTER operator: (1) released Twilio number + deleted TwiML Bin,
# (2) terraform destroy in infra/envs/prod.
# Read-only — never destroys.
#
# Usage:
#   export TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#   export TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#   bash bin/cleanup-verify-twilio.sh
#
# Reads:
#   HERA_REGION (default ap-northeast-1)
#   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN (operator pastes)
# Effect: ~10 read-only API calls (AWS + Twilio); prints OK/FAIL per resource + final tally.

set -euo pipefail

# --- preflight: required tools ---
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq not found" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 2; }

# --- preflight: required env vars ---
: "${TWILIO_ACCOUNT_SID:?ERROR: paste TWILIO_ACCOUNT_SID before running}"
: "${TWILIO_AUTH_TOKEN:?ERROR: paste TWILIO_AUTH_TOKEN before running}"

REGION="${HERA_REGION:-ap-northeast-1}"
PASS_COUNT=0
FAIL_COUNT=0
GONE_REGEX='ResourceNotFound|NoSuchEntity|NotFound|does not exist|404'

echo "cleanup-verify-twilio against ${REGION} + Twilio account ${TWILIO_ACCOUNT_SID:0:8}..."
echo "----------------------------------------"

_check_gone() {
  local label="$1"; shift
  local resp
  resp=$("$@" 2>&1) || true
  if echo "${resp}" | grep -qiE "${GONE_REGEX}"; then
    echo "OK: ${label} is gone"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: ${label} still exists"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

_check_count_zero() {
  local label="$1"; shift
  local count
  count=$("$@" 2>/dev/null || echo "ERR")
  count="${count//[[:space:]]/}"
  if [[ "${count}" == "0" ]]; then
    echo "OK: ${label} count = 0"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: ${label} count = ${count}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# --- AWS-side checks ---
_check_gone "Bridge Lambda hera-twilio-bridge-prod" \
  aws lambda get-function --function-name hera-twilio-bridge-prod --region "${REGION}"

_check_gone "IAM role hera-twilio-bridge-prod-exec" \
  aws iam get-role --role-name hera-twilio-bridge-prod-exec

_check_count_zero "APIGW WS API hera-twilio-ws" \
  aws apigatewayv2 get-apis \
    --query "Items[?Name=='hera-twilio-ws'] | length(@)" --output text \
    --region "${REGION}"

_check_count_zero "CW log group /aws/lambda/hera-twilio-bridge-prod" \
  env MSYS_NO_PATHCONV=1 aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/hera-twilio-bridge-prod \
    --region "${REGION}" \
    --query 'logGroups | length(@)' --output text

_check_count_zero "CW log group /aws/apigateway/hera-twilio-ws" \
  env MSYS_NO_PATHCONV=1 aws logs describe-log-groups \
    --log-group-name-prefix /aws/apigateway/hera-twilio-ws \
    --region "${REGION}" \
    --query 'logGroups | length(@)' --output text

# --- Twilio-side checks (curl + jq against Twilio REST API) ---
TWILIO_API="https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}"
TWILIO_AUTH="${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}"

# Incoming phone numbers tagged for hera-twilio-bridge:
NUMBERS_COUNT=$(curl -s -u "${TWILIO_AUTH}" "${TWILIO_API}/IncomingPhoneNumbers.json" \
  | jq '[.incoming_phone_numbers[] | select(.friendly_name | test("hera"; "i"))] | length')
if [[ "${NUMBERS_COUNT}" == "0" ]]; then
  echo "OK: Twilio IncomingPhoneNumbers count (hera-tagged) = 0"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: Twilio IncomingPhoneNumbers (hera-tagged) count = ${NUMBERS_COUNT}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# TwiML Bins tagged for hera-bridge:
TWIML_COUNT=$(curl -s -u "${TWILIO_AUTH}" "https://serverless.twilio.com/v1/TwimlBins" \
  | jq '[.twiml_bins[]? | select(.friendly_name | test("hera"; "i"))] | length' 2>/dev/null \
  || echo "0")
if [[ "${TWIML_COUNT}" == "0" ]]; then
  echo "OK: Twilio TwiML Bins (hera-tagged) count = 0"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: Twilio TwiML Bins (hera-tagged) count = ${TWIML_COUNT}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "----------------------------------------"
echo "cleanup-verify-twilio: ${PASS_COUNT}/${TOTAL} resources verified clean"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: ${FAIL_COUNT} leftover(s) detected." >&2
  echo "Hints:" >&2
  echo "  - Did you release the Twilio phone number in console BEFORE terraform destroy?" >&2
  echo "  - Did you delete the TwiML Bin in console?" >&2
  echo "  - Did 'terraform destroy' complete without error in infra/envs/prod?" >&2
  exit 1
fi

echo "OK (cleanup-twilio): all phase 6 resources removed"
exit 0
```

### RUNBOOK Phase 6 Section Outline (planner extends RUNBOOK.md)

```markdown
## Phase 6 — Twilio Voice Channel Setup (operator paste-style)

### Pre-flight
- AWS CLI v2 + Terraform >=1.9 + jq + curl + uv (per Phase 1-5 RUNBOOK pre-flight; nothing new).
- A Twilio account (sign up free at https://www.twilio.com/try-twilio).
- A funded Twilio balance (~$5 covers the workshop demo + 30min testing).

### Step 1: Create Twilio account + capture credentials
1. Sign up, verify email + phone, complete onboarding.
2. Twilio console → Account → API keys & tokens. Copy:
   - Account SID (starts `AC...`)
   - Auth Token (click "Show")
3. Set env vars locally (NEVER commit):
   ```bash
   export TF_VAR_twilio_auth_token=<paste auth token>
   export TWILIO_ACCOUNT_SID=<paste account sid>
   export TWILIO_AUTH_TOKEN=<paste auth token>  # for cleanup-verify later
   ```

### Step 2: Buy a phone number
1. Twilio console → Phone Numbers → Manage → Buy a number.
2. Filter by capabilities: Voice ✓. Country: US (or local; cheapest is US local at $1.15/mo).
3. Buy. Note the number (e.g., +18005551234).

### Step 3: Deploy bridge (Terraform)
```bash
cd infra/envs/prod
terraform apply -var=agentcore_runtime_arn=arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD
# (TF_VAR_twilio_auth_token is read from env automatically.)
# Capture the WSS URL output:
TWILIO_BRIDGE_WSS_URL=$(terraform output -raw twilio_bridge_wss_url)
echo "${TWILIO_BRIDGE_WSS_URL}"   # wss://abc123.execute-api.ap-northeast-1.amazonaws.com/prod
```

### Step 4: Create TwiML Bin
1. Twilio console → Develop → TwiML Bins → Create new TwiML Bin.
2. Friendly name: `hera-bridge-prod`.
3. Paste content (replace `<APIGW-WS-URL>` with the value from Step 3):
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <Response>
     <Connect>
       <Stream url="<APIGW-WS-URL>" />
     </Connect>
   </Response>
   ```
4. Save. Copy the TwiML Bin SID (starts `EH...`) and URL.

### Step 5: Wire the number's voice webhook to the TwiML Bin
1. Twilio console → Phone Numbers → Manage → Active numbers → click your number.
2. Voice & Fax section → "A call comes in" → set to TwiML Bin → pick `hera-bridge-prod`.
3. Save.

### Step 6: Smoke test
1. Dial the number from your phone.
2. Wait for AgentCore concurrency (cap=2 — make sure no browser session is active).
3. Speak: "Do you have iPhone 13 Pro Max in stock?"
4. Hera should respond within ~3 seconds.
5. End call.
6. Tail logs to verify:
   ```bash
   aws logs tail /aws/lambda/hera-twilio-bridge-prod --since 5m --region ap-northeast-1
   ```

### Step 7: Cost watch
- Twilio console → Usage → Voice → confirm <$0.10 spent for the test call.
- Hera AWS billing: Phase 4 alarm at $5/day still covers this.

### Phase 6 Cleanup (release in this exact order!)
1. **Release the Twilio number FIRST.** Console → Phone Numbers → Manage → Active numbers → click number → Release this number → confirm. (Deletes monthly hold.)
2. **Delete TwiML Bin.** Console → Develop → TwiML Bins → click `hera-bridge-prod` → Delete.
3. **Terraform destroy.**
   ```bash
   cd infra/envs/prod
   terraform destroy
   ```
4. **Verify.**
   ```bash
   bash bin/cleanup-verify-twilio.sh
   # Expect: cleanup-verify-twilio: <N>/<N> resources verified clean
   ```
```

---

## Validation Architecture

`workflow.nyquist_validation = false` (per `.planning/config.json` line 24). **This section is omitted per config.**

---

## Security Domain

`security_enforcement = true` per `.planning/config.json`. Phase 6 is API-server (Lambda + APIGW) with telephony auth — V2 (auth), V4 (access control), V5 (input validation), V6 (cryptography) categories ALL apply.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | **YES** | Twilio webhook auth: `twilio.request_validator.RequestValidator` (HMAC-SHA1). Server-side AWS auth: `botocore.auth.SigV4QueryAuth` (re-using widget_presigner pattern). |
| V3 Session Management | YES | AgentCore Runtime native session management (`X-Amzn-Bedrock-AgentCore-Runtime-Session-Id`, default 15min idle timeout). Bridge Lambda passes Twilio CallSid as session_id for conversation continuity. |
| V4 Access Control | YES | Bridge Lambda IAM scoped EXACTLY to `hera_agent-GIsf2P4ImD` runtime ARN (D-66). Zero IAM wildcards (D-13 carry-forward). Confused-deputy condition `aws:SourceAccount`. |
| V5 Input Validation | YES | Twilio JSON envelope MUST be parsed and event-field validated before dispatch. Untrusted base64 audio MUST be size-bounded (32 KB APIGW WS frame cap structurally bounds this). |
| V6 Cryptography | YES | NEVER hand-roll HMAC-SHA1 (use Twilio SDK). NEVER hand-roll SigV4 (use botocore). Both are battle-tested. |

### Known Threat Patterns for AWS Lambda + APIGW WebSocket + Twilio

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Anonymous bridge abuse (script kiddies hit the public WSS URL) | Spoofing / Denial of service | X-Twilio-Signature HMAC validation at `$connect` (D-67). Reject 403 on invalid signature. AgentCore concurrency cap=2 (D-65) bounds blast radius. Bridge Lambda reserved-concurrency=5 (D-65). |
| Twilio AuthToken leak in git | Information Disclosure | Sensitive Terraform variable `twilio_auth_token`; passed via `TF_VAR_*` env. terraform.tfvars NEVER committed (project pattern). |
| Lambda secrets in logs | Information Disclosure | NEVER log the auth token. Lambda env vars are not auto-logged but a careless `print(os.environ)` would. Code review enforces. |
| Audio replay / forgery | Tampering | Twilio MAC-signs only the WS handshake (per Q6); per-frame audio is not signed. Inherent in Media Streams protocol. Acceptable for v2 demo (calls are bounded by AgentCore cap=2 + Twilio inbound minutes Twilio-side rate-limit). v3+ would add JWT or out-of-band session tokens. |
| Cross-account confused-deputy | Elevation of Privilege | Lambda trust policy uses `aws:SourceAccount=851725411875`. SigV4 only signs from this account. |
| Excessive Bedrock cost from leaked phone number | Repudiation / Denial of service | Phase 4 billing alarm $5/day (OBS-03) covers this. Bridge Lambda concurrency=5 + AgentCore concurrency=2 = max 2 concurrent live calls. |

---

## Don't-Forget Checks Before Coding

- [ ] Operator can probe what sample rate Sonic actually emits over `/ws` data-plane (Q2 [ASSUMED] flag). 16 kHz vs 24 kHz changes the resampler `inrate` parameter.
- [ ] Q1 architectural finding raised to user via `/gsd-discuss-phase` Phase-6-D58-followup (or planner explicitly resolves locked path).
- [ ] `TF_VAR_twilio_auth_token` is in operator's shell env, NOT committed to terraform.tfvars.
- [ ] `widget_presigner_*` resources untouched (D-64 — v1 unchanged).
- [ ] `bin/cleanup-verify.sh` (v1) NOT modified by Phase 6 — only `bin/cleanup-verify-twilio.sh` (new) is created.
- [ ] No `cdk deploy` in Phase 6 — agent container + AgentCore Runtime UNCHANGED.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Per-frame fresh AgentCore session (Q1 Option γ) latency is ~150-600ms; structurally infeasible for real-time voice | Q1 | If actual measured latency is sub-50ms, option γ becomes more viable (still has session-fragmentation issue but worth re-test). Recommend a quick spike measurement. |
| A2 | Sonic outputs 16 kHz Int16 over `bedrock-agentcore /ws`. Phase 2 RUNBOOK says 24 kHz at the agent's WebSocket; the WSS data-plane may differ. | Q2 | If 24 kHz, resample param `inrate=24000` (one-line change). Probe live before coding. |
| A3 | `audioop.ratecv` per-frame state=None will produce acceptable audio quality without obvious clicks for short fragments | Pitfall 4 | Likely audible if the Lambda model forces fresh state per frame. Mitigation: ear-test on first frame round-trip; if clicks audible, escalate to DynamoDB state OR App Runner per Q1. |
| A4 | `bedrock-agentcore` PyPI helper SDK installs cleanly in Lambda Python 3.13 with reasonable size | Q4 | If too heavy, fall back to direct `botocore.auth.SigV4QueryAuth` (proven Phase 3 pattern). |
| A5 | `audioop-lts` ratecv produces bit-exact output to stdlib `audioop.ratecv` | Q2 | If subtly different (e.g., different default filter weights), audio may sound off. Mitigation: A/B test `audioop.ratecv` (Python 3.12 stdlib) vs `audioop-lts` on a known input fragment. |
| A6 | API Gateway WebSocket text-frame contract carries Twilio's JSON-with-base64-audio without modification | Q3 | Verified safe by AWS docs (Twilio uses text). If Twilio ever sends a binary frame for some reason, APIGW closes with 1003. |
| A7 | Twilio US local pricing $0.0085/min current (NOT $0.013/min as in CONTEXT D-65) | Q7 | RUNBOOK paste-block updates with current rate. Only affects per-call cost messaging in workshop docs, not contract. |
| A8 | `bedrock-agentcore` IAM action `InvokeAgentRuntimeWithWebSocketStream` exists and is the right action | Q4 | Verified via 3 sources (AWS docs, widget_presigner main.tf line 69, AWS Bedrock AgentCore samples GitHub). HIGH confidence. |

**To resolve before / during planning:** A1, A2, A3, A4 — these affect concrete code shape and may surface a re-design need.

---

## Open Questions

1. **Q1 — D-58 architectural choice.** RECOMMENDATION: surface to user via `/gsd-discuss-phase Phase-6-D58-followup`. Three options. Default recommendation: Option β (App Runner). Without this question resolved, Phase 6 risk of shipping non-functional bridge is HIGH.

2. **Sonic output sample rate.** Resolution: 2-minute live probe.

3. **`bedrock-agentcore` PyPI vs `botocore.auth.SigV4QueryAuth` for upstream signing.** Either works. Phase 3 widget_presigner uses the latter; sticking with that pattern is cheapest.

4. **Bridge Lambda packaging — pyproject.toml + uv vs requirements.txt + pip.** Phase 5 RUNBOOK already standardizes uv. `uv pip install --target` is supported. Recommend uv. Plumbing detail.

---

## Recommended Plan / Wave Structure

### Recommendation: 2 Plans, 2 Waves

**Wave 1 — Plan 06-01: bridge module + handler code**
- Files NEW: `infra/modules/twilio_bridge/{versions.tf, variables.tf, main.tf, outputs.tf, src/handler.py, src/resampler.py, src/upstream.py, src/requirements.txt}`
- Files MODIFIED: `infra/envs/prod/{main.tf, variables.tf, outputs.tf}` (add module block, var, output)
- Acceptance: `terraform validate` passes; `terraform plan` (dry) emits exactly the expected new resources; bridge Lambda zips clean; module local file structure matches widget_presigner pattern.
- Live AWS work: ZERO until Plan 06-02. Plan 06-01 is IaC-only + unit-tested handler.

**Wave 2 — Plan 06-02: cleanup-verify-twilio.sh + RUNBOOK + live deploy + smoke**
- Files NEW: `bin/cleanup-verify-twilio.sh`
- Files MODIFIED: `RUNBOOK.md` (add Phase 6 section)
- Live AWS work: 1 `terraform apply -var=agentcore_runtime_arn=...` + 1 paste-style operator setup (Twilio number + TwiML Bin) + 1 dial-in smoke + 1 `cleanup-verify-twilio.sh` dry run (returns FAIL while resources are still deployed — that's how the script works).
- Acceptance: Phone dial-in → Sonic responds within 3s; bin/cleanup-verify-twilio.sh exits 0 after operator releases Twilio + terraform destroy.

### Rationale

- **Why 2 plans not 1.** Wave 2 needs Wave 1's `terraform output -raw twilio_bridge_wss_url` to populate the TwiML Bin. Hard sequence dependency.
- **Why 2 plans not 3.** Splitting bridge handler from Terraform adds 1 plan with no parallelism gain — the same human reviews both. The natural file boundary is "infra-side" vs "operator-side" (RUNBOOK + verify script + live deploy).
- **File-disjoint between waves.** Wave 2 does NOT touch `infra/modules/twilio_bridge/` (Wave 1's output). Wave 1 does NOT touch `bin/` or `RUNBOOK.md`.
- **Q1 finding gates Wave 1.** Plan 06-01 should not ship Lambda handler code that's structurally broken (Option γ). The planner MUST resolve Q1 first — either via explicit user discussion (default recommendation: switch D-56 to App Runner), or by accepting Option γ as documented-broken phase scope.

### Alternative: 3 Plans (NOT recommended)

- Plan 06-01: TF module skeleton only (versions/variables/main/outputs, no Lambda handler).
- Plan 06-02: Lambda handler code (handler.py + resampler.py + upstream.py + requirements.txt).
- Plan 06-03: cleanup-verify + RUNBOOK + live deploy.

This would let Plan 06-01 + Plan 06-02 be parallel — but no, Plan 06-02 depends on the IAM Resource ARN format that Plan 06-01 establishes. Net: zero parallelism, +1 plan overhead. Skip.

### Alternative: 1 Plan (NOT recommended)

Single plan does both waves in sequence. Risk: 1 huge plan with mixed concerns (TF + Python + bash + RUNBOOK markdown), harder to review, harder to back out, no atomic boundary between IaC complete and "operator paste + smoke". Skip.

---

## Sources

### Primary (HIGH confidence)
- [AWS Bedrock AgentCore - Get started with bidirectional streaming](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-get-started-websocket.html) — verified 2026-05-07; canonical WSS endpoint `/runtimes/<ARN>/ws`, IAM action, SigV4 service name
- [AWS Bedrock AgentCore - Bi-directional streaming announcement (2025-12-18)](https://aws.amazon.com/blogs/machine-learning/bi-directional-streaming-for-real-time-agent-interactions-now-available-in-amazon-bedrock-agentcore-runtime/)
- [Twilio Media Streams - WebSocket Messages](https://www.twilio.com/docs/voice/media-streams/websocket-messages) — verified 2026-05-07; envelope shapes
- [Twilio Webhooks Security](https://www.twilio.com/docs/usage/webhooks/webhooks-security) — verified 2026-05-07; HMAC-SHA1 algorithm + WSS handshake quirk
- [Twilio TwiML Voice <Stream>](https://www.twilio.com/docs/voice/twiml/stream) — verified 2026-05-07
- [AWS API Gateway WebSocket overview](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-websocket-api-overview.html) — verified 2026-05-07; route mappings + close codes
- [AWS API Gateway WebSocket quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-execution-service-websocket-limits-table.html) — verified 2026-05-07; 29s integration timeout, 32KB frame, 128KB message, 10min idle, 2hr connection
- [AWS Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) — verified 2026-05-07; Python 3.13 supported until 2029-06-30
- [audioop-lts on PyPI](https://pypi.org/project/audioop-lts/) — verified 2026-05-07; v0.2.2; Python ≥3.13 required
- [Python 3.12 audioop docs](https://docs.python.org/3.12/library/audioop.html) — verified 2026-05-07; deprecated, removed in 3.13
- [Twilio Programmable Voice US Pricing](https://www.twilio.com/en-us/voice/pricing/us) — verified 2026-05-07
- [AWS API Gateway pricing](https://aws.amazon.com/api-gateway/pricing/) — verified 2026-05-07
- `infra/modules/widget_presigner/src/handler.py` — existing Hera SigV4 pattern, proven in Phase 3 production
- `infra/modules/widget_presigner/main.tf` — existing IAM-no-wildcards pattern + Lambda+Function-URL shape

### Secondary (MEDIUM confidence)
- [aws-samples/sample-amazon-nova-sonic-twilio-integration](https://github.com/aws-samples/sample-amazon-nova-sonic-twilio-integration) — README; "EC2/ECS/EKS behind ALB" explicitly NOT Lambda
- [aws-samples/sample-aws-bedrock-twilio-voice-ai](https://github.com/aws-samples/sample-aws-bedrock-twilio-voice-ai) — re:Invent 2025; Application Load Balancer-fronted Fargate; not Lambda
- [Amazon Lex + Twilio Media Streams (AWS ML blog 2019-08)](https://aws.amazon.com/blogs/machine-learning/use-amazon-lex-as-a-conversational-interface-with-twilio-media-streams/) — Fargate behind ALB sticky sessions
- [webrtc.ventures Serverless Voice AI (2025-07)](https://webrtc.ventures/2025/07/how-to-build-a-serverless-voice-ai-assistant-for-telephony-in-aws-using-twilio-conversationrelay/) — Lambda + APIGW WS works for ConversationRelay text only
- [PEP 594 - Removing dead batteries from the standard library](https://peps.python.org/pep-0594/#audioop) — audioop deprecation rationale
- [Twilio Bidirectional Streaming changelog](https://www.twilio.com/en-us/changelog/bi-directional-streaming-support-with-media-streams)

### Tertiary (LOW confidence — flagged for validation if used)
- [AWS Lambda Python 3.13 announcement (2024-11-14)](https://aws.amazon.com/blogs/compute/python-3-13-runtime-now-available-in-aws-lambda/) — release date verification

---

## Metadata

**Confidence breakdown:**
- AgentCore data-plane WSS contract (Q4): HIGH — verified against AWS docs verbatim quote + existing Hera widget_presigner production code
- Twilio Media Streams envelope (Q5): HIGH — verified against Twilio docs verbatim quote
- Twilio webhook signature (Q6): HIGH — verified against Twilio docs verbatim quote
- API Gateway WebSocket route layout + limits (Q3): HIGH — verified against AWS docs
- audioop-lts + Python 3.13 timeline (Q2): HIGH — verified against PyPI + AWS docs
- Cost estimates (Q7): HIGH — verified against current Twilio/AWS pricing pages
- D-58 upstream WSS persistence pattern (Q1): **MEDIUM-LOW for "Lambda is the right compute"** — researched extensively; no canonical AWS pattern matches the exact chain; recommend re-evaluation of D-56 by user
- Standard stack (Python 3.13 + audioop-lts + websockets + twilio): HIGH — all verified
- Architecture patterns: HIGH (handler skeleton) / MEDIUM (upstream session lifecycle pending Q1 resolution)
- Pitfalls: HIGH — well-known traps documented across multiple sources

**Research date:** 2026-05-07
**Valid until:** 2026-06-07 (30 days for stable AWS surface; faster invalidation expected for AgentCore which is still evolving)
