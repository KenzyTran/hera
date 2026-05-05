# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-04)

**Core value:** A Cloud Clubs learner walks the workshop and successfully deploys a voice chatbot in their own AWS account, talking to it through their browser.
**Current focus:** Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL — UI-SPEC approved; planning next.

## Current Position

Phase: 3 of 5 (AgentCore Deploy + Web Widget + Public Demo URL) — UI-SPEC approved
Plan: 0 of TBD. CONTEXT.md ships D-24..D-30 (IaC split TF+CDK hybrid; 3-step deploy; S3+CloudFront widget; Apple-Store light polish; $5/day cap; 2-concurrent throttling). UI-SPEC.md (commit a71b70a) locks the design contract — Apple-Store light palette (`#0071e3` accent, `#f5f5f7` background, `#e74c3c` destructive), 4 type sizes / 2 weights / system fonts, 4/8/16/24/32/48 spacing scale (+56px button-height exception), 5-state record button, color-coded transcript, all 5 WID-06 error strings, instructor-demo banner verbatim, zero registries (vanilla HTML/CSS/JS — no npm, no CDN). Researcher and planner have not yet run.
Status: `/gsd:ui-phase 3` complete (commit a71b70a). UI-checker APPROVED 6 dimensions (1 non-blocking FLAG on Dim 2 Visuals — focal point implicit, recommend explicit declaration in planning). `/gsd:discuss-phase 3` complete earlier (commit 5c0f31b). 4 gray areas resolved with 8 single-question turns: (1) DEP-04 IaC fallback flavor → TF + AWS CDK Python (TF owns everything except the AgentCore Runtime resource; CDK owns one stack `hera-agentcore`); (2) WID-01 / DEM-01 hosting → S3 + CloudFront with default `*.cloudfront.net` URL; build-time sed-replace injects the AgentCore WSS URL into `frontend/app.js`; (3) WID polish → Apple-Store light branding (5 record-button states, color-coded transcript, human-readable WID-06 errors); (4) DEM-02 / DEM-03 → $5/day banner copy hardcoded, AgentCore concurrency capped at 2, no per-IP. Phase 4 will own CloudWatch alarms + Lambda cost-circuit-breaker. Phase 2 D-22 closes in Phase 3 (managed policy `hera-kb-retrieve-prod` attaches to the new AgentCore exec role). Next: `/gsd-plan-phase 3`.
Last activity: 2026-05-05 — `/gsd:ui-phase 3` produced `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-UI-SPEC.md` (commit a71b70a). UI-researcher pre-populated 11 decisions from CONTEXT.md (palette, button states, banner copy, error messages, transcript colors, exclusions), 3 from Phase 2 frontend baseline, 6 from REQUIREMENTS.md WID-01..06 / DEM-03, 1 from CLAUDE.md no-emojis mandate; 0 user prompts. UI-checker passed 5/6 dimensions; Dim 2 Visuals flagged for non-blocking enhancement (declare record button as explicit focal point in planning).

Progress: [████████████████░░░░] 40%

## Performance Metrics

**Velocity:**
- Total plans completed: 6
- Average duration: ~27 min
- Total execution time: ~2.65 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Knowledge Base Foundation | 3/3 | ~69 min | ~23 min |
| 2. Pipecat Voice Agent (Local) | 3/3 | ~90 min | ~30 min |
| 3. AgentCore Deploy + Web Widget + Public Demo URL | 0/TBD | — | — |
| 4. Observability, Cost Control, Cleanup | 0/TBD | — | — |
| 5. Workshop Documentation (vi/en) | 0/TBD | — | — |

