---
phase: 03-agentcore-deploy-web-widget-public-demo-url
verified: 2026-05-06T08:00:00Z
status: human_needed
score: 4/5 success criteria closed; 1 deferred (SC#2 protocol bridge -> Phase 4)
overrides_applied: 0
gaps:
  - truth: "User opens public HTTPS demo URL, clicks record, grants mic, holds end-to-end voice conversation with at least one KB-backed product answer + audible response + live transcript visible (SC#2)"
    status: failed
    reason: "Container starts cleanly on AgentCore Runtime version=2 (Plan 03-05 credential bridge fix proven by local docker run + curl /ping=200 with no env vars set; AgentCore data-plane reaches container; 424->404 transition is the smoking gun). However, the FastAPI app exposes only GET /ping + WebSocket /ws while AgentCore Runtime ProtocolConfiguration=HTTP invokes the container at POST /invocations per Bedrock convention. Browser-driven voice loop cannot complete because the AgentCore HTTP protocol layer 404s before any Pipecat frames flow."
    artifacts:
      - path: "agent/hera_agent/main.py"
        issue: "Exposes /ping + /ws but NOT /invocations. AgentCore HTTP protocol routes to /invocations per Bedrock BYOC convention."
      - path: "infra/cdk/hera_agentcore/stack.py:86"
        issue: "ProtocolConfiguration=HTTP selects the /invocations bridge contract; CFn schema has no enum for raw WSS routing."
    missing:
      - "POST /invocations endpoint on the FastAPI app that bridges AgentCore HTTP request envelopes to the existing Pipecat WebSocket pipeline (or a sidecar proxy that translates between the two)."
      - "Phase 4 follow-up plan: 04-XX-agent-protocol-bridge. Reference: awslabs/agentcore-samples/.../06-bi-directional-streaming/04-pipecat-sonic-ws."
deferred:
  - truth: "Live browser voice loop end-to-end (SC#2)"
    addressed_in: "Phase 4 (Wave-1 priority) — `04-XX-agent-protocol-bridge`"
    evidence: "ROADMAP.md Phase 4 section: 'NEW Wave-1 priority: ship the agent protocol-bridge follow-up plan (suggested 04-XX-agent-protocol-bridge) that closes Phase 3 SC#2 by exposing POST /invocations per AgentCore HTTP protocol contract.' STATE.md Pending Todos and Blockers/Concerns sections corroborate the deferral with user-approved Q1+Q2 cost-conscious closure (2026-05-06)."
human_verification:
  - test: "Browser-driven voice loop on https://dg0w939ktclw6.cloudfront.net/"
    expected: "Click Record -> grant mic -> ask 'Do you have MacBook Pro?' -> hear Apple Store assistant reply with KB-backed answer in <3s p95 -> see color-coded transcript with User/Agent lines."
    why_human: "Live voice quality, mic permission UX, real-time playback, KB retrieval semantic correctness, and audible Sonic output cannot be programmatically asserted. ALSO: this test is currently EXPECTED TO FAIL with HTTP 404 from the protocol-bridge gap above; the human verification will only succeed after the Phase 4 protocol-bridge plan ships."
  - test: "Visual inspection of the polished widget on https://dg0w939ktclw6.cloudfront.net/"
    expected: "Apple-Store light palette renders; banner with $5/day cost-cap copy visible at top with 4px accent left bar; 5-state record button visually distinct (idle white, connecting yellow pulse, listening red, speaking blue, error red border); transcript pane uses monospace; status pill shows lower-case state labels; mobile breakpoint (<720px) collapses correctly."
    why_human: "Visual rendering, color contrast in real browser, and animation behavior need a human eye. Automated verifier checks for token presence (verified) but cannot judge whether the page LOOKS right."
  - test: "WID-06 error states render the verbatim copy when triggers fire"
    expected: "Block mic permission -> 'Allow microphone access in your browser to start.' Drop network -> 'Couldn't reach the agent — check your connection and retry.' Stay silent for 30s -> 'The agent didn't respond in time — try again.' Mute mic mid-session -> 'Microphone is muted — unmute to continue.' Open over http:// -> 'Microphone needs HTTPS...'"
    why_human: "Trigger events (network drop, mic mute, no audio for 30s) are external to the page and cannot be programmatically simulated without instrumenting the browser. Code paths verified present in app.js with correct verbatim strings; runtime behavior needs human."
---

# Phase 3: AgentCore Deploy + Web Widget + Public Demo URL — Verification Report

**Phase Goal:** Anyone with the public instructor URL can open a browser, click a record button, and have a working voice conversation with the Apple Store agent running on Amazon Bedrock AgentCore Runtime — no installation, no login, just a headset and a microphone.

**Verified:** 2026-05-06T08:00:00Z
**Status:** human_needed (4/5 SC closed; SC#2 deferred to Phase 4 with documented protocol-bridge gap; all closed SC need human visual/voice verification)
**Re-verification:** No — initial verification

---

## 1. Phase Goal Verification

**Verdict: PASS-WITH-DEFERRAL.**

The phase goal is the headline user-facing promise: "click record, talk to the agent". As of 2026-05-06 that round-trip is **not yet end-to-end live** — AgentCore data-plane reaches the container but returns HTTP 404 because the FastAPI app does not expose `POST /invocations` per AgentCore HTTP protocol contract.

What was DELIVERED (and is verifiable in the codebase right now):

- The full IaC substrate for AgentCore Runtime, ECR, widget hosting, IAM, log group, and the Lambda presigner auth bridge — Terraform + CDK Python in the repo, applied live at least once (per SUMMARY claims).
- The polished web widget (Apple-Store light, 5 button states, all 5 WID-06 verbatim error strings, 30s heartbeat, presign-then-WSS connection flow).
- The pipeline-as-code for repeating the deploy (push-image.sh, build-widget.sh, smoke-deploy.sh, RUNBOOK 4-step lifecycle).
- The agent credential bridge fix (lazy-default config, boto3 default chain in build_llm(), Dockerfile ENV bake-in) — container survives cold-start under AgentCore IMDSv2 conditions.

What was NOT yet delivered (with documented hand-off):

- The actual user-facing voice conversation. SC#2 sits behind one remaining architectural gap: the FastAPI entry point shape does not match AgentCore's HTTP protocol contract. STATE.md, ROADMAP.md, and 03-05-SUMMARY.md all explicitly track this as the Phase 4 Wave-1 priority `04-XX-agent-protocol-bridge`.

This is honest progress. ~3 hours wall-clock across 5 plans + ~30 commits + multiple live AWS deploys advanced infra/auth/credential layers materially. But the headline promise of Phase 3 (a learner clicks Record and talks to the agent) is not closed. Verifier reports SC#2 as DEFERRED, not COVERED, and will not whitewash that.

---

## 2. Success Criteria Matrix

| # | Success Criterion | Verdict | Evidence |
|---|-------------------|---------|----------|
| SC#1 | Pipecat container deployed to Bedrock AgentCore Runtime in `ap-northeast-1` with working WSS endpoint, exposed via Terraform `~> 6.27` (or hybrid TF + CDK fallback). | **COVERED** | TF modules `infra/modules/agentcore_iam/` + `infra/modules/ecr/` + `infra/modules/widget_hosting/` (versions.tf pin `aws ~> 6.27`). CDK Python stack `infra/cdk/hera_agentcore/stack.py` deploys `aws_cdk.aws_bedrockagentcore.CfnRuntime` (D-24 hybrid honored). Live runtime claimed `hera_agent-GIsf2P4ImD` status=READY version=2 (per 03-05 SUMMARY; not re-verified live per cost constraint). The "WSS endpoint" piece is bridged via the Lambda presigner — see SC#2 row for the open routing gap. |
| SC#2 | User opens public HTTPS demo URL on desktop browser → record → mic permission → end-to-end voice conversation with KB-backed answer + audible audio + live transcript. | **DEFERRED** | Container cold-starts cleanly (Plan 03-05 fix verified locally `docker run` + `curl /ping`=200 with no env vars). Presign+WSS handshake reaches AgentCore data-plane (424→404 transition documented in 03-05-SUMMARY). FastAPI exposes only `/ping` + `/ws` — AgentCore Runtime ProtocolConfiguration=HTTP routes to `POST /invocations`. Phase 4 follow-up plan `04-XX-agent-protocol-bridge` owns the close. |
| SC#3 | Error states visible and self-explanatory (mic permission denied, WS connect failure, agent timeout, mic muted) — display human-readable messages. | **COVERED** | `frontend/app.js:111-119` defines `WID06` constant with all 5 error strings verbatim from UI-SPEC. App wires `getUserMedia` rejection (line 336), ws.onerror + ws.onclose code!=1000 (lines 200-211), 30s heartbeat fail() (lines 132-138), MediaStreamTrack mute event (lines 256-263), getUserMedia-unsupported probe (lines 297-301). All wire to `fail()`/`appendLine("error", ...)` rendering paths. CSS `frontend/styles.css:127-132` renders the `.mic-muted-label`. (Live trigger-driven UX needs human verification — see human_verification[2].) |
| SC#4 | AgentCore exec role least-privilege (`bedrock:InvokeModelWithBidirectionalStream`, `bedrock:Retrieve`, scoped CloudWatch logs/metrics — zero wildcards). Region defaults to `ap-northeast-1` with `us-east-1` override. | **COVERED** | `infra/modules/agentcore_iam/main.tf` — single inline policy with explicit Action lists: `bedrock:InvokeModelWithBidirectionalStream` scoped to `var.sonic_model_arn` (line 60-61), CloudWatch logs scoped to log group ARN (lines 91-103), `bedrock:Retrieve` via attached managed policy `kb_retrieve_policy_arn` (lines 132-135). Two documented Resource=* exceptions: `cloudwatch:PutMetricData` (gated by namespace condition, line 110-121) and `ecr:GetAuthorizationToken` (no resource-level scoping per AWS IAM model, line 72-77). `infra/envs/prod/variables.tf:1-5` defaults `region=ap-northeast-1`, type=string (override-able, DEP-06 honored). |
| SC#5 | Public demo banner: instructor demo, daily cost capped, learners follow workshop. | **COVERED** | `frontend/index.html:10-12` renders the banner with verbatim DEM-03 copy: "Instructor demo. Daily cost capped at $5/day. For your own deployment, follow the workshop." Workshop link is an `aria-disabled="true"` placeholder per UI-SPEC (Phase 5 will fill the href). `frontend/styles.css:43-50` renders the 4px accent left-border stripe per UI-SPEC §Color "Accent reserved for" item 3. |

**Score:** 4 COVERED / 1 DEFERRED. Deferred item is documented in ROADMAP Phase 4 section + STATE.md Pending Todos + 03-05-SUMMARY.

---

## 3. REQ-ID Coverage Table

| Req ID | Description | Verdict | Evidence (file:line or path) |
|--------|-------------|---------|------------------------------|
| **DEP-01** | Agent container deploy to Bedrock AgentCore Runtime in ap-northeast-1 | PARTIAL | `infra/cdk/hera_agentcore/stack.py:72-88` instantiates `CfnRuntime` with `network_mode=PUBLIC`, `protocol_configuration=HTTP`, container_uri composed from `ecr_repo_url:image_tag`. Live runtime `hera_agent-GIsf2P4ImD` status=READY (per 03-05-SUMMARY; not re-verified live). Container reaches "started" state; the application route (/invocations) gap is SC#2. |
| **DEP-02** | AgentCore endpoint exposed (WSS) — pattern based on Pipecat support | PARTIAL | WSS data-plane URL constructed in `infra/cdk/hera_agentcore/stack.py:100-109`. Browser auth bridge: `infra/modules/widget_presigner/main.tf` Lambda Function URL signs SigV4 presigned WSS URLs (TTL=300s, see `src/handler.py:32`). End-to-end WSS handshake reaches container per 03-04-SUMMARY (auth proven before 404 layer). |
| **DEP-03** | Terraform modules deploy fresh AWS account with `terraform init && apply` | COVERED | `infra/modules/{agentcore_iam,widget_hosting,ecr,widget_presigner}/` each have versions.tf (aws ~> 6.27) + variables.tf + main.tf + outputs.tf. `infra/envs/prod/main.tf` instantiates them. `bin/push-image.sh` + `bin/build-widget.sh` + `bin/smoke-deploy.sh` form the rest of the pipeline-as-code path. |
| **DEP-04** | Hybrid Terraform + CDK/CLI fallback documented for AgentCore | COVERED | D-24 split honored: `infra/modules/*` is Terraform; `infra/cdk/hera_agentcore/stack.py` is the ONLY CDK stack and contains ONLY the AgentCore Runtime resource (verified by inspection — single `CfnRuntime` resource, no IAM/log/ECR resources in CDK). RUNBOOK.md:339+ documents the 4-step lifecycle including the second-pass terraform apply (D-25 amended). |
| **DEP-05** | AgentCore exec role least-privilege | COVERED | `infra/modules/agentcore_iam/main.tf` — see SC#4 row above. Zero unscoped wildcards in Action; 2 documented Resource=* exceptions both with AWS-mandated rationale + namespace/scope conditions where applicable. |
| **DEP-06** | Region var default ap-northeast-1, override us-east-1 for dev | COVERED | `infra/envs/prod/variables.tf:1-5`: `variable "region" { default = "ap-northeast-1" }`. All Phase 3 modules accept `var.region` and pass through; CDK reads `AWS_REGION` env var (`infra/cdk/app.py:55`) defaulting to ap-northeast-1. |
| **WID-01** | Trang HTML/JS tối giản, host được trên S3+CloudFront hoặc GitHub Pages | COVERED | `frontend/{index.html, styles.css, app.js, audio-capture-worklet.js}` — vanilla, no framework, no build step beyond sed-replace. `infra/modules/widget_hosting/main.tf` ships private S3 + CloudFront + OAC (verified). `bin/build-widget.sh` is the deploy script. |
| **WID-02** | Nút record dùng getUserMedia + AudioWorklet 16 kHz Int16 mono | COVERED | `frontend/app.js:250` calls `navigator.mediaDevices.getUserMedia({audio: ...})`. AudioWorklet path preserved verbatim from Phase 2 baseline (`frontend/audio-capture-worklet.js` byte-for-byte unchanged per 03-02-SUMMARY claim — last touched commit 109c686 from Phase 2). |
| **WID-03** | Audio gửi qua binary WS frames, không base64 | COVERED | `frontend/app.js:183` sets `ws.binaryType = "arraybuffer"`. `frontend/app.js:274` ships raw `ws.send(e.data)` where `e.data` is the ArrayBuffer from the AudioWorklet `port.onmessage` (NOT a JSON-wrapped or base64 string). |
| **WID-04** | Audio response 24kHz PCM playback queue, no lag | COVERED | `frontend/app.js:185` constructs `playbackCtx = new AudioContext({ sampleRate: 24000 })`. Lines 224-240 decode Int16 → Float32, build AudioBuffer @ 24kHz, sequential schedule via `nextStart` (Phase 2 path preserved). |
| **WID-05** | Transcript text song song với audio | COVERED | `frontend/app.js:98-109` `appendLine()` builds `<span class="line-{kind}">` per UI-SPEC line format. CSS `frontend/styles.css:152-155` colors per kind (User accent, Agent text-secondary, System text-muted, Error destructive). Auto-scroll on append (line 108). |
| **WID-06** | Error states visible | COVERED | See SC#3 row. All 5 verbatim copy + all 5 trigger events present in app.js. (Live trigger UX = human verification.) |
| **DEM-01** | Public HTTPS demo URL accessible from internet, ACM cert valid | COVERED | `infra/modules/widget_hosting/main.tf:99-101`: `cloudfront_default_certificate = true` + `viewer_protocol_policy = "redirect-to-https"`. Output `widget_cloudfront_url = https://dg0w939ktclw6.cloudfront.net` per 03-01 live capture. (Note: TLSv1.2_2021 minimum silently downgrades to TLSv1 on default cert — documented in 03-01-SUMMARY; client reach maximization, not regression.) |
| **DEM-02** | Anonymous access — no login, throttling/rate limit | PARTIAL | Anonymous: `infra/modules/widget_presigner/main.tf:144`: `authorization_type = "NONE"` on the Function URL. Rate-limit: per-IP rate limit + per-Lambda concurrency cap deferred to Phase 4 OBS-04/OBS-05 per user-approved Q2 (i) on 2026-05-06; `reserved_concurrent_executions = -1` default (per `variables.tf:47`) due to account-floor constraint. AgentCore service-quota request (D-30 concurrency=2) is operational AWS console action, not IaC. CORS origin pinned to CloudFront URL (`main.tf:147` `allow_origins = [var.cors_allow_origin]`). |
| **DEM-03** | Banner instructor demo + daily cap + workshop pointer | COVERED | See SC#5. Verbatim copy in `frontend/index.html:11`. |

**Coverage:** 12 COVERED / 3 PARTIAL / 0 MISSING. PARTIAL items: DEP-01 + DEP-02 (waiting on SC#2 protocol-bridge close); DEM-02 (rate-limit deferred to Phase 4 per Q2 (i)).

**Orphaned check:** No requirement IDs from REQUIREMENTS.md Phase 3 list (DEP-01..06, WID-01..06, DEM-01..03 = 15 reqs) are missing from plan declarations — every Phase 3 req has at least one plan claiming it.

---

## 4. Cross-Cutting Constraints

| Constraint | Verdict | Evidence |
|------------|---------|----------|
| **No emojis (CLAUDE.md mandate)** | COVERED | Grep sweep with `[\x{1F300}-\x{1FAFF}]|[\x{2600}-\x{27BF}]` regex across `frontend/`, `bin/`, `infra/`, `agent/` returns ZERO matches. Em-dash characters (—) in UI-SPEC error strings are typography, not emojis (verified verbatim in app.js:114-118). |
| **uv-only Python (no pip install, no python3 X)** | COVERED | Grep for `pip install` and `python3 ` across `bin/` + `*.py` returns nothing. Dockerfile uses `uv sync --frozen --no-install-project` (line 23-26, 32-33). CDK uses `uv run cdk deploy ...` (RUNBOOK.md:405, smoke-deploy.sh:47). |
| **Zero IAM wildcards (D-13)** | COVERED | Grep `"\*"` across `infra/**/*.tf`: exactly 2 hits in `agentcore_iam/main.tf` (line 76 = `ecr:GetAuthorizationToken` Resource=*; line 114 = `cloudwatch:PutMetricData` Resource=*). Both are AWS-mandated documented exceptions with leading comment blocks explaining the IAM-model constraint and namespace/action scoping. No Action=* anywhere. |
| **Region default ap-northeast-1 with us-east-1 override (DEP-06)** | COVERED | `infra/envs/prod/variables.tf:1-5` sets default. Modules accept `var.region` pass-through; CDK reads from `os.environ["AWS_REGION"]` or default. |
| **Pitfall B credential pattern (post-03-05 fix)** | COVERED | `agent/hera_agent/pipeline.py:44-71` `build_llm()` calls `boto3.Session().get_credentials().get_frozen_credentials()` per-connection (NOT at module import — supports rotated IMDS creds), passes static kwargs. `agent/Dockerfile:44-45` bakes `ENV HERA_KB_ID=BKXE19AH89` + `ENV AWS_REGION=ap-northeast-1` (only non-secret config; AWS creds still come from env or IMDSv2 per the docstring). `agent/hera_agent/config.py:15-24` lazy `os.environ.get(KEY, default)`. |
| **No defensive try/except (AGENTS.md root-cause discipline)** | COVERED | Only try/except in agent code is `WebSocketDisconnect` (main.py:46) which is the normal disconnect path, and `NoCredentialsError` raised explicitly in pipeline.py:55-56 (defensive raise, not swallow). No new try/except introduced in Phase 3. |
| **Pipecat /ping + /ws shape preserved** | COVERED | `agent/hera_agent/main.py:27-47` keeps both routes. (NOTE: this is exactly what the SC#2 protocol-bridge gap is about — AgentCore wants /invocations on top of these.) |

---

## 5. Locked Decisions Honored

| Decision | Verdict | Evidence |
|----------|---------|----------|
| **D-22** — Attach hera-kb-retrieve-prod policy to AgentCore exec role | COVERED | `infra/modules/agentcore_iam/main.tf:130-135`: `aws_iam_role_policy_attachment.kb_retrieve` with `policy_arn = var.kb_retrieve_policy_arn`. `infra/envs/prod/main.tf:37` passes `module.kb_consumer_policy.policy_arn`. Live verification: 03-01-SUMMARY records `aws iam list-attached-role-policies` returns the kb_retrieve policy. |
| **D-24** — TF source-of-truth, CDK owns only AgentCore Runtime | COVERED | `infra/cdk/hera_agentcore/stack.py:72-88` declares ONE `CfnRuntime` resource; no IAM/log/ECR/S3/CloudFront resources in CDK. Lambda presigner is `infra/modules/widget_presigner/` Terraform (Rule-4 deviation honors D-24). |
| **D-25** (amended) — 4-step lifecycle (terraform apply → push-image → cdk deploy → second-pass terraform apply → build-widget → smoke) | COVERED | RUNBOOK.md:339-485 documents exactly this 4-step (technically 6 paste-blocks counting smoke). `bin/smoke-deploy.sh` is the 8-step orchestrator. The second-pass apply is at RUNBOOK Step 3.5 and smoke-deploy.sh:62-66. |
| **D-26** — S3 force_destroy + git rollback (no versioning v1) | COVERED | `infra/modules/widget_hosting/main.tf:18`: `force_destroy = true`. Leading comment block (lines 12-14) documents the trade-off and Phase 4 revisit window. No `aws_s3_bucket_versioning` resource present. |
| **D-28** — 5 error strings verbatim from UI-SPEC | COVERED | `frontend/app.js:111-119` `WID06` constant has all 5 strings verbatim including em-dashes. UI-SPEC §Error state copy line-for-line match. |
| **D-30** — Concurrency cap deferred (Q2 (i) approved) | COVERED | `infra/modules/widget_presigner/variables.tf:44-48`: `reserved_concurrent_executions` default `-1`. `infra/cdk/hera_agentcore/stack.py:20-26` documents in stack docstring: "AWS::BedrockAgentCore::Runtime CFn schema confirmed live to have NO MaxConcurrentSessions / Throttle / SessionLimit property — concurrency is enforced at the AgentCore SERVICE quota layer." Phase 4 OBS-04/OBS-05 owns the rate-limit + cost-circuit-breaker work. |

---

## 6. Rule-4 Deviation: Lambda Presigner

**Recorded?** Yes — comprehensively, in 03-04-SUMMARY "Deviations from Plan (auto-fixed during execution)" §Rule-4 architectural additions, ROADMAP Phase 3 line 96, STATE.md `Plan 03-04` and `Plan 03-04 Q1 user-approved` decision logs.

**Module exists?** Yes — `infra/modules/widget_presigner/` ships:
- `versions.tf` (provider pin)
- `variables.tf` (`agentcore_runtime_arn`, `cors_allow_origin`, `presign_ttl_seconds` capped <=300, `reserved_concurrent_executions` default -1)
- `main.tf` (Lambda + Function URL + IAM role + inline policy + log group, 154 lines)
- `outputs.tf` (`presign_url` + `function_name`/`function_arn`/`role_arn`)
- `src/handler.py` (96 lines; `SigV4QueryAuth` from botocore signs URL with TTL=300s)

**CORS scoped to CloudFront URL?** Yes — `infra/modules/widget_presigner/main.tf:147`: `allow_origins = [var.cors_allow_origin]` and `infra/envs/prod/main.tf:53` passes `module.widget_hosting.cloudfront_url` (NOT `*`).

**IAM scoped to specific runtime ARN?** Yes — `infra/modules/widget_presigner/main.tf:63-75` policy_document has `bedrock-agentcore:InvokeAgentRuntime` + `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream` Resource = `local.invoke_resource` (the runtime ARN, no wildcards beyond the unavoidable `${arn}/*` qualifier path scope at line 73).

**TTL <=300s enforced?** Yes — `variables.tf:38-41` validation block: `condition = var.presign_ttl_seconds > 0 && var.presign_ttl_seconds <= 300`.

**AuthType=NONE flagged as threat?** Yes — 03-04-SUMMARY lists `threat_flag: anonymous-public-lambda` with mitigations (CORS pinned, 300s TTL, zero-wildcard IAM, deferred per-IP rate-limit to Phase 4 OBS-04/OBS-05).

**Followup required:** Phase 4 OBS-04 (per-IP rate limit on presign Function URL) + Phase 4 OBS-05 (Lambda cost circuit-breaker on billing alarm) — both tracked in STATE.md "Deferred Items" table.

---

## 7. Open Items / Gaps Surfaced

1. **Phase 3 SC#2 protocol-bridge gap → Phase 4 follow-up plan `04-XX-agent-protocol-bridge`.** The headline goal is incomplete. Container starts cleanly under AgentCore IMDSv2 (Plan 03-05 fix proven by `docker run` + `curl /ping`=200 with no env vars). AgentCore data-plane reaches the container (424→404 transition is the smoking gun). FastAPI `/ping` + `/ws` does not match AgentCore HTTP protocol's `POST /invocations` route. ROADMAP Phase 4 section + STATE.md Blockers/Concerns + 03-05-SUMMARY "Discovered During This Plan" all document the deferral with rationale (Q1 + Q2 user-approved on 2026-05-06; Hera is a learning demo, not production; running another billable smoke just to confirm a known failure burns budget). **This is the single biggest open item; the verifier reports it as DEFERRED, not COVERED.**

2. **D-30 concurrency cap enforcement → Phase 4 OBS-04/OBS-05.** The CFn schema for `AWS::BedrockAgentCore::Runtime` has NO `MaxConcurrentSessions`/`Throttle`/`SessionLimit` property (live-introspected by Plan 03-04). D-30's "max 2 concurrent sessions" becomes an operational AWS Service Quota request, not IaC. Per-Lambda concurrency cap on the presigner (Q2 (i) deferred) and per-IP rate limit are tracked in STATE.md Deferred Items.

3. **Bulk delete-time risk on `force_destroy=true` widget bucket (D-26 acknowledged trade-off).** `infra/modules/widget_hosting/main.tf:18` documents the trade-off in a leading comment block; Phase 4 cleanup-verify decides whether to add versioning. No exposure today (widget S3 holds 4 static files; rollback is git + bin/build-widget.sh).

4. **Sonic foundation-model ARN runtime gate carried since Plan 03-01.** `arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.nova-sonic-v1:0` accepted by IAM-policy create (which validates ARN syntax, not model existence). Runtime InvokeModelWithBidirectionalStream is the actual gate; it has not been exercised end-to-end because the protocol-bridge gap blocks the container from reaching the LLM init step. Will close as part of the Phase 4 protocol-bridge plan smoke.

5. **CDK bootstrap deploy-role trust policy for non-root operators.** Current credentials run as IAM root which CDK warns about; deploys still succeed. Phase 4 may add a role-trust amendment.

6. **Live AWS state preserved.** Per Q1+Q2 cost-conscious closure, NO teardown was performed at end of Plan 03-05. Phase 4 protocol-bridge can apply its fix in place without re-creation cost. Live ARNs: AgentCore Runtime `hera_agent-GIsf2P4ImD` v=2 status=READY, image `hera-agent:5f21e36`, presign Function URL `https://ijrovzxz4tts2tdo2w5yxqxho40fruyn.lambda-url.ap-northeast-1.on.aws/`, widget `https://dg0w939ktclw6.cloudfront.net/`.

---

## 8. Final Verdict

**4 of 5 success criteria CLOSED in code; SC#2 (live browser voice loop) DEFERRED to Phase 4 protocol-bridge follow-up plan with full documentation in ROADMAP/STATE/SUMMARY.** The infrastructure layer (TF + CDK), auth bridge layer (Lambda presigner), credential layer (Plan 03-05 fix), widget UX layer (5-state machine + WID-06 verbatim copy), and pipeline-as-code layer (push-image, build-widget, smoke-deploy, RUNBOOK 4-step) are all delivered and code-verifiable. The headline user-facing promise — "click record, talk to the agent" — is NOT yet end-to-end live; Phase 4 Wave-1 plan `04-XX-agent-protocol-bridge` owns the close. Honest scope: Phase 3 should NOT be marked "complete on goal"; it should be marked "5/5 plans shipped, SC#2 deferred to Phase 4". That matches ROADMAP/STATE/SUMMARY narrative exactly — no whitewashing in either direction.

**Recommended next step:** Run `/gsd-plan-phase 4` to plan Phase 4 with `04-XX-agent-protocol-bridge` as the Wave-1 priority. The protocol-bridge plan should mine `awslabs/agentcore-samples/.../06-bi-directional-streaming/04-pipecat-sonic-ws` for the canonical Pipecat-on-AgentCore bidi-streaming pattern, ship a `POST /invocations` endpoint (or sidecar bridge), and verify with one `bin/smoke-deploy.sh` run + browser approval against the existing live runtime — that closes Phase 3 SC#2 and unblocks Phase 4 OBS work.

---

_Verified: 2026-05-06T08:00:00Z_
_Verifier: Claude (gsd-verifier)_
