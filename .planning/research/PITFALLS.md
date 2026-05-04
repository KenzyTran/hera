# Pitfalls Research

**Domain:** AWS-native voice AI agent (Pipecat + Nova 2 Sonic + Bedrock KB + S3 Vectors + ECS Fargate + Terraform) — built as both a working demo AND a teaching workshop.
**Researched:** 2026-05-04
**Confidence:** HIGH for AWS service behavior, Pipecat known issues, and workshop UX failures (verified against AWS docs, Pipecat GitHub issues, and production guides). MEDIUM for exact Nova Sonic concurrency quotas (region-specific, not publicly documented).

This document covers two failure surfaces simultaneously:

1. **System pitfalls** — bugs we will hit while building hera.
2. **Workshop UX pitfalls** — failure modes that confuse Cloud Clubs learners doing the hands-on.

Severity legend used throughout: **P0** = blocker, voice loop will not work / learner cannot continue; **P1** = user-visible defect or learner gets stuck without help; **P2** = cleanup, polish, or cost hygiene.

---

## Critical Pitfalls

### Pitfall 1: Nova 2 Sonic 8-minute hard session timeout (P0 — voice)

**What goes wrong:**
Nova Sonic's `InvokeModelWithBidirectionalStream` connection has a default ~8-minute lifetime. After ~8 minutes a single bidirectional connection raises `ModelTimeoutException: "Model has timed out in processing the request."` and the WebSocket dies mid-conversation. In a workshop demo, the presenter's "let me show you a long demo" call dies on stage.

**Why it happens:**
The bidi-stream API enforces a server-side cap independent of the underlying TCP/WebSocket. Many Pipecat tutorial samples don't implement reconnect-with-context-replay, so the conversation just ends.

**How to avoid:**
- Treat the 8-minute cap as a contract. Implement session rotation: detect approaching timeout, open a new bidi stream, and pass `previousConversationHistory` in the new session prompt.
- Surface `ModelTimeoutException` as a known event in logs, not a bug.
- For workshop demos: keep scripted demo flows under 6 minutes per single connection, OR explicitly demo the rotation.

**Warning signs:**
- "Worked in dev" but breaks in long-form QA sessions.
- CloudWatch logs show `ModelTimeoutException` clustered around the 480-second mark.
- User complains "it just stopped responding" after long pause-and-think turns.

**Phase to address:** Pipecat orchestrator phase (session management is part of orchestrator core, not optional polish).

---

### Pitfall 2: ALB 60-second idle timeout silently kills WebSocket sessions (P0 — voice)

**What goes wrong:**
AWS ALB default idle timeout is 60 seconds. If no bytes cross the proxy in any 60-second window — including pure listening with VAD silence — ALB closes the connection (RFC 1006 close). The browser sees `WebSocket close code 1006`, audio just dies. This is the single most reproducible bug for AWS-hosted Pipecat WebSocket deployments.

**Why it happens:**
Voice apps spend long periods with no inbound bytes (user thinking, agent generating). VAD-suppressed silence still produces no frames over the wire unless we explicitly send keepalives. The default ALB timeout was designed for short HTTP requests, not long-lived voice streams.

**How to avoid:**
- Raise `idle_timeout.timeout_seconds` on the ALB to 3600 (1 hour) or higher in Terraform.
- Implement application-level WebSocket ping/pong every 25 seconds (clears every common proxy default).
- Document this as a Terraform variable with a comment ("DO NOT lower below 600 — voice sessions will drop").

**Warning signs:**
- Sessions die at exactly ~60s into pauses.
- Browser console shows `WebSocket close code 1006` (abnormal closure).
- ALB access logs show `target_status_code: -` (connection closed by LB).
- Works on `localhost` but breaks deployed.

**Phase to address:** Terraform infrastructure phase (ALB module). Workshop must call this out as a "Heads up" box because learners hitting this will think their code is broken.

---

### Pitfall 3: Bedrock model access not enabled in workshop region (P0 — workshop blocker)

**What goes wrong:**
Learner runs the first `terraform apply` or first Pipecat invocation and gets `AccessDeniedException: You don't have access to the model with the specified model ID`. They have no idea this is account-level enablement, not IAM.

**Why it happens:**
Bedrock requires explicit model access enablement per-model per-region in the console, separate from IAM permissions. Nova 2 Sonic is gated. New AWS accounts in regions like ap-northeast-1 have nothing enabled by default. This is the single most common workshop blocker reported across the AWS Bedrock workshop ecosystem.

**How to avoid:**
- Phase 2 (Preparation) section of workshop docs MUST include a screenshot-stepped chapter "Enable Nova 2 Sonic model access in ap-northeast-1" before any code is run.
- Provide a one-liner pre-flight check: `aws bedrock list-foundation-models --region ap-northeast-1 --by-output-modality SPEECH` and grep for `amazon.nova-2-sonic`.
- Terraform `null_resource` precondition that calls the AWS CLI to verify model access; fail apply with a clear message before creating any resources.
- Workshop must show a screenshot of the "Modify model access" page in the exact region the workshop deploys to.

**Warning signs:**
- `AccessDeniedException` on first invocation despite seemingly correct IAM.
- `bedrock:InvokeModel` is allowed in IAM but call still fails.
- `list-foundation-models` does not list Sonic as accessible.

**Phase to address:** Workshop preparation phase (Phần 2). Must precede any Terraform apply.

---

### Pitfall 4: Audio sample-rate mismatch — Sonic expects 16kHz mono PCM in, returns 24kHz out (P0 — voice quality)

**What goes wrong:**
Browser captures 48kHz Float32 audio by default. Send that to Sonic and you get garbled transcription, no transcript, or silent failure. Send 24kHz output to a player expecting 48kHz and audio plays at half speed (chipmunk effect).

**Why it happens:**
Nova Sonic input contract: 16-bit PCM, 16kHz, mono. Output contract: base64 PCM at 24kHz. Browser `getUserMedia` defaults are sample-rate-agnostic and typically 48kHz. Pipecat's `AWSNovaSonicLLMService` does not auto-resample browser input — this is the application's responsibility.

**How to avoid:**
- In the browser widget, request `audioContext = new AudioContext({ sampleRate: 16000 })` and downsample explicitly before WebSocket send.
- On the server, validate inbound frame rate; log loudly if not 16000.
- For TTS playback, create a separate `AudioContext({ sampleRate: 24000 })` for the response stream.
- Document the format contract in the widget code with a comment block at the top.

**Warning signs:**
- Audio sounds slow/fast like Alvin & The Chipmunks.
- Sonic returns empty transcript for clearly-spoken audio.
- Distorted noise / static instead of voice.

**Phase to address:** Web widget phase. The widget is the closest thing to "user-facing", and audio format is non-negotiable.

---

### Pitfall 5: ALB target group health check on a WebSocket-only app (P0 — deployment)

**What goes wrong:**
ALB health checks do not support WebSockets — they only do HTTP/HTTPS. If the Pipecat container only exposes a `/ws` WebSocket endpoint, ALB cannot health check it. Default health check on `/` returns 404 → ALB marks task unhealthy → ECS replaces task → new task also fails health check → infinite replacement loop. Demo never goes live.

**Why it happens:**
Pipecat tutorials often show only the WebSocket endpoint. Authors forget that ALB needs a separate HTTP health endpoint. ALB health checks make HTTP GETs, not WebSocket upgrades.

