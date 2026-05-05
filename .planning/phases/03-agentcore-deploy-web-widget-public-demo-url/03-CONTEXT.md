# Phase 3: AgentCore Deploy + Web Widget + Public Demo URL - Context

**Gathered:** 2026-05-05
**Status:** Ready for research and planning

<domain>
## Phase Boundary

Phase 3 lifts the Phase 2 multi-arch Pipecat container (`hera-agent`, `linux/arm64,linux/amd64`) onto Amazon Bedrock AgentCore Runtime in `ap-northeast-1`, exposes one public HTTPS WSS endpoint, and ships a polished web widget on S3 + CloudFront so that anyone with the demo URL can open a browser, click record, grant mic permission, and hold an end-to-end voice conversation that includes at least one KB-backed Apple product answer with audible response and live transcript. Day-one abuse rails (concurrency cap + banner cost notice) ride on the AgentCore resource itself; CloudWatch dashboards/alarms and the Lambda cost-circuit-breaker are explicitly Phase 4 territory.

In scope: AgentCore Runtime resource (CDK Python), AgentCore execution IAM role + attachment of existing `hera-kb-retrieve-prod` policy (TF), ECR repo + 3-step build/push/deploy pipeline (TF + bin scripts), CloudWatch log group for AgentCore (TF), S3 + CloudFront widget hosting module (TF), Apple-Store-light branded widget polish (5 record-button states, color-coded transcript, WID-06 error states), public demo banner with $5/day cost cap copy. Out of scope: CloudWatch dashboards/alarms (Phase 4 OBS-01..03), Lambda cost-circuit-breaker (Phase 4 OBS-05), `terraform destroy` cleanup verification script (Phase 4), workshop documentation chapters (Phase 5), custom domain + ACM cert for CloudFront (default `*.cloudfront.net` URL accepted v1).

</domain>

<decisions>
## Implementation Decisions

(Numbering continues from Phase 2 D-23. Phase 3 starts at D-24.)