**Recent Trend:**
- Last 6 plans: 01-02 (~14 min, 3 tasks, 11 files — network-error resume), 01-03 (~50 min, 5 tasks, 2 deliverables + 3 deviation-fix iterations against live AWS), 02-01 (~5 min, 3 tasks, 16 files, 0 deviations — pure greenfield Python with mocked boto3), 02-03 (~7 min, 3 tasks, 7 files, 0 auto-fix deviations — IaC plan against live AWS), 02-02 (~78 min, 5 tasks, 12 files, 4 auto-fix deviations — container + frontend + live Bedrock Nova 2 Sonic AGT-04 gate against KB BKXE19AH89; ~21 min spent on cold Pipecat ML deps download in Docker build, ~30 min on Plan-02-01 latent-issue debugging via live Sonic introspection)
- Trend: live-AWS audio-loop plans cost the most wall-clock (78 min) because the loop spans Docker build + WS transport + Pipecat pipeline + bidi stream to Sonic + tool execution against KB - debugging requires running each layer end-to-end. Plan 02-02 surfaced two latent Plan-02-01 issues (missing serializer; greet-kickoff race) that unit tests with MagicMock could not catch. The smoke-gate-as-acceptance pattern is what made these visible: AGT-04 gate refused to pass without root-causing the underlying audio-flow break.

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- Initialization: Compute pivoted from ECS Fargate to Amazon Bedrock AgentCore Runtime (managed; no ALB/VPC/NAT/PrivateLink in scope).
- Initialization: Vector store is S3 Vectors (cost-driven over OpenSearch Serverless).
- Initialization: IaC is Terraform `~> 6.27` primary; hybrid Terraform + CDK/CLI fallback for AgentCore if provider has gaps — decision locks in Phase 3 planning.
- Initialization: Region is `ap-northeast-1` prod / `us-east-1` dev.
- Initialization: Workshop docs trail system implementation — Phase 5 follows Phases 1-4 because docs need real screenshots and verified snippets.
- Plan 01-01: Stock data inlined in each SKU markdown file (D-03), not in a shared stock.md, so retrieval chunks always co-locate stock numbers with the SKU name.
- Plan 01-01: RUNBOOK.md authored as a stub with seven `TODO(plan-03)` markers; the Next steps (deferred) section is fully written and locks in D-10 (Phase 2 consumer role), D-11 (remote backend deferred), and Guardrails as out-of-v1.
- Plan 01-01: `.terraform.lock.hcl` is intentionally NOT in `.gitignore` (commit the lock for reproducibility); `terraform.tfvars` is also NOT ignored because Phase 1 has no secrets.
- Plan 01-02: Single-module shape (D-08) — one `infra/modules/knowledge_base/` module instantiated by a thin `infra/envs/prod/` root. No per-resource sub-modules; multi-module factoring deferred until a second consumer exists.
- Plan 01-02: Provider pinned to `hashicorp/aws ~> 6.27` (resolved 6.43.0 in lockfile) — the floor for native `s3_vectors_storage_configuration` on `aws_bedrockagent_knowledge_base`.
- Plan 01-02: Zero wildcards in any IAM Action or Resource (D-13) — verified by Python regex sweep across `infra/**/*.tf`. Trust policy uses `bedrock.amazonaws.com` (NOT `bedrockagent.amazonaws.com` — Pitfall I) with both `aws:SourceAccount` and `AWS:SourceArn` confused-deputy conditions.
- Plan 01-02: Provider quirks honored verbatim — `aws_s3vectors_index` uses lowercase `float32`/`cosine`; `aws_bedrockagent_knowledge_base` uses UPPERCASE `FLOAT32`; `aws_s3vectors_vector_bucket` uses `vector_bucket_name` (not `name`).
- Plan 01-02: `aws_bedrockagent_knowledge_base.depends_on = [aws_iam_role_policy.kb_inline]` is mandatory (KB validates role permissions at create time — RESEARCH.md Pattern 5).
- Plan 01-02: No `aws_s3_object` and no `null_resource`/`local-exec` — Plan 03 RUNBOOK is the manual-upload + manual-ingestion teaching surface (D-05/D-07).
- Plan 01-03: S3 Vectors `aws_s3vectors_index` declares `metadata_configuration { non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"] }`. Forced by live ingestion failure: S3 Vectors caps filterable metadata at 2 KB per record; Bedrock-written chunk text routinely exceeds that for FIXED_SIZE 300-token chunks. Both keys are retrieve-only — never filtered on — so non-filterable is the correct shape, not a workaround. Commit `9006d48`.
- Plan 01-03: `aws_bedrockagent_data_source.catalog` carries `lifecycle.replace_triggered_by = [aws_bedrockagent_knowledge_base.this]`. The AWS provider does NOT mark the data source for replacement when its parent KB is replaced; without this lifecycle block, terraform attempts `UpdateDataSource` against the new KB id with the stale data source id and corrupts state. Forces lockstep replacement. Commit `28bbcee`.
- Plan 01-03: `bin/verify-kb.sh` enforces `command -v aws` and `command -v jq` at startup, exits 2 with platform install hints on miss; the original `2>/dev/null || echo 0` jq fallback was a textbook diagnostic-killing pattern (masked missing-jq install as 5-minute propagation timeout). Aligns with AGENTS.md "don't program defensively, identify root cause first." Commit `f78a39a`.
- Plan 01-03: KB-04 verified end-to-end against live AWS — `aws bedrock-agent-runtime retrieve` for "iPhone 13 Pro Max stock" returns top score `0.8598317801952362` against KB `BKXE19AH89` in `ap-northeast-1`. Closes Phase 1 success criterion #2.
- Plan 01-03: KB-06 re-index path verified for-real — single-file edit + `aws s3 cp` + `aws bedrock-agent start-ingestion-job` (job `KKLS6LQP9A`) re-indexes incrementally; new content queryable at attempt 1. Catalog reverted; final sync `AWI4TJPQN9` re-aligned KB to repo state. Closes Phase 1 success criterion #5.
- Plan 01-03: Live KB id is `BKXE19AH89` (NOT `DWQQ6HXRQW` — the original first-apply id was replaced when the metadata_configuration fix landed). Phase 2 consumer role must scope to `kb_arn = arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89`.
- Plan 02-01: Python 3.12 pinned in `agent/pyproject.toml` (`requires-python = ">=3.12"`), NOT 3.11 as CONTEXT D-20 originally said. Pipecat's `aws-nova-sonic` extra has marker `python_version>='3.12'`; on 3.11 the extra silently no-ops and `aws_sdk_bedrock_runtime` is missing from the lockfile. Research correction #1.
- Plan 02-01: AWS credentials passed as explicit kwargs to `AWSNovaSonicLLMService(access_key_id=..., secret_access_key=..., session_token=..., region=...)` from `os.environ`. The service uses `StaticCredentialsResolver` internally — boto3 default chain (`~/.aws`) is NOT enough on its own. Research correction #3 / Pitfall B.
- Plan 02-01: FastAPI single-app shape exposes both `GET /ping` (returns `{"status":"Healthy",...}`) and `WebSocket /ws` on the same port 8080. Phase 3 AgentCore deploy reuses `hera_agent.main:app` directly — no transport refactor. Research correction #4.
- Plan 02-01: `lookup_product_handler` dispatches sync boto3 via `await asyncio.to_thread(_kb_retrieve, query)` because boto3 is sync; inline sync inside an async pipeline stutters audio playback. Pitfall F.
- Plan 02-01: `register_function("lookup_product", handler, cancel_on_interruption=False)` — KB calls take ~400ms; cancelling+re-firing on every barge-in wastes user-perceived latency. Pitfall H.
- Plan 02-01: `SessionContinuationParams(transition_threshold_seconds=360)` configured explicitly in `pipeline.py` (matches Pipecat default but makes AGT-05 contract grep-discoverable). Pipecat rotates the bidi stream ~120s before the ~480s Sonic stream cap.
- Plan 02-01: No `AudioConfig(...)` instantiation anywhere — Pipecat defaults already satisfy AGT-07 (16 kHz Int16 in / 24 kHz mono out).
- Plan 02-01: `tools.py` mirrors `bin/verify-kb.sh` 1:1 — `numberOfResults=3`, threshold from `HERA_KB_SCORE_THRESHOLD` env (default 0.4), `"no relevant product info"` sentinel, top-1-first `Source: <basename>\n<text>` format joined by `\n\n`. D-18.
- Plan 02-01: Only `try/except` in the codebase is `except WebSocketDisconnect: pass` in `/ws` handler — that is the normal disconnect path, not error suppression. AGENTS.md mandate honored across 6 hera_agent modules.
- Plan 02-01: Dev dep `websockets` declared explicitly in `agent/pyproject.toml` (already a transitive of Pipecat's `websocket` extra) so Plan 02-02's `bin/_smoke_voice_probe.py` has a stable AGT-04 latency-gate import that survives Pipecat-internal swaps.
- Plan 02-03: New module `infra/modules/kb_consumer_policy/` mirrors `infra/modules/knowledge_base/` four-file shape (versions/variables/main/outputs). Single `aws_iam_policy.kb_retrieve` resource — name `hera-kb-retrieve-prod`, one Allow statement (Action `bedrock:Retrieve`, Resource `var.kb_arn`), zero wildcards (D-13), zero attachments (D-22). Module input `kb_arn` has no default so a wildcard is structurally impossible; only legitimate caller is `module.kb_consumer_policy { kb_arn = module.knowledge_base.kb_arn }`. Live policy ARN: `arn:aws:iam::851725411875:policy/hera-kb-retrieve-prod`.
- Plan 02-03: jsonencode chosen over `data "aws_iam_policy_document"` for this single-statement policy (matches RESEARCH.md verbatim, simpler than Phase 1's data-source style which exists because Phase 1 has three statements with shared conditions). Both styles satisfy D-13 wildcard-free.
- Plan 02-03: Phase-N IAM ships, Phase-N+1 attaches (RESEARCH P7). Policy created in Phase 2, attachment to AgentCore exec role deferred to Phase 3 with `aws_iam_role_policy_attachment.role = aws_iam_role.agentcore_exec.name; policy_arn = module.kb_consumer_policy.policy_arn`.
- Plan 02-03: RUNBOOK split between Plan 02-03 and Plan 02-02 by heading (not by file). 02-03 owns `## Local agent setup (Phase 2) — uv path` + `## Resolved deferrals`; 02-02 owns `## First voice test` + `## Cleanup local Docker resources`. No merge conflict because diffs land at distinct sections.
- Plan 02-03: `bin/verify-kb.sh` requires `jq` and the script's pre-flight `command -v jq` gate (added in 01-03 commit `f78a39a`) is what produces the install-hint error. Document — operators on a fresh shell must `winget install jqlang.jq` (Windows), `brew install jq` (macOS), or `apt-get install jq` (Debian/Ubuntu) before running the script. Underlying `aws bedrock-agent-runtime retrieve` API call works without `jq`.
- Plan 02-02: Container is multi-arch (`linux/arm64,linux/amd64`) via `docker buildx --platform`, ARG TARGETPLATFORM/BUILDPLATFORM only — NO `FROM --platform=` pin (Pitfall C). Same image artifact ships to ECR for Phase 3 AgentCore Runtime (ARM64-only) without rebuild — this is AGT-08.
- Plan 02-02: Pipecat 1.1.0's `FastAPIWebsocketTransport` SILENTLY DROPS every WS frame in both directions when `serializer=None`. Plan 02-01 left it None; the entire wire contract was non-functional and was only revealed when running `bin/smoke-voice.sh` against live Sonic. Fix: `agent/hera_agent/serializer.py` ships `RawPCMSerializer` (pass-through bytes <-> `{Input,Output}AudioRawFrame`) wired into `FastAPIWebsocketParams(serializer=RawPCMSerializer())`. This honors the plan's `add_wav_header=False` raw-PCM contract.
- Plan 02-02: `AWSNovaSonicLLMService` only triggers a greet when the LLMContext ENDS with a `Role.USER` message at session-setup time (sent as `interactive=True`). Plan 02-01's on_client_connected handler used role="developer" added AFTER the session-setup race - the message arrived too late and Sonic never greeted. Fix: pre-seed `LLMContext(messages=[{"role": "user", "content": "Hello."}], tools=TOOLS)` at construction time so `_finish_connecting_if_context_available`'s initial run sees the kickoff message.
- Plan 02-02: docker-compose.yml uses `${VAR:?msg}` REQUIRED-syntax for AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, HERA_KB_ID — surfaces friendly fail-fast error before container starts (T-02-02-04). Env-var values are double-quoted because the planner-specified messages contain `:` characters that would otherwise break YAML scalar parsing.
- Plan 02-02: AGT-04 latency target is now PROGRAMMATICALLY GATED via `bin/smoke-voice.sh` (exits 0 only on `LATENCY_MS<3000`). Operator inspection is no longer the gate. Live result against Bedrock Nova 2 Sonic in ap-northeast-1 + KB BKXE19AH89: `LATENCY_MS=0` (Sonic's first inbound binary frame arrived essentially synchronously with end-of-send during the 1s silence streaming phase).

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 3 open questions** (from research/SUMMARY.md): AgentCore Terraform-provider coverage, AgentCore pricing model, exact Pipecat → AgentCore deploy steps, concurrency/quota defaults, WebRTC-vs-WebSocket transport for Pipecat. Resolve in Phase 3 planning via `/gsd-research-phase` before committing implementation.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Repo hygiene | Add `plan.out` to `.gitignore` (post-`terraform plan -out` artifact) | Open | Plan 02-03 |
| Phase 1 D-10 | Consumer `bedrock:Retrieve` policy for Pipecat | RESOLVED in Plan 02-03 (managed policy `hera-kb-retrieve-prod`) | Plan 01-01 |

## Session Continuity

Last session: 2026-05-05
Stopped at: Phase 3 UI-SPEC approved. `/gsd:ui-phase 3` produced 03-UI-SPEC.md, commit a71b70a. Apple-Store light design system locked: palette (`#0071e3` / `#f5f5f7` / `#ffffff` / `#e74c3c`), 4 type sizes (14/16/20/28) × 2 weights (400/600), 4/8/16/24/32/48 spacing scale (+56px record-button height for WCAG 2.5.5), 5 record-button states with full per-state color/background/border/aria-label spec, color-coded transcript (user `#0071e3`, agent `#1d1d1f`, system `#86868b`), 5 WID-06 error strings, instructor-demo banner verbatim, zero registries (no npm / no CDN / no Google Fonts — vanilla HTML/CSS/JS). UI-checker APPROVED 6 dimensions (Dim 2 non-blocking FLAG: focal point implicit — planner should declare record button as primary focal point explicitly). Earlier: `/gsd:discuss-phase 3` produced 03-CONTEXT.md (D-24..D-30) and 03-DISCUSSION-LOG.md, commit 5c0f31b. Hybrid TF + CDK Python IaC split locked. 3-step deploy lifecycle locked. S3+CloudFront widget hosting locked. $5/day banner cap + 2-concurrent throttling locked. D-22 (Phase 2 deferral) closes here when policy attachment lands in Phase 3 IAM module. Next: `/gsd-plan-phase 3` (researcher must resolve research/SUMMARY.md open questions #1, #3, #4, #6 around AgentCore Terraform support, deploy steps, concurrency knob, KB tool helper).
Resume file: .planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-UI-SPEC.md