**How to avoid:**
- Pipecat container MUST expose a separate `GET /healthz` HTTP endpoint that returns `200 OK` independent of WebSocket state.
- Configure ALB target group `health_check.path = "/healthz"`, `matcher = "200"`.
- Set `health_check_grace_period_seconds = 60` on the ECS service (Pipecat takes time to initialize VAD model).
- Terraform module should reject configurations where health check path is unset.

**Warning signs:**
- ECS service "Events" tab spam: "task ... failed ELB health checks" every 30s.
- CloudWatch log group churns through tasks; each task lives ~2 minutes.
- Browser cannot connect; ALB returns 503.

**Phase to address:** Pipecat container phase (must expose health endpoint) + Terraform infrastructure phase (must wire it up).

---

### Pitfall 6: ECS task IAM role missing `bedrock:InvokeModelWithBidirectionalStream` permission (P0 — voice)

**What goes wrong:**
The task starts, ALB health check passes, WebSocket connects, but the moment the user speaks Sonic returns `AccessDenied`. Many Bedrock IAM examples grant `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` only — these are not enough for bidirectional streaming.

**Why it happens:**
`InvokeModelWithBidirectionalStream` is its own IAM action (or, depending on exact policy form, requires `bedrock:InvokeModel` plus the right resource ARN format including `foundation-model/amazon.nova-2-sonic-v1:0`). AWS docs are inconsistent across pages on which exact action key applies — some pages list it as covered by `bedrock:InvokeModel`, others require the longer name. Easiest safe policy uses both.

**How to avoid:**
- Task role policy should explicitly grant `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`, and `bedrock:InvokeModelWithBidirectionalStream` on the model ARN.
- Use the model ARN form `arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.nova-2-sonic-v1:0` — wildcard region matters because eval region is the calling region.
- Test the task role with a simple scripted invoke before wiring to WebSocket.

**Warning signs:**
- First voice frame causes immediate `AccessDeniedException` in CloudWatch.
- Works in local dev with personal credentials, fails on Fargate.

**Phase to address:** Terraform IAM module phase. Must be a discrete "task role for Sonic" module.

---

### Pitfall 7: VPC egress without NAT or VPC endpoint = no Bedrock connectivity (P0 — deployment)