### IaC split — Terraform + AWS CDK hybrid
- **D-24:** Phase 3 uses **hybrid Terraform + AWS CDK (Python)** per DEP-04. Terraform owns everything except the AgentCore Runtime resource itself; CDK owns one stack (`hera-agentcore`) containing only the AgentCore resource. Reasoning: research flagged Terraform 6.27 AgentCore-resource coverage as MEDIUM-LOW confidence (`research/SUMMARY.md` open question #1) — researcher must confirm; if native resource ships, planner may collapse to pure TF, but the design contract here is hybrid.
  - **Terraform owns:** ECR repo (`hera-agent` private repo with image scanning) + AgentCore execution IAM role (`hera-agentcore-exec-prod`) + `aws_iam_role_policy_attachment` of the existing `hera-kb-retrieve-prod` policy + bidi-stream + CloudWatch logs/metrics inline policy + CloudWatch log group (`/aws/bedrock-agentcore/hera-agent`) + S3 + CloudFront widget hosting module + the Phase 1 KB module (existing) + the Phase 2 `kb_consumer_policy` module (existing).
  - **CDK owns:** one Python stack `hera-agentcore` whose only responsibility is the AgentCore Runtime resource bound to the ECR image and the TF-created exec role. CDK reads `agentcore_role_arn`, `agentcore_log_group_arn`, and `image_uri` from terraform outputs (planner picks the bridge mechanism — likely `terraform output -json` piped into `cdk deploy --context-from-file` or SSM Parameter Store; the principle is "TF is the source of truth, CDK reads it"). Zero IAM in CDK — D-13 wildcards rule still applies.
  - **Cleanup contract:** `cdk destroy hera-agentcore` first (drops the AgentCore resource) → `terraform destroy` second (drops everything else). Documented in RUNBOOK and in Phase 4 cleanup-verify script.

### Deploy lifecycle — 3-step explicit sequence
- **D-25:** Update flow after first apply is **3 explicit paste-blocks**, not a 1-command wrapper and not CDK `DockerImageAsset`:
  1. `bin/build-push.sh` — `docker buildx build --platform linux/arm64,linux/amd64 --push -t ${ECR_URL}:${GIT_SHA} -t ${ECR_URL}:latest ./agent` (image tag is the short git SHA so AgentCore replaces deterministically when source changes).
  2. `cdk deploy hera-agentcore --context image_tag=${GIT_SHA}` — replaces AgentCore resource to point at the new image.
  3. `bin/deploy-widget.sh` — sed-replaces the AgentCore endpoint URL into `frontend/app.js`, `aws s3 sync` to the S3 bucket, then `aws cloudfront create-invalidation` for the JS path.
  Reasoning: workshop FCJ pattern is paste-style; each step has 1 clear job; debug is easier when each step's exit code surfaces independently. CDK `DockerImageAsset` was rejected because it would hide the multi-arch buildx flags Phase 2 spent debugging into a CDK construct.

### Widget hosting — S3 + CloudFront
- **D-26:** Widget HTML/JS hosts on **S3 (private bucket, OAI/OAC) + CloudFront distribution** in `ap-northeast-1` per WID-01 / DEM-01. AWS-native chosen over GitHub Pages because the workshop teaches "static site on AWS" as part of the deliverable; GitHub Pages would skip that lesson and add cross-origin complexity (different domain class). Default CloudFront domain (`*.cloudfront.net`) accepted for v1 — custom domain + ACM cert deferred (no Route53 / DNS work in v1 scope). New Terraform module `infra/modules/widget_hosting/` ships: S3 bucket (versioning enabled for rollback, public access blocked, OAC origin), CloudFront distribution (HTTPS-only, default root object `index.html`, error responses for 404→index.html), and the OAC bucket policy. ACM cert deferred because default CloudFront cert covers `*.cloudfront.net`.

### Endpoint URL injection — build-time sed-replace
- **D-27:** Widget knows the AgentCore WSS URL via **build-time sed-replace into `frontend/app.js`**, not runtime fetch and not query string. `bin/deploy-widget.sh` reads `terraform output -raw agentcore_wss_url`, runs `sed -i "s|__AGENTCORE_WSS_URL__|${AGENTCORE_WSS_URL}|g" frontend/app.js`, then `aws s3 sync` and CloudFront invalidation. Existing `frontend/app.js:12` constant `WS_URL = "ws://localhost:8080/ws"` becomes `WS_URL = "__AGENTCORE_WSS_URL__"` with a default-fallback for local dev (the deploy script never touches the local-dev source path; sed runs on a build copy if needed — planner picks). Reasoning: simplest possible, no runtime config-fetch round trip, no error path for missing config.json, FCJ paste-friendly.
  - **Local dev unchanged:** `docker compose up` continues to work against `ws://localhost:8080/ws`. The sed-replace targets only the deploy artifact, not the working tree (planner: copy `frontend/` to `dist/widget/` first, sed there).

### Widget UX polish — Apple-Store light branding
- **D-28:** Polish target is **Apple-Store light branding**, not minimal-debug and not full-instructor-theme. Keep current vanilla HTML/JS/CSS shape (no React, no framework, no build step beyond sed-replace). Add:
  - Apple-style logo (small, top-left) + neutral background (`#f5f5f7`, white card).
  - Record button with **5 distinct visual states**: idle (white) / connecting (yellow pulse) / listening (red recording badge) / speaking (blue speaker icon) / error (red border + retry text).
  - Transcript pane with color-coded speakers — User (blue) and Agent (grey) — and timestamps; auto-scroll on new message.
  - Human-readable error messages for every WID-06 case: mic permission denied ("Allow microphone access in your browser to start"), WS connect failure ("Couldn't reach the agent — check your connection and retry"), agent timeout ("The agent didn't respond in time — try again"), mic muted indicator (always-on visual when track muted).
  - Banner copy at the top: "Instructor demo. Daily cost capped at $5/day. For your own deployment, follow the workshop." (DEM-03 + D-29).
  - **NOT included:** modal onboarding, FAQ inline, waveform visualizer, sound-effect cues. These are scope creep for v1.
  - **UI-SPEC.md will be generated by `/gsd-ui-phase 3` next** — exact copy, color palette tokens, accessibility notes (WCAG AA contrast, focus rings, ARIA roles for status pill), responsive breakpoints. Planner reads UI-SPEC.md as contract.

### Daily cost cap on banner — $5/day fixed
- **D-29:** Banner cost-cap copy is **$5/day, hardcoded** — not a Terraform variable, not a config.json value. Aligns with OBS-03 default ("default $5/ngày cho v1") and PROJECT.md billing alarm baseline. Hardcoded because (a) the number is a single constant that changes only when the project's cost philosophy changes, (b) parameterising adds sed-replace complexity for zero practical benefit, and (c) Phase 4's actual billing alarm enforces the cap — the banner is a user-facing notice, not a mechanism. If a future instructor wants a different cap, they edit one line in `frontend/index.html` and re-deploy.

### Day-1 throttling — 2 concurrent, no per-IP
- **D-30:** AgentCore Runtime resource is created with **max 2 concurrent sessions, no per-IP rate limit**. Rationale: instructor-demo scope only needs 1-2 simultaneous users (instructor + 1 viewer); abuse from a leaked URL is bounded by the 2-session ceiling regardless of IP. AgentCore default per-IP behavior (researcher to confirm exact default) is sufficient. Sonic's 8-min stream cap (Phase 2 D-19, AGT-05) is the natural max session length — no separate enforcement needed. Phase 4 layers CloudWatch billing alarm + Lambda cost-circuit-breaker (OBS-03, OBS-05) on top of this baseline; Phase 3 ships only the static AgentCore concurrency setting.

### Locked decisions carried forward (NOT re-litigated here)
- **From Phase 1 (D-01..D-16):** zero IAM wildcards (D-13), region default `ap-northeast-1` override `us-east-1` (D-14), terraform `~> 6.27` primary, Terraform fixed names no `random_id` suffix (D-12), recovery path `terraform destroy && apply`.
- **From Phase 2 (D-17..D-23):** WebSocket transport not WebRTC (D-19, "Phase 3 inherits this choice"), single FastAPI app with `/ping` + `/ws` on port 8080 matching AgentCore HTTP service contract, AWSNovaSonicLLMService receives explicit static creds from `os.environ` (Phase 2 research correction #3), Pipecat 1.1.0 + Python 3.12 + `aws-nova-sonic` extra, `lookup_product` tool contract verbatim (D-18), in-memory session state (D-21), `kb_retrieve_policy_arn` exists in TF outputs and **MUST be attached** to the new AgentCore exec role (D-22 resolves here), multi-arch container image (`linux/arm64,linux/amd64`) is the same artifact pushed to ECR — no second build path (D-20).

### Claude's discretion (planner / executor decides)
- Exact CDK Python project layout (`cdk/` at repo root vs nested under `infra/`) — planner picks based on simplest cross-tool wiring.
- Mechanism by which CDK reads TF outputs (SSM Parameter vs `terraform output -json` piped to cdk context vs Boto3 lookup at synth) — planner picks lowest-friction option after researcher verifies what works.
- Image tag scheme details (git SHA short vs full vs semver) — `git rev-parse --short HEAD` is fine; planner can override.
- ECR lifecycle policy (keep last N images for retention) — planner sets a sensible default (e.g., 5 most recent untagged + all tagged), not asked.
- CloudFront cache behaviors / TTLs / compression — planner picks defaults appropriate for static-site-with-changing-config.
- Whether to add a `Strict-Transport-Security` header on CloudFront — yes by default (HTTPS-only is required for `getUserMedia` anyway).
- Per-state record-button CSS specifics — UI-SPEC.md will define; planner reads UI-SPEC.md.
- Exact AgentCore concurrency knob name and value (D-30 says "2 concurrent" — researcher resolves the actual config field name).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level mandates
- `.planning/PROJECT.md` — core value, locked stack, key decisions table, scope rules
- `.planning/REQUIREMENTS.md` — Phase 3 requirement IDs DEP-01..06, WID-01..06, DEM-01..03 (15 total)
- `.planning/ROADMAP.md` — Phase 3 goal + 5 success criteria (lines 76-88)
- `CLAUDE.md` / `AGENTS.md` — no emojis, uv only, root-cause debugging, no defensive try/except, concise docstrings

### Cross-phase research (open questions to resolve)
- `.planning/research/SUMMARY.md` — open questions #1-#7 (Terraform AgentCore support, pricing model, exact deploy steps, concurrency quotas, WebRTC vs WebSocket, KB tool helper, static widget hosting). Phase 3 researcher MUST resolve #1, #3, #4, #6 at minimum.
- `.planning/research/STACK.md` / `FEATURES.md` / `ARCHITECTURE.md` / `PITFALLS.md` — original research; AgentCore-pivot annotations live in SUMMARY.md.

### Prior phase decisions (carry-forward)
- `.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md` — D-12 (fixed names, no random_id), D-13 (zero IAM wildcards), D-14 (region defaults).
- `.planning/phases/01-knowledge-base-foundation/01-VERIFICATION.md` — live KB id `BKXE19AH89`, ARN, account 851725411875.
- `.planning/phases/02-pipecat-voice-agent-local/02-CONTEXT.md` — D-19 transport WSS locked, D-20 container shape, D-21 in-memory state, D-22 consumer policy ships ready-to-attach (resolves here).
- `.planning/phases/02-pipecat-voice-agent-local/02-RESEARCH.md` — FastAPI `/ping` + `/ws` shape, AgentCore HTTP service contract, multi-arch buildx pattern, ARM64-only AgentCore Runtime requirement.
- `.planning/phases/02-pipecat-voice-agent-local/02-VERIFICATION.md` — proof Phase 2 ROADMAP success criteria met (8/8 AGT, AGT-04 latency gate live).
- `.planning/phases/02-pipecat-voice-agent-local/02-REVIEW.md` + `02-REVIEW-FIX.md` — closed: WR-02 (WS open await), WR-03 (anti-alias LPF), IN-05 (playbackCtx cleanup). Frontend code is now stable baseline for Phase 3 polish.

### Existing assets to extend
- `agent/Dockerfile` — multi-arch, `0.10.8-python3.12-trixie-slim`, ARM64-ready. Phase 3 builds + pushes this image to ECR.
- `agent/hera_agent/main.py` — FastAPI app with `/ping` (UTC boot time) + `/ws`. AgentCore service contract already satisfied.
- `agent/hera_agent/pipeline.py` — Pipecat pipeline with `RawPCMSerializer`, `cancel_on_interruption=False` for KB tool. No code changes expected in Phase 3 unless researcher finds AgentCore-specific tweaks.
- `agent/hera_agent/config.py` — env var contract (`HERA_KB_ID`, `HERA_KB_SCORE_THRESHOLD`, `AWS_REGION`, `HERA_VOICE`). AgentCore env injection wires these.
- `frontend/index.html`, `frontend/app.js`, `frontend/audio-capture-worklet.js` — debug-grade widget; Phase 3 polishes per D-28 / UI-SPEC.md.
- `infra/envs/prod/main.tf` — TF root that adds Phase 3 modules.
- `infra/envs/prod/outputs.tf` — Phase 3 adds: `agentcore_wss_url`, `ecr_repo_url`, `agentcore_role_arn`, `agentcore_log_group_arn`, `widget_cloudfront_url`, `widget_s3_bucket_name`.
- `infra/modules/kb_consumer_policy/` — existing, exports `policy_arn`. Phase 3 attaches via `aws_iam_role_policy_attachment` on the new exec role.
- `infra/modules/knowledge_base/` — existing, exports `kb_arn`, `kb_id`, `data_source_id`, `source_bucket_name`. No changes.
- `RUNBOOK.md` — extend with new sections: "Phase 3: AgentCore deploy" (TF apply order, CDK install + deploy, build-push commands), "Widget deploy", "Update flow", "Cleanup order (CDK first, then TF)".
- `bin/verify-kb.sh` — existing reference for paste-style command pattern.
- `bin/run-agent-docker.sh` / `bin/run-agent-local.sh` / `bin/smoke-voice.sh` — Phase 3 adds `bin/build-push.sh`, `bin/deploy-widget.sh`, and `bin/deploy-agentcore.sh` (the CDK wrapper). Same pattern (`set -euo pipefail`, `command -v` preflight checks, `||` exit-code capture per WR-01 fix).

### External references
- AWS blog: [Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/) — primary AgentCore + Pipecat blueprint.
- Reference repo: [aws-samples/sample-nova-sonic-websocket-agentcore](https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore) — proves WSS + AgentCore + tool use; researcher mines for exact deploy commands and CDK shape.
- AWS docs: AgentCore Runtime HTTP service contract (`/ping` JSON shape) — already satisfied by `agent/hera_agent/main.py`.
- AWS docs: Bedrock model access enablement — Nova 2 Sonic + AgentCore must be enabled in `ap-northeast-1` (account-level gate; documented in workshop Phase 5 too).
- AWS CDK Python docs: `cdk deploy --context` flag, cross-stack imports.
- Terraform AWS provider `~> 6.27`: `aws_ecr_repository`, `aws_iam_role`, `aws_s3_bucket`, `aws_cloudfront_distribution` resources.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`agent/Dockerfile`** — multi-arch ready, pinned to `ghcr.io/astral-sh/uv:0.10.8-python3.12-trixie-slim`. Phase 3 reuses verbatim; no Dockerfile edits expected.
- **`agent/hera_agent/main.py`** — `/ping` already returns `{"status": "Healthy", "time_of_last_update": <utc int>}` matching AgentCore service contract; `/ws` already on port 8080. Zero refactor needed at agent boundary.
- **`infra/modules/knowledge_base/`** — exports `kb_arn`, `kb_id`. Phase 3 doesn't touch the module; only adds new modules alongside it.
- **`infra/modules/kb_consumer_policy/`** — exports `policy_arn`. Phase 3 attaches it via `aws_iam_role_policy_attachment` on the new AgentCore exec role (resolves Phase 2 D-22 deferral).
- **`infra/envs/prod/outputs.tf`** — pattern for adding new outputs already established (`kb_id`, `kb_arn`, `kb_retrieve_policy_arn`, etc.). Phase 3 follows the same shape.
- **`frontend/`** — vanilla HTML/JS/CSS, no framework, no build step. Polish in place; sed-replace pattern works because there are no source maps / bundlers.
- **`RUNBOOK.md`** — paste-style operational sections established. Phase 3 extends, doesn't rewrite.
- **`bin/*.sh`** — `set -euo pipefail`, `command -v jq` / `command -v aws` preflight, `|| EXIT_CODE=$?` capture pattern (WR-01 lesson). Phase 3 new scripts inherit this.

### Established Patterns
- **TF root + thin module** (Phase 1 D-08 single-module shape): `infra/envs/prod/main.tf` is thin; modules under `infra/modules/<name>/` follow `versions.tf / variables.tf / main.tf / outputs.tf` four-file shape. Phase 3 adds `agentcore_iam`, `widget_hosting`, `ecr` modules in the same shape.
- **Zero IAM wildcards** (D-13): every Action and Resource is explicitly typed. Phase 3 AgentCore exec role policy: `bedrock:InvokeModelWithBidirectionalStream` scoped to the Nova 2 Sonic model ARN, `bedrock:Retrieve` already scoped via the attached `hera-kb-retrieve-prod` policy, CloudWatch logs/metrics scoped to the Phase 3 log group ARN.
- **Confused-deputy mitigation** (Phase 1): trust policy on AgentCore exec role uses `bedrock-agentcore.amazonaws.com` (or whatever the AgentCore service principal is — researcher confirms) with `aws:SourceAccount` + `aws:SourceArn` conditions where applicable.
- **Region variable** (D-14): default `ap-northeast-1`, override `us-east-1`. New Phase 3 modules accept `var.region` and pass through; CDK stack reads same region from terraform output / context.
- **Atomic conventional commits** scoped to plan id: e.g., `feat(03-01): add ECR repo module`. Phase 3 follows this for executor.
- **Paste-style RUNBOOK + bin scripts**: Phase 3 deliverable includes Phase 3-specific sections in RUNBOOK and 3 new bin scripts (`build-push.sh`, `deploy-widget.sh`, `deploy-agentcore.sh` wrapping `cdk deploy`). Each script idempotent enough to re-run.
- **No defensive try/except** (AGENTS.md): Phase 2 baseline is clean (only `except WebSocketDisconnect: pass` in `/ws` handler). Phase 3 introduces no new try/except except for ECR login retry boundary if needed (planner justifies).

### Integration Points
- **TF → CDK bridge:** `terraform output -json` → file → `cdk deploy --context-from-file` (planner picks exact mechanism). All cross-tool data flows TF → CDK, never the reverse.
- **Container → AgentCore:** image URI in ECR (`<account>.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent:<git_sha>`) is the contract; CDK reads via cdk context; AgentCore replaces resource on image_uri change.
- **Widget → AgentCore:** WSS URL injected into `frontend/app.js` at deploy time via sed-replace from `terraform output -raw agentcore_wss_url`. CORS configured on AgentCore endpoint (researcher confirms how) to allow CloudFront origin.
- **AgentCore exec role → KB:** `aws_iam_role_policy_attachment.exec_kb_retrieve` attaches existing `module.kb_consumer_policy.policy_arn` (Phase 2 deferral closes here).
- **Phase 2 image artifact → Phase 3 ECR:** same `agent/Dockerfile`, same `docker buildx --platform linux/arm64,linux/amd64`, retagged for ECR repo.
- **Phase 4 hand-off:** Phase 3 leaves a CloudWatch log group with named ARN, AgentCore endpoint ARN, IAM exec role ARN — Phase 4 will hang dashboards/alarms/Lambda circuit breaker off these.
- **Phase 5 hand-off:** Phase 3 deliverables (live AgentCore endpoint, widget URL, RUNBOOK sections) become the screenshot/snippet/verification source for Phần 3.3 + 3.4 + 3.5 (DOC-05, DOC-06).

</code_context>

<specifics>
## Specific Ideas

- **CDK stack name:** `hera-agentcore` (single stack, single resource — keep CloudFormation small).
- **ECR repo name:** `hera-agent` (matches container image name; one repo per app).
- **AgentCore exec role name:** `hera-agentcore-exec-prod` (D-12 fixed name, `prod` suffix matches Phase 1+2 naming).
- **CloudWatch log group:** `/aws/bedrock-agentcore/hera-agent` (AWS-conventional path).
- **S3 widget bucket:** `hera-widget-prod` (D-12 fixed name).
- **CloudFront distribution comment:** `hera widget instructor demo` for AWS console clarity.
- **Banner copy verbatim (DEM-03):** "Instructor demo. Daily cost capped at $5/day. For your own deployment, follow the workshop." — workshop link points to the GitHub Pages site once Phase 5 ships.
- **Record button label per state:** idle = "Record", connecting = "Connecting...", listening = "Recording (click to stop)" (kept from Phase 2), speaking = "Agent speaking", error = "Retry".
- **Transcript color tokens:** User = `#0071e3` (Apple blue), Agent = `#6e6e73` (Apple grey). UI-SPEC.md may refine.

</specifics>

<deferred>
## Deferred Ideas

(Items raised or implied during discussion that belong outside Phase 3 scope.)

- **Custom domain + ACM cert for CloudFront** — defer to v2 / instructor preference. Default `*.cloudfront.net` URL accepted. Adding a real domain pulls in Route53, ACM in `us-east-1` (CloudFront cert region), DNS validation flow — non-trivial scope. Capture for v2 backlog if instructor wants `demo.hera.example.com`.
- **WebRTC transport** — Phase 2 D-19 already locked WSS; AgentCore WebRTC announcement (March 2026) is documented in PROJECT.md but Pipecat WebRTC support for AgentCore endpoint is unverified. Re-evaluate in v2 once Pipecat ships explicit AgentCore-WebRTC integration.
- **Pipecat client SDK + RTVI protocol in browser** — Phase 2 research deferred this; same call holds for Phase 3 (vanilla AudioWorklet + plain WS proven, RTVI adds bundler complexity for transcript events that we already get via control text frames).
- **Modal onboarding / FAQ inline / waveform visualizer** — D-28 explicitly excludes; could be v2 polish if user feedback says the demo feels too bare.
- **Cost circuit-breaker Lambda** (OBS-05) — Phase 4 owns. Phase 3 sets static AgentCore concurrency cap only.
- **CloudWatch dashboards / billing alarm wiring** (OBS-01..03) — Phase 4 owns. Phase 3 ensures the log group + ARNs exist for Phase 4 to hang resources off.
- **`cleanup-verify.sh` cleanup script** (Phase 4 success criterion #4) — Phase 4 owns. Phase 3 RUNBOOK documents cleanup ORDER (CDK destroy first, TF destroy second) but does not ship the verification script.
- **Per-instructor cost-cap config** — D-29 hardcoded to $5/day; if a future instructor needs a different value they edit `frontend/index.html` and re-deploy. Parameterising via TF variable was rejected to avoid sed-replace complexity.
- **GitHub Pages widget host** — rejected in favor of S3+CloudFront (D-26) so workshop teaches AWS-native static hosting. Capture if the instructor reverses for cost reasons (though S3+CloudFront is well within free tier for instructor demo traffic).

</deferred>

<success_signals>
## What Success Looks Like (for downstream agents)

When research and planning complete, the executor should be able to produce a Phase 3 deliverable that satisfies all 5 ROADMAP success criteria:

1. Container deployed to AgentCore Runtime in `ap-northeast-1` via Terraform `~> 6.27` (KB/IAM/ECR/log group/widget infra) + AWS CDK Python (AgentCore Runtime resource only) per D-24. Hybrid IaC fallback flavor locked: TF + CDK. Pure TF allowed if researcher confirms native resource exists.
2. Public HTTPS demo URL on `*.cloudfront.net` opens, mic permission grants, WSS to AgentCore endpoint connects, voice loop with at least one KB-backed answer ("Do you have MacBook Pro?" → audible Apple Store reply) plays through speakers, transcript visible.
3. Every WID-06 error case has a human-readable message in the widget UI (mic permission denied, WS connect fail, agent timeout, mic muted indicator). Widget shows 5 distinct record-button states (idle/connecting/listening/speaking/error) with visual differentiation.
4. AgentCore exec role least-privilege: explicit Action `bedrock:InvokeModelWithBidirectionalStream` (model ARN), `bedrock:Retrieve` (via attached `hera-kb-retrieve-prod` policy), CloudWatch `logs:CreateLogStream` + `logs:PutLogEvents` scoped to the Phase 3 log group ARN. Zero wildcards. Region default `ap-northeast-1`, override variable for `us-east-1`.
5. Public banner displays "Instructor demo. Daily cost capped at $5/day. For your own deployment, follow the workshop." (DEM-03 verbatim; D-29).

Plus implicit must-haves:
- AgentCore Runtime resource configured with max 2 concurrent sessions (D-30).
- 3-step deploy contract documented in RUNBOOK: `bin/build-push.sh` → `cdk deploy hera-agentcore` → `bin/deploy-widget.sh` (D-25).
- `kb_retrieve_policy_arn` Phase 2 output is attached to AgentCore exec role (Phase 2 D-22 closes here).
- UI-SPEC.md generated by `/gsd-ui-phase 3` becomes the design contract; planner reads it before writing PLAN.md.

</success_signals>

---

*Phase: 03-AgentCore Deploy + Web Widget + Public Demo URL*
*Context gathered: 2026-05-05*