**What goes wrong:**
Learner deploys ECS Fargate tasks into private subnets (because that's "best practice"). Tasks start, but every Bedrock call hangs and times out. There's no path out of the VPC.

**Why it happens:**
Private subnets without a NAT gateway or VPC endpoint cannot reach any AWS service public endpoint. Bedrock has no Gateway endpoint (S3 and DynamoDB do); it requires an Interface Endpoint (PrivateLink). Workshop authors often skip this because their personal account uses default VPC with internet gateway.

**How to avoid:**
Two viable options for the workshop, document both:
- **Option A (cheaper for student account):** Deploy tasks in public subnets with `assign_public_ip = true` and security group locking ingress to ALB only. No NAT needed. Direct internet egress to Bedrock public endpoint.
- **Option B (more "production-correct"):** Private subnets + Interface VPC Endpoint for `com.amazonaws.<region>.bedrock-runtime` + S3 Gateway Endpoint (free) for ECR layer pulls.
- Terraform module should support both, default to Option A for workshop simplicity, with a comment explaining cost vs production tradeoff.
- Calling out NAT cost ($35-45/mo per AZ, plus data charges) is critical — workshop learners running 24/7 NAT will get unexpected bills.

**Warning signs:**
- Task starts but Bedrock calls hang for ~30s then time out.
- CloudWatch logs show DNS resolution OK but socket connect fails.
- VPC Flow Logs show no traffic leaving the subnet.

**Phase to address:** Terraform networking module phase. MUST be addressed before first end-to-end test.

---

### Pitfall 8: S3 Vectors embedding model and dimension lock-in (P1 — KB)

**What goes wrong:**
Learner creates Knowledge Base with Titan Text Embedding v2 at 1024 dimensions, ingests Apple catalog, gets it working. Later wants to switch to Cohere or Titan v1 (1536 dim). KB throws dimension mismatch on retrieval. Index dimension cannot be changed after creation. Only fix: destroy the index, recreate, re-ingest.

**Why it happens:**
S3 Vectors index dimension is set at creation and is immutable. Embedding model choice locks dimension. Workshop learners often pick model based on a list without realizing it's a one-way door.

**How to avoid:**
- Workshop pins a single embedding model (recommend Titan v2 at 1024 dim) and explains the lock-in upfront.
- Terraform variable `embedding_model_arn` is documented as "DO NOT CHANGE after first apply — requires destroy/recreate of vector index".
- Code comment in Terraform module above the index resource.
- Workshop "anti-pattern" callout: "Don't try to A/B test embedding models in this workshop — pick one and stay with it."

**Warning signs:**
- KB sync succeeds but retrieval returns 0 results.
- Error: `dimension mismatch: expected 1024 got 1536` in retrieval response.

**Phase to address:** Knowledge Base + Terraform module phase. Must lock decisions before first ingestion.

---

### Pitfall 9: Knowledge Base sync delay — uploaded doc not retrievable immediately (P1 — workshop UX)

**What goes wrong:**
Learner uploads Apple catalog CSV to S3, runs sync, immediately tests "What MacBooks do you have?" — gets "I don't have that information." Concludes it's broken. Actually KB needs minutes for vector embeddings to propagate after sync completes.

**Why it happens:**
Sync job status hits "Complete" before embeddings are queryable. The S3 Vectors backend has a propagation window. AWS docs say "could take a few minutes for the vector embeddings of the newly ingested data to be available in the vector store for querying" but workshop tutorials skip this.

**How to avoid:**
- Workshop step explicitly says: "Wait 2-3 minutes after sync completes before testing retrieval."
- Provide a verification one-liner using `bedrock-agent-runtime retrieve` that polls until results appear.
- Set learner expectation: this is normal AWS service behavior, not a bug.

**Warning signs:**
- Sync status `Complete` but retrieval empty.
- Document `INDEXED` per `GetKnowledgeBaseDocuments` but searches return nothing.

**Phase to address:** Knowledge Base phase. Workshop docs and demo script must include the wait.

---

### Pitfall 10: Browser microphone requires HTTPS (and so does the WebSocket server) (P0 — workshop UX)

**What goes wrong:**
Learner deploys ECS+ALB without an ACM certificate, gets HTTP-only ALB, opens widget, clicks "Record" — browser silently denies microphone access with no obvious error. Or learner uses HTTPS for the widget page but `ws://` for WebSocket — mixed-content blocked by browser.

**Why it happens:**
`getUserMedia()` requires a secure context. HTTP fails with `NotAllowedError`. Mixed content (HTTPS page + `ws://`) is blocked silently in modern Chrome/Firefox/Safari. `localhost` is the only HTTP exception.

**How to avoid:**
- Workshop terraform provisions ACM cert + HTTPS listener as default. No HTTP-only path.
- Workshop preparation phase walks through ACM DNS validation OR uses a domain-on-ALB approach (e.g., validation via Route53 if learner has a hosted zone, or a placeholder subdomain).
- For zero-cost workshop without a custom domain: document using AWS-issued ALB DNS name with self-signed cert is NOT enough (browsers reject); recommend a free Route53 + ACM + cheap domain, or use `ngrok`/`localhost.run` for local dev path.
- Widget code uses `wss://` derived from `window.location.protocol` to avoid mixed-content.

**Warning signs:**
- Click "Record", nothing happens, no JS error visible.
- Browser console: `NotAllowedError: Permission denied`.
- Console: `Mixed Content: The page was loaded over HTTPS, but attempted to connect to the insecure WebSocket endpoint`.

**Phase to address:** Web widget + Terraform ACM/ALB phase.

---

### Pitfall 11: Pipecat memory leak / OOM under multi-session load (P1 — operational)

**What goes wrong:**
Single-session demo works. Multiple concurrent sessions cause Pipecat process memory to climb fast (reports of 3GB/min in some pipelines). Fargate task crashes with 137 (OOM kill). Workshop demo with two presenters talking at once dies.

**Why it happens:**
Pipecat's stateful pipeline holds VAD model, audio buffers, conversation history per session in the same process. Known memory leak issues exist in 0.0.85+ on Linux (not macOS, so dev rarely catches it). `AudioOutMixer` and certain transports have leaks. The recommended pattern is "1-container-per-session" but that's overkill for a workshop demo.

**How to avoid:**
- For workshop scope (low concurrency, single demo): pin a Pipecat version that doesn't have the known leak. Verify on Linux Fargate, not just dev macOS.
- Size Fargate task generously: 2 vCPU, 4GB minimum. Don't try to be cheap with 0.5 vCPU/1GB.
- Configure ECS service auto-scaling on memory utilization (target 70%) to scale out before OOM.
- Set ECS task `essential: true` and verify task replaces fast on death.
- Workshop "Heads up" box: "Pipecat is one-process-per-session in spirit. For real production, run AgentCore Runtime or session-isolated containers."

**Warning signs:**
- Task exits with code 137.
- Memory utilization graph in CloudWatch climbs steadily.
- New users connecting cause progressively worse latency.

**Phase to address:** Pipecat orchestrator + Terraform ECS sizing phase.

---

### Pitfall 12: Tool-use schema mismatch between Pipecat function definitions and Sonic JSON contract (P1 — voice + KB)

**What goes wrong:**
Sonic calls the KB lookup tool, but the response never gets back into the conversation. Sonic answers "I'll look that up for you" and then says nothing. OR: tool call fails with a JSON Schema validation error. Echoes the original presenter pain point in `raw_content.txt` line 2342-2378 ("we predict the system will fail initially") — the same first-call schema mismatch will recur on AWS.

**Why it happens:**
Pipecat's `AWSNovaSonicLLMAdapter` converts FunctionSchema to Sonic's tool format. Edge cases: empty parameter objects `{}`, optional fields, oneOf/anyOf, deeply nested objects don't always map cleanly. Known issue: `AWSNovaSonicLLMService' object has no attribute 'call_function'` regression. Tool result frames must come back via `LLMMessagesFrame` with the right content shape.

**How to avoid:**
- Define KB lookup tool with flat parameters: `{ query: string, max_results: int }`. Avoid nested objects.
- Test tool path in isolation before integrating: scripted text input → tool call → printed response.
- Pin a known-good Pipecat version (verify against current Pipecat AWS Nova Sonic example).
- Log `ToolUseFrame` and `ToolResultFrame` at INFO level so flow is visible during workshop debugging.

**Warning signs:**
- Sonic acknowledges ("Let me check…") then silence.
- CloudWatch shows tool invocation but no result frame returned to LLM.
- JSON Schema validation error on first tool call.

**Phase to address:** Pipecat orchestrator phase, specifically the KB-tool integration step.

---

### Pitfall 13: Public Bedrock endpoint without rate limit / auth = bill bomb (P1 — security/cost)

**What goes wrong:**
Learner deploys workshop, shares URL on Discord. Anonymous internet visitor opens widget, holds down Record, racks up Bedrock streaming charges. Or a bot scrapes the WebSocket endpoint and just keeps streaming silence. Bill arrives at $500.

**Why it happens:**
Workshop scope deliberately deferred Cognito/SSO. "Just a widget" feels harmless. Bedrock streaming charges per second of audio; with the 8-min session cap, an attacker can burn ~$0.40 per session * unlimited reconnects.

**How to avoid:**
- ALB-level rate limit: max 10 connections per source IP via WAF rule (free tier covers basic rate limit).
- Simple shared API key check on WebSocket upgrade — query param or header. Workshop docs explain "this is workshop-grade, real production needs Cognito."
- Aggressive AWS Budget alarm: $5/day threshold sends SNS email. Documented as part of preparation phase.
- Use throttling on the Pipecat side: max session duration 5 minutes hard cap, per-IP concurrent session limit of 1.
- Workshop "Heads up": "Don't share your endpoint publicly. The cleanup chapter will tear it down — do that the same day."

**Warning signs:**
- AWS Cost Explorer shows Bedrock spike.
- CloudWatch session count abnormally high.
- Same IP appears in many access log entries.

**Phase to address:** Terraform security module + Pipecat orchestrator (throttling) + workshop docs (cleanup chapter).

---

### Pitfall 14: CloudWatch logs retention forever + verbose Pipecat logging = silent cost growth (P2 — cost)

**What goes wrong:**
Default CloudWatch log group retention is "Never expire". Pipecat logs every audio frame at DEBUG. Over weeks, logs grow gigabytes. Bill includes a $30/mo line item for log ingestion the learner forgot existed.

**Why it happens:**
CloudWatch defaults are anti-frugal. Tutorials don't set retention. Pipecat logging defaults are verbose for development.

**How to avoid:**
- Terraform `aws_cloudwatch_log_group` always specifies `retention_in_days = 7` for workshop, with comment "raise to 30+ for production".
- Pipecat config sets log level to INFO for ECS task; DEBUG only via env var override.
- Workshop cleanup chapter explicitly verifies log groups deleted.

**Warning signs:**
- Cost Explorer shows CloudWatch line growing month-over-month.
- Log groups have no retention set (`Retention: Never`).

**Phase to address:** Terraform observability module + Pipecat orchestrator config.

---

### Pitfall 15: PII captured in CloudWatch transcripts (P1 — security/compliance)

**What goes wrong:**
Workshop demo logs full conversation transcripts. If a learner demos with a real user (e.g., friend providing real name, address, credit card to test), that PII lands in CloudWatch logs forever, queryable by anyone with `logs:GetLogEvents`. Also: even without real PII, the workshop demo accidentally teaches "log everything" as a pattern.

**Why it happens:**
Voice agents naturally capture sensitive content. CloudWatch is not encrypted by default at field level. Bedrock model invocation logs contain the full request unmodified, even when guardrails redact responses.

**How to avoid:**
- By default, log only frame metadata (timestamps, frame types, durations) — not transcript contents.
- If transcripts are useful for workshop debugging, redact via CloudWatch Logs data protection policy with a built-in PII detector.
- Workshop docs explicitly warn: "this stack is for synthetic Apple-catalog demo data only; do not feed real customer PII."
- Bedrock Guardrails with Sensitive Information Filter as recommended add-on (workshop scope: mention, don't necessarily implement in v1).

**Warning signs:**
- Code reviews show transcript strings logged at INFO.
- Tester reports "I told it my phone number and now it's in the logs".

**Phase to address:** Pipecat orchestrator phase + workshop docs section on responsible demoing.

---

### Pitfall 16: VAD edge cases — overlapping speech, long silence, environmental noise (P1 — voice UX)

**What goes wrong:**
Demo presenter is in a noisy room. Background noise (laptop fan, café chatter, "mhm" acknowledgments) trigger VAD, which trigger user-interruption frames, which interrupt Sonic mid-response. Bot gets stuck saying "I'm sorry, what was your—" repeatedly.

**Why it happens:**
Silero VAD is energy/model-based; it cannot distinguish "user wants to interrupt" from "user said mhm in agreement". Pipecat's interruption logic is binary — any VAD speech-start fires an `UserInterruptionFrame`. Confidence threshold is a single dial; doesn't cover all environments.

**How to avoid:**
- Tune `confidence` threshold up (0.7-0.8) for noisy environments; document as Pipecat env var.
- Tune `stop_secs` (silence before transitioning to QUIET) to 0.8s minimum to ignore brief sounds.
- Workshop demo recommendation: use a headset/lavalier mic for live demo, not laptop mic in conference room.
- Mention Pipecat Smart Turn v3 as "next step" in workshop summary chapter — out of v1 scope but worth noting for learners building production.

**Warning signs:**
- Bot frequently says "I'm sorry, can you repeat?"
- Bot interrupts itself within first second of response.
- VAD speech-start events logged in environments where speaker isn't talking.

**Phase to address:** Pipecat orchestrator phase (VAD tuning).

---

### Pitfall 17: Terraform state conflicts and re-apply pain for learners (P1 — workshop UX)

**What goes wrong:**
Learner runs `terraform apply` mid-tutorial, hits an error, fixes, re-runs. Bedrock KB resource is already half-created in AWS but Terraform state doesn't reflect it. Re-apply fails with `ResourceAlreadyExists`. Or two learners share the same backend bucket and trample each other's state.

**Why it happens:**
Bedrock Knowledge Base creation is multi-step (data source, vector store, KB itself, sync job). Terraform AWS provider's coverage of Bedrock KB has had rough edges and lifecycle/import issues. Local state is fragile across crashes.

**How to avoid:**
- Workshop default: local backend (no S3 backend). Each learner is isolated by their own laptop.
- Provide explicit `terraform import` recipes for the most likely half-created resources, in a "Recovery" appendix chapter.
- Make resource names include a random suffix (`random_id`) so retries can use a clean namespace if learner gets stuck.
- Document `terraform destroy` then re-`apply` as the simple recovery path for workshop scale (< $1 of recreate cost).

**Warning signs:**
- Apply error: `ResourceAlreadyExistsException` for a KB or data source.
- State out of sync: `terraform plan` shows resources to create that AWS console shows as existing.

**Phase to address:** Terraform infrastructure phase. Workshop docs need explicit recovery appendix.

---

### Pitfall 18: ACM certificate region mismatch (P1 — deployment)

**What goes wrong:**
If learner adds CloudFront in front of ALB (perhaps for v2 to reduce latency), they create an ACM cert in `ap-northeast-1` for the ALB. Then they try to use that same cert in CloudFront — CloudFront only accepts ACM certs from `us-east-1`. Deployment fails or cert is invalid.

**Why it happens:**
CloudFront is a global service that uses certs from us-east-1 only. ALB uses certs from its own region. Cross-region cert reuse not allowed for ALB-CloudFront pairing.

**How to avoid:**
- v1 scope: skip CloudFront. Document the gotcha as a "v2 heads-up" in the summary chapter.
- If CloudFront is later added, Terraform must use a `provider "aws"` aliased to `us-east-1` for CloudFront cert, separate from regional ALB cert.
- Workshop summary chapter explicitly warns: "If you add CloudFront in front of ALB later, ACM cert must be in us-east-1, not ap-northeast-1."

**Warning signs:**
- CloudFront distribution creation fails: `InvalidViewerCertificate: The specified SSL certificate doesn't exist...`.
- Terraform error: `acm_certificate must be in us-east-1 for CloudFront`.

**Phase to address:** Workshop summary chapter (out-of-v1-scope warning). Address in Terraform if CloudFront ever added.

---

### Pitfall 19: Workshop step-by-step drift from AWS console UI (P1 — workshop UX, ongoing)

**What goes wrong:**
Workshop publishes Oct 2026 with screenshots of "click Modify model access". By Feb 2027, AWS renames it "Manage model access" or moves it to a new tab. Learner can't follow steps. Workshop loses credibility.

**Why it happens:**
AWS console UI churns 2-4 times per year per service area. Bedrock UI is especially active. Static screenshots are fragile.

**How to avoid:**
- Prefer CLI / Terraform commands over console clicks wherever possible (CLI is more stable).
- For the unavoidable console steps (Bedrock model access — has no CLI shortcut for the EULA acceptance), include both screenshot AND a text description ("look for any link/button containing 'model access' under Configuration").
- Date-stamp screenshots: "As of November 2026 the button is labeled X. If you see Y instead, look for Z."
- Workshop CI: every 90 days, run a smoke test (Terraform apply + click-through) and update screenshots if drift detected. Issue template for "console UI changed" so learners can report.
- Pin AWS region in screenshots to ap-northeast-1 (the workshop's prod region) so learner sees same UI.

**Warning signs:**
- Issues filed: "step 3 says click X but I don't see X".
- Workshop completion rate drops over time.

**Phase to address:** Workshop ongoing maintenance — not a phase to "complete" but a process. Address in workshop docs phase by establishing the maintenance process.

---

### Pitfall 20: Cleanup chapter incomplete → learner billed for forgotten resources (P0 — workshop UX, financial)

**What goes wrong:**
Learner finishes workshop, runs `terraform destroy`. Terraform reports success. But: ECR images, CloudWatch log groups, Bedrock KB ingestion job artifacts in S3, NAT gateway elastic IPs, ACM certs — any of these can leak. A month later, learner gets a bill for $20-50 for a NAT gateway they didn't realize was still running. Worst-case: learner posts on Discord/Reddit "this workshop charged me $500" → reputational damage to AWS Cloud Clubs.

**Why it happens:**
Terraform only destroys what's in state. Resources created outside (manual S3 uploads to KB bucket, CloudWatch log groups created by ECS first-run, EIPs for NAT) often remain. Workshop authors test cleanup once at end of writing and assume done.

**How to avoid:**
- Cleanup chapter (Phần 4) is its own deliverable, NOT a footnote. It must include:
  1. `terraform destroy` (the obvious step)
  2. Explicit AWS console verification checklist with screenshots: ECS clusters, Bedrock KBs, S3 buckets (esp. KB data bucket), CloudWatch log groups, ECR repos, NAT gateways, EIPs, Route53 records.
  3. A `cleanup-verify.sh` script that uses AWS CLI to grep all the above and prints a "still alive" report.
  4. Cost Explorer screenshot showing how to verify zero ongoing cost.
- All Terraform-managed S3 buckets use `force_destroy = true` so destroy doesn't fail on residual objects.
- Workshop final page repeats: "Verify in Cost Explorer that your daily Bedrock + ECS + NAT cost is $0 the day after destroy."
- Workshop has automated test that runs apply→destroy→cost-check on its own AWS account weekly.

**Warning signs:**
- Cost Explorer shows ongoing charges 24h after `terraform destroy`.
- AWS Console shows resources tagged with workshop project tag still alive.

**Phase to address:** Workshop cleanup phase (Phần 4). MUST be tested end-to-end before workshop publishes. Has its own dedicated milestone.

---

### Pitfall 21: vi/en bilingual content drift (P1 — workshop UX)

**What goes wrong:**
Vietnamese version of a chapter updates with new screenshot, English version doesn't. Learner switches language mid-tutorial, sees different instructions. Or one language has a critical caveat, the other doesn't. Translation falls behind code.

**Why it happens:**
Two parallel content trees in `content/vi/` and `content/en/`. Maintaining both is double work. Authors typically update the language they're more comfortable in, defer the other.

**How to avoid:**
- Convention: source of truth is `content/en/`; `content/vi/` is the translation. PR cannot merge if `vi/` and `en/` for same path differ in structure (CI check on file count and frontmatter parity).
- Each chapter has a `lastTranslatedFrom` frontmatter field with the en commit hash; CI flags pages where en has been updated since that hash.
- Workshop layout shows "Translation status: out of date — read English for latest" banner when drift detected.
- Don't try to keep both perfect; prefer "English first, Vietnamese follows within 1 week" as documented policy.

**Warning signs:**
- Issue: "Vietnamese says X but English says Y, which is right?"
- Word count or section count diverges between language versions of same chapter.

**Phase to address:** Workshop docs infrastructure phase (CI checks) + ongoing.

---

### Pitfall 22: Code snippets that don't copy cleanly (P2 — workshop UX)

**What goes wrong:**
Learner copy-pastes a Terraform block from the workshop. Hugo theme's syntax highlighter inserted a non-breaking space, or the code block included line numbers that copied along, or a smart quote replaced a regular quote. `terraform plan` errors with cryptic message. Learner spends 30 minutes diffing.

**Why it happens:**
Hugo `chroma` syntax highlighter behavior varies. Markdown smart quotes can replace `"` in plain text contexts. "Copy" buttons in some themes copy the line numbers.

**How to avoid:**
- Hugo config: disable smart quotes for code (`enableEmoji = false`, `disableMarkdownify` for code). Use raw fenced code blocks.
- Test the "Copy" button manually for every code snippet on dev preview.
- For commands, prefer one-line that user can copy whole, not multi-line shell with `\` line continuations.
- For Terraform/Python files, link to the actual file in the repo instead of inlining; learner clones repo, reads file directly.

**Warning signs:**
- Tester reports "I copied this exactly and it doesn't work".
- Diff between expected and learner's pasted shows whitespace/quote differences.

**Phase to address:** Workshop docs phase (Hugo configuration + content writing).

---

### Pitfall 23: IAM wildcards as bad teaching example (P1 — security; workshop teaches a bad pattern)

**What goes wrong:**
Workshop, for simplicity, uses `Action: "*"` or `Resource: "*"` in IAM policies. Learner copy-pastes pattern into their day job. Now their company has a wildcard IAM policy in production because "the AWS workshop did it that way."

**Why it happens:**
Tutorials trade least-privilege for clarity. "Just to get it working" creep.

**How to avoid:**
- ZERO wildcards in any Terraform/CloudFormation in the workshop. Every action listed; every resource ARN scoped.
- Where wildcards seem unavoidable (e.g., listing all foundation models for the dropdown), explain why and suggest the production-correct alternative.
- Workshop has an explicit "anti-pattern" callout box pattern, used to warn about exactly this kind of teaching shortcut.

**Warning signs:**
- Code review shows `"*"` in Action or Resource.
- Workshop generates IAM policies the learner cannot explain line-by-line.

**Phase to address:** Terraform IAM module phase.

---

### Pitfall 24: Cold start on scale-out — first session after idle is slow (P2 — voice UX)

**What goes wrong:**
Workshop demo starts cold (no warm tasks). Presenter clicks "Record" — first response takes 8-12 seconds (Pipecat sequential init: VAD model load, Sonic auth, KB connection). Audience thinks "this is slow." Subsequent calls are fast (1-2s).

**Why it happens:**
Pipecat initializes TTS, LLM, STT, transport sequentially on first call. Silero VAD ONNX model load alone is ~2s. Sonic session establishment is ~1-2s. Bedrock KB first-call cold is ~1s. Stacked = 8-second user-visible cold start.

**How to avoid:**
- Keep at least 1 ECS task always warm (`desired_count = 1` minimum). Don't scale to zero.
- Pre-warm script as part of demo: hit the health endpoint, do a synthetic small Sonic call on container start, before accepting traffic.
- Demo script: presenter does one throwaway "hi" call before live audience watches, so the demo-call is warm.
- Workshop "Heads up": "Your first call after deployment will be slow. This is normal. Subsequent calls within 10 minutes are fast."

**Warning signs:**
- First demo call takes 8+ seconds; second takes <2s.
- CloudWatch shows long initialization time on task start.

**Phase to address:** Pipecat orchestrator phase + Terraform ECS service config.

---

### Pitfall 25: Twilio credentials accidentally committed when prepping for v2 (P0 — security)

**What goes wrong:**
v1 is web-only, but workshop author already started a v2 branch with Twilio integration. Twilio account SID + auth token committed to git in a config file. Branch pushed to public GitHub. Twilio credentials abused; bill spikes.

**Why it happens:**
v2 prep work happening in parallel with v1 stabilization. `.env.example` accidentally has real values. `.gitignore` doesn't catch the right pattern.

**How to avoid:**
- `.gitignore` includes `.env`, `.env.*`, `*.tfvars` (except `*.tfvars.example`), `terraform.tfstate*`, `secrets/`.
- Pre-commit hook (`gitleaks` or similar) scans for AWS keys, Twilio SIDs, generic high-entropy strings.
- Twilio creds (when v2 starts) MUST go in AWS Secrets Manager, referenced by ARN in Terraform — never in code.
- Rule: any `.env.example` file has placeholder values like `<YOUR_TWILIO_SID_HERE>`, never real values commented out.

**Warning signs:**
- gitleaks/trufflehog flags commit.
- Twilio billing spike for unknown SMS or voice usage.

**Phase to address:** Workshop docs infrastructure phase (CI/pre-commit hook). Critical before v2.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use ALB idle_timeout = 60s default | One less Terraform variable | Voice sessions die at every 60s of silence | NEVER for voice |
| IAM wildcards in workshop policies | Shorter, "cleaner" Terraform | Teaches anti-pattern; learner imports it to prod | NEVER |
| No CloudWatch log retention set | One line less Terraform | Logs grow forever; surprise bill | NEVER (always set 7d for workshop) |
| Public ALB without auth/rate limit | "Just works", anyone can demo | Bill bomb if URL leaks | Only for very short live demo with monitoring; tear down same day |
| Skip cleanup verification step | Workshop ships sooner | First learner who skims the cleanup chapter gets billed → reputation damage | NEVER for workshop |
| Local Terraform state | Simple, no S3 backend setup | Learner laptop crash = orphaned AWS resources | Acceptable for workshop only (single-user, recoverable) |
| Hardcode region "ap-northeast-1" everywhere | Less variable plumbing | Workshop only deployable to one region; learner from EU stuck | Acceptable for v1 if Terraform variable defaults to it but allows override |
| One Pipecat process per multiple sessions (not 1-per-1) | Lower Fargate cost | Memory leaks affect all sessions; one bad session OOMs all | Acceptable for workshop scale (low concurrency); call out in v1→prod section |
| Static screenshots of console UI | Workshop publishes faster | Drift within months | Acceptable if maintenance cadence is established |
| Skip Bedrock Guardrails | One less integration | PII captured in transcripts; no content moderation | Acceptable in v1 with documented "do not feed real PII" warning |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Bedrock Nova 2 Sonic | IAM grants `bedrock:InvokeModel` only | Grant `bedrock:InvokeModel` + `bedrock:InvokeModelWithResponseStream` + `bedrock:InvokeModelWithBidirectionalStream` on model ARN |
| Bedrock model access | Treat as IAM-only | Console enablement is separate; Phase 2 must include the click-through |
| Bedrock KB + S3 Vectors | Embed model dimensions chosen casually | Pin dimensions; document immutability; require destroy/recreate to change |
| Bedrock KB sync | Test retrieval immediately after sync | Wait 2-3 min after sync `Complete` for vector store propagation |
| Pipecat + Nova Sonic tool use | Nested/complex JSON schema parameters | Flat parameter shapes; test tool path standalone before integrating |
| ALB + WebSocket | Default `idle_timeout = 60s` | Raise to 3600s; add 25s app-level keepalive |
| ALB target group health check | Probe WebSocket endpoint | Add separate `GET /healthz` HTTP endpoint; configure ALB to use it |
| ECS Fargate + Bedrock | Private subnets without endpoint | Either public subnets with public IP, OR private + Interface VPC Endpoint for `bedrock-runtime` + S3 Gateway Endpoint |
| ECS task IAM | Wildcard or missing model ARN | Scope to `arn:aws:bedrock:<region>::foundation-model/amazon.nova-2-sonic-v1:0` |
| Browser microphone | HTTP endpoint or mixed content | HTTPS for page, `wss://` for WebSocket, derived from `window.location` |
| ACM cert | Reuse one cert for ALB and CloudFront | ALB cert in regional region; CloudFront cert in `us-east-1` (separate provider alias) |
| Terraform Bedrock KB | `terraform destroy` fails on non-empty S3 | Set `force_destroy = true` on KB data buckets |
| Twilio (v2 prep) | Creds in `.env.example` or code | AWS Secrets Manager + ARN reference + gitleaks pre-commit hook |
| CloudWatch logs | `retention_in_days` unset | Always set `retention_in_days = 7` for workshop |
| Pipecat version | Pin to "latest" | Pin to a known-good version verified on Linux Fargate (memory leaks land in patch releases) |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| ALB 60s idle drops | WebSocket close 1006 after silence | Raise to 3600s + 25s app keepalive | Any session with >60s of pure silence |
| 8-min Sonic session cap | `ModelTimeoutException` exactly at ~480s | Session rotation with conversation replay | Any single conversation longer than ~7 min |
| Pipecat memory growth | Task RSS climbs over hours | Pin known-good version; auto-scale on memory; restart task daily | Multi-session workshop demo with >2-3 concurrent users |
| Cold start 8s on first call | First call slow, subsequent fast | Keep min 1 task warm; pre-warm on startup; presenter does throwaway call | Every fresh deploy; every scale-from-zero |
| KB sync to query lag | "I just uploaded that doc, why doesn't it know?" | Explicit 2-3min wait step | Always; not a load-related break |
| VAD false-positive interruptions | Bot interrupts itself in noisy room | Tune confidence to 0.7-0.8; recommend headset mic | Any noisy environment (cafe, conference room) |
| NAT data transfer cost | Bill creep at $0.045/GB | VPC Endpoints for Bedrock + S3 Gateway endpoint, OR public subnets | Sustained Bedrock traffic at production scale |
| CloudWatch log volume | $30+/month line item from logs | `retention_in_days = 7`; INFO log level on Fargate | Any deployment running >2 weeks with default retention |
| Sonic concurrent session quota | Throttling under load | Default quotas are low (typically 5-10 concurrent for Sonic); request increase before workshop public launch | Workshop with >5 simultaneous users — won't matter for self-paced individual deploys |
| Pipecat aggregation_timeout 1s default | Universal +1s response delay | Override `aggregation_timeout=0` if STT-confidence-based EOT works for your model | Always — every response is 1s slower than it should be |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Public ALB endpoint without rate limit | Bill bomb / abuse via leaked URL | WAF rate limit (10/IP), shared API key on WS upgrade, AWS Budget $5/day alarm |
| IAM wildcards in workshop code | Teaches anti-pattern; learner imports to prod | Zero wildcards; every Action and Resource scoped; comment when scope is broader than ideal |
| PII in CloudWatch transcripts | Voice = sensitive content; logs unencrypted at field level | Log frame metadata only; CloudWatch data protection policy; Bedrock Guardrails for production add-on |
| Twilio creds in repo (v2 prep) | Account abuse, bill spike | Secrets Manager + ARN reference; gitleaks pre-commit hook; `.env.example` only with placeholders |
| Bedrock task role grants `bedrock:*` | Over-privileged service role | Scope to `InvokeModel*` actions on specific model ARN |
| KB data bucket public-readable | Catalog exposed publicly | Block-public-access default; explicit bucket policy denying public |
| WebSocket no origin check | CSRF / cross-origin abuse | Validate `Origin` header on WS upgrade against allowlist |
| API key check via query param | Key ends up in ALB access logs | Use header (e.g., `Authorization: Bearer`) instead; or use a short-lived signed-URL pattern |
| Workshop teaches `aws configure` with admin keys | Learner uses long-lived admin keys for everything | Workshop uses IAM Identity Center / SSO short-lived creds; if admin needed for setup, scope to setup phase only |
| Hardcoded account ID in Terraform | Workshop deploys to author's account if learner skims | Use `data "aws_caller_identity" "current"` ; never hardcode |

---

## UX Pitfalls

### Workshop learner UX

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| "Click here" without screenshot | Learner can't find the button | Every UI step has either a screenshot OR a CLI command (prefer CLI) |
| Single-line code that wraps in browser | Copy-paste includes broken wrapping | Use code blocks with horizontal scroll, never line-wrap |
| Screenshots without region indicator | Learner is in different region, sees different UI | Every screenshot's URL bar visible showing region |
| Smart quotes / non-breaking spaces in code | Pasted code doesn't run | Hugo config disables smart quotes in code blocks; manual copy-button test |
| Vague error advice ("try again") | Learner doesn't know what to fix | Each known error has a "if you see X, run Y" entry in troubleshooting appendix |
| No "where am I" indicator | Learner gets lost in long tutorial | Each step has clear "you should now have X resource" success criteria |
| Wait-time not called out | Learner thinks system is broken during 3-min sync | "This step takes 2-3 minutes, you should see Z while you wait" |
| Bilingual drift | Learner switches lang, sees different content | CI parity check + "translation out of date" banner |
| Cleanup is single sentence at the end | Learner skims, misses, gets billed | Cleanup is its own chapter with verification checklist + cost screenshot |
| No fallback if region unavailable | Learner is in EU, ap-northeast-1 latency feels slow | Document supported regions (us-east-1, us-west-2, ap-northeast-1, eu-north-1) and which to pick by location |

### End-user (voice agent) UX

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| 8-second cold start | User clicks Record, nothing happens for 8s, gives up | Keep min 1 warm task; show "connecting..." indicator; pre-warm on widget load |
| No visual indicator that bot is "thinking" | User repeats themselves, interrupts response | Widget shows VAD state (listening / thinking / speaking) clearly |
| Bot interrupts own response on cough/noise | Conversation feels broken | Tune VAD confidence higher; recommend headset; consider Smart Turn |
| Unclear how to stop | User can't end gracefully | Visible "End call" button that closes WebSocket cleanly, releases mic |
| Silence after tool call | Bot says "let me check" then nothing for 4s | Either: stream a filler ("looking that up…") or speed up KB query path |
| No transcript display | User wonders what bot heard | Optional toggle to show interim/final transcript text under widget |

---

## "Looks Done But Isn't" Checklist

- [ ] **Voice loop works in dev:** Often missing — has anyone tested it on Linux Fargate, not just macOS? Verify on actual ECS task, not local.
- [ ] **WebSocket connects:** Often missing — does it survive 90 seconds of silence? Test the 60s ALB cliff explicitly.
- [ ] **Tool call works:** Often missing — does the result get back into the conversation? Verify Sonic incorporates KB result into response, not just acknowledges call.
- [ ] **KB returns relevant docs:** Often missing — was the "wait 2-3 min after sync" actually waited? Re-test 5 minutes after sync completion.
- [ ] **Health check passes:** Often missing — is it on a real `/healthz` HTTP endpoint, or is ALB probing the WebSocket and tasks are flapping?
- [ ] **IAM is least-privilege:** Often missing — verify zero `*` in Action and Resource fields. Run `terraform plan -out` and grep `"\*"`.
- [ ] **CloudWatch retention set:** Often missing — verify all log groups have `retention_in_days` defined, none "Never".
- [ ] **`terraform destroy` actually destroys:** Often missing — run apply→destroy on a clean account; check Cost Explorer 24h later for $0.
- [ ] **Cleanup chapter verifiable:** Often missing — does the verification script actually catch leftover NAT? EIPs? Log groups?
- [ ] **vi/en parity:** Often missing — same step count, same screenshots, same code? CI check enforced.
- [ ] **Code snippets copy clean:** Often missing — manual test of every Copy button, paste into terminal, verify executes.
- [ ] **Workshop tested end-to-end on a fresh account:** Often missing — author's account has stale credentials/access; does a brand-new AWS account complete the workshop?
- [ ] **Cost ceiling validated:** Often missing — run workshop for full duration, check actual cost; document expected cost in workshop intro.
- [ ] **HTTPS works for widget:** Often missing — does the deployed widget actually unlock microphone? Test in incognito/fresh browser, not author's already-permitted browser.
- [ ] **First call cold start documented:** Often missing — does demo script account for 8s first-call lag, or will presenter look bad on stage?

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| ALB 60s timeout dropped session mid-conversation | LOW | Update Terraform `idle_timeout = 3600`, `terraform apply`, reconnect; existing sessions need browser refresh |
| Sonic 8-min `ModelTimeoutException` mid-call | LOW | Implement reconnect-with-context-replay in Pipecat; ship next deploy |
| Bedrock model access not enabled | LOW | Console → Bedrock → Model access → Modify → enable Nova 2 Sonic; wait ~1 min; retry |
| Wrong embedding model, KB index dim mismatch | MEDIUM | `terraform destroy` of KB+vector index, change `embedding_model_arn` var, `terraform apply`, re-sync. Cost: ~30 min + re-ingestion charges |
| KB synced but retrieval empty | LOW | Wait 3 minutes; if still empty, check `GetKnowledgeBaseDocuments` status; check embedding model access; check S3 doc readability |
| Pipecat OOM crashing tasks | LOW-MEDIUM | Rollback Pipecat version to last known good; increase task memory to 4GB; ECS will replace task automatically |
| Health check loop killing tasks | LOW | Add `/healthz` endpoint to Pipecat container; update Terraform target group; redeploy |
| Tool-use schema validation error | LOW-MEDIUM | Flatten parameter schema; remove nested objects/oneOf; test in isolation; redeploy |
| Public endpoint abused, bill spike | HIGH | Immediately delete ALB or Sonic IAM permission to halt charges; AWS Support → request bill credit citing learning workshop; add WAF + auth before redeploying |
| Mixed content blocking widget | LOW | Switch widget to derive `wss://` from `window.location.protocol`; add ACM cert + HTTPS listener if not present |
| `terraform apply` half-failed, dirty state | LOW-MEDIUM | `terraform destroy -auto-approve`; manually delete any AWS-side leftovers via console; `terraform apply` fresh |
| ECS Fargate can't reach Bedrock (private subnet, no endpoint) | LOW | Switch to public subnet + `assign_public_ip = true` for workshop OR add Interface VPC Endpoint for `bedrock-runtime` |
| Twilio creds leaked in v2 prep | HIGH | Rotate Twilio creds immediately; revoke old; force-push history rewrite (`git filter-repo`); audit Twilio billing for unauthorized use |
| Workshop learner billed for forgotten resources | MEDIUM | Update cleanup chapter; reach out to learner with manual cleanup steps; consider AWS billing credit request |
| Console UI drifted from screenshot | LOW | File workshop issue; update screenshot in next maintenance window; meanwhile add a "if UI looks different, find the page that does X" hint |
| vi/en drift detected | LOW | Translate the gap; CI check passes |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| #1 Sonic 8-min timeout | Pipecat orchestrator | Synthetic 10-minute conversation completes via session rotation |
| #2 ALB 60s idle | Terraform networking + ALB | Test: open WS, wait 90s silent, ping → still connected |
| #3 Model access not enabled | Workshop preparation (Phần 2) | Pre-flight CLI check passes; Terraform null_resource gate |
| #4 Audio sample rate | Web widget | Verify on dev: send 16kHz, expect coherent transcript; play 24kHz output, expect natural pace |
| #5 Health check on WS | Pipecat orchestrator + Terraform ALB | `curl /healthz` on ALB returns 200; ECS service stable for 24h |
| #6 IAM missing bidi action | Terraform IAM module | Synthetic Sonic invocation from task role succeeds |
| #7 No VPC egress | Terraform networking | First Bedrock call from task succeeds within 5s |
| #8 KB embedding dim lock | Knowledge Base + Terraform module | Variable documented as immutable; learner doesn't change mid-workshop |
| #9 KB sync delay | Knowledge Base phase | Workshop step explicitly says wait; verification one-liner provided |
| #10 HTTPS for mic | Web widget + Terraform ACM/ALB | Test in fresh browser: click Record, mic permission prompt appears |
| #11 Pipecat memory leak | Pipecat orchestrator + Terraform ECS sizing | Soak test: 5 concurrent sessions for 30 min, no OOM |
| #12 Tool-use schema | Pipecat orchestrator | Tool call → result → Sonic response includes KB content (verifiable in transcript) |
| #13 Public endpoint bill bomb | Terraform security + Pipecat throttling + workshop docs | WAF rule deployed; Budget alarm at $5/day; cleanup chapter explicit |
| #14 Logs retention | Terraform observability | All log groups have `retention_in_days = 7` |
| #15 PII in transcripts | Pipecat orchestrator + workshop docs | Log review shows only metadata, no transcript bodies |
| #16 VAD edge cases | Pipecat orchestrator | Demo with simulated background noise; bot doesn't self-interrupt within 1s |
| #17 Terraform state pain | Terraform infrastructure + workshop docs (recovery appendix) | Recovery appendix exists; tested with deliberate mid-apply abort |
| #18 ACM region mismatch | Workshop summary chapter (out-of-scope warning) | Documented in v2 heads-up section |
| #19 Console UI drift | Workshop docs ongoing maintenance | 90-day smoke test cadence established; issue template ready |
| #20 Cleanup incomplete | Workshop cleanup chapter (Phần 4) | Apply→destroy→24h cost check returns $0; cleanup-verify.sh ships |
| #21 vi/en drift | Workshop docs infrastructure | CI parity check on PRs; "translation out of date" banner working |
| #22 Code snippets copy issues | Workshop docs (Hugo config + content) | Manual Copy button test on every snippet on dev preview |
| #23 IAM wildcards | Terraform IAM module | grep `"\*"` in `*.tf` returns zero results in IAM Action/Resource |
| #24 Cold start | Pipecat orchestrator + Terraform ECS service | Demo script accounts for warm-up; min 1 warm task |
| #25 Twilio creds leak (v2 prep) | Workshop docs infrastructure (CI/pre-commit) | gitleaks/trufflehog runs on every PR; `.env.example` reviewed |

---

## Phase Ordering Implications

Synthesis of which pitfalls block which phases — informs roadmap sequencing:

- **Workshop preparation chapter (Phần 2) cannot wait until end** — Pitfalls #3 (model access), #10 (HTTPS), #18 (region) block every learner from step zero. Preparation must be the first ship-quality artifact.
- **Terraform networking + IAM phase must precede end-to-end testing** — Pitfalls #6, #7, #23. Without correct network + role, every other test fails.
- **ALB configuration is non-trivial and is shared across many pitfalls** — Pitfalls #2, #5, #10, #13. Treat ALB as its own milestone, not a sub-task.
- **Cleanup chapter is its own deliverable, not a footnote** — Pitfall #20 alone justifies a dedicated milestone.
- **Pipecat version pinning + sizing must be set early** — Pitfalls #11, #12, #16, #24 all relate. Don't churn versions mid-workshop development.
- **vi/en infrastructure must precede content writing at scale** — Pitfall #21. CI parity check has to exist before second-language content begins, otherwise drift accumulates.

---

## Sources

- AWS Bedrock — [Using the Bidirectional Streaming API](https://docs.aws.amazon.com/nova/latest/userguide/speech-bidirection.html) — HIGH confidence
- AWS Bedrock — [Nova 2 Sonic model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-2-sonic.html) — HIGH
- aws-samples/amazon-nova-samples issue #147 — ["I am getting a model timeout"](https://github.com/aws-samples/amazon-nova-samples/issues/147) — confirms ~8-minute session cap behavior — HIGH
- AWS Bedrock — [InvokeModelWithBidirectionalStream API reference](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_InvokeModelWithBidirectionalStream.html) — HIGH
- AWS Elastic Load Balancing — [Application Load Balancer target group health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html) — HIGH
- WebSocket.org — [AWS ALB: Config, Sticky Sessions & Scaling](https://websocket.org/guides/infrastructure/aws/alb/) — confirms 60s default and need for keepalive — HIGH
- WebSocket.org — [Fix WebSocket Timeout and Silent Dropped Connections](https://websocket.org/guides/troubleshooting/timeout/) — HIGH
- AWS Bedrock — [Request access to models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html) — HIGH
- AWS Bedrock — [Identity-based policy examples](https://docs.aws.amazon.com/bedrock/latest/userguide/security_iam_id-based-policy-examples.html) — HIGH
- AWS Bedrock — [Identity-based policy examples for Knowledge Bases](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base-setup.html) — HIGH
- AWS S3 — [Using S3 Vectors with Amazon Bedrock Knowledge Bases](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-bedrock-kb.html) — confirms dimension immutability — HIGH
- AWS Bedrock — [Sync your data with your Amazon Bedrock knowledge base](https://docs.aws.amazon.com/bedrock/latest/userguide/kb-data-source-sync-ingest.html) — HIGH
- AWS re:Post — [Why are documents added to a knowledge base not searchable even though their document status is reported as INDEXED?](https://repost.aws/questions/QUMzcw5_c0SwWsVurg1D55Og/why-are-documents-added-to-a-knowledge-base-not-searchable-even-though-their-document-status-is-reported-as-indexed) — confirms post-sync propagation lag — MEDIUM
- AWS Blog — [Building intelligent AI voice agents with Pipecat and Amazon Bedrock](https://aws.amazon.com/blogs/machine-learning/building-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock-part-1/) — HIGH
- Pipecat — [AWS Nova Sonic service docs](https://docs.pipecat.ai/server/services/s2s/aws) — HIGH
- Pipecat issue #2010 — ['call_function' attribute missing on AWSNovaSonicLLMService](https://github.com/pipecat-ai/pipecat/issues/2010) — confirms tool-use integration is fragile — MEDIUM
- Pipecat issue #1875 — [Lagging latency in AWS Nova Sonic example](https://github.com/pipecat-ai/pipecat/issues/1875) — MEDIUM
- Luong Hong Thuan — [Pipecat Voice Agent in Production: Complete Guide to Issues, Optimization & Scalable Architecture](https://luonghongthuan.com/en/blog/pipecat-voice-agent-production-scalable-guide/) — independent production guide cataloging memory leaks, aggregation timeout, cold start sequential init — MEDIUM
- Pipecat — [SileroVADAnalyzer docs](https://docs.pipecat.ai/server/utilities/audio/silero-vad-analyzer) — HIGH
- AWS — [Amazon Nova Sonic technical report](https://assets.amazon.science/86/bb/4316d28940bd9a719abb28f45aaf/amazon-nova-sonic-technical-report-and-model-card-6-12.pdf) — confirms 16kHz input / 24kHz output — HIGH
- MDN — [MediaDevices.getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia) — confirms HTTPS secure-context requirement — HIGH
- Vantage — [Save by Using Anything Other Than a NAT Gateway](https://www.vantage.sh/blog/nat-gateway-vpc-endpoint-savings) — HIGH
- Four Theorem — [The hidden costs of private AWS networks with Amazon ECS](https://fourtheorem.com/amazon-ecs-hidden-costs/) — MEDIUM
- AWS Blog — [Building cost-effective RAG applications with Amazon Bedrock Knowledge Bases and Amazon S3 Vectors](https://aws.amazon.com/blogs/machine-learning/building-cost-effective-rag-applications-with-amazon-bedrock-knowledge-bases-and-amazon-s3-vectors/) — HIGH
- Cloud Burn — [Amazon Bedrock Pricing: Token Rates Hide a $350/Month Trap](https://cloudburn.io/blog/amazon-bedrock-pricing) — confirms KB hidden ongoing cost surprises — MEDIUM
- AWS Blog — [Detect and protect sensitive data with Amazon Lex and Amazon CloudWatch Logs](https://aws.amazon.com/blogs/machine-learning/detect-and-protect-sensitive-data-with-amazon-lex-and-amazon-cloudwatch-logs/) — confirms CloudWatch transcript PII concern pattern — MEDIUM
- AWS Bedrock — [Remove PII from conversations by using sensitive information filters](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-sensitive-filters.html) — HIGH
- `raw_content.txt` (origin Vietnamese transcript) — recurrent presenter pain points: webhook config drift (lines 501-509, 1419-1505), agent first-call schema mismatch ("we predict the system will fail initially", lines 2342-2378), prompt override forgotten (lines 615, 1523-1543) — DIRECT EVIDENCE of patterns that will recur on AWS

---
*Pitfalls research for: Hera — AWS-native voice AI agent workshop & demo*
*Researched: 2026-05-04*
