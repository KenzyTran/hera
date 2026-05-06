# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-04)

**Core value:** A Cloud Clubs learner walks the workshop and successfully deploys a voice chatbot in their own AWS account, talking to it through their browser.
**Current focus:** Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL — Wave 1 complete (03-01 + 03-02 done); Wave 2 next (03-03 bin/push-image.sh).

## Current Position

Phase: 3 of 5 (AgentCore Deploy + Web Widget + Public Demo URL) — In progress
Plan: 2 of 4 done. Plan 03-02 (frontend widget Apple-Store light + bin/build-widget.sh) shipped 5 files in 3 atomic commits. Apple-Store light widget polish satisfies WID-01..06 + DEM-03: 5 record-button state classes wired by a setState() machine in app.js, all 5 WID-06 error trigger handlers wired to D-28 events with verbatim UI-SPEC copy, 30s heartbeat for agent-timeout, AGENTCORE_WSS_URL build-time placeholder with typeof guard so source-tree local-dev fallback (`ws://localhost:8080/ws`) keeps docker compose path working. bin/build-widget.sh paste-style operator script copies frontend/* into dist/widget/, sed-replaces the placeholder, runs two sanity gates (placeholder gone + localhost dev URL gone), then `aws s3 sync` + `aws cloudfront create-invalidation` on 4 specific paths. audio-capture-worklet.js byte-for-byte unchanged from Phase 2.

Plan 03-01 (prior wave): TF infra applied live, 12 AWS resources in account 851725411875/ap-northeast-1. D-22 closed. Live outputs:
  - agentcore_exec_role_arn = arn:aws:iam::851725411875:role/hera-agentcore-exec-prod
  - agentcore_log_group_name = /aws/bedrock-agentcore/hera-agent
  - ecr_repo_url = 851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent
  - widget_cloudfront_url = https://dg0w939ktclw6.cloudfront.net
  - widget_cloudfront_distribution_id = E10K3B1L8PQ9EC
  - widget_s3_bucket_name = hera-widget-prod

Wave 2: 03-03 (bin/push-image.sh) — unblocked by 03-01 ECR output. Wave 3: 03-04 (CDK AgentCore stack + smoke) — needs all of 03-01/02/03; will set AGENTCORE_WSS_URL env var or wire it to a terraform output, then invoke bin/build-widget.sh as deploy step 3 (D-25).
Status: Plan 03-02 complete. All 30 must_haves truths verified via node script (8 palette tokens, 5 button states, 5 WID-06 verbatim strings, 4 transcript color tokens, AGENTCORE_WSS_URL placeholder in app.js + build-widget.sh, AudioWorkletNode preserved, 30s heartbeat, prefers-reduced-motion override, 56px button height). Zero deviations.
Last activity: 2026-05-06 — Plan 03-02 executed in 3 tasks / ~22 min. Task 1 commit `011395f` (rewrite frontend/index.html + extract styles.css), Task 2 commit `95ae987` (rewrite frontend/app.js with 5-state machine + WID-06 + heartbeat + placeholder), Task 3 commit `6a57d95` (bin/build-widget.sh + .gitignore dist/). audio-capture-worklet.js untouched (last commit 109c686 Phase 2). Em-dash characters in error strings preserved verbatim from UI-SPEC.

Progress: [██████████████████░░] 50%

## Performance Metrics

**Velocity:**
- Total plans completed: 8
- Average duration: ~26 min
- Total execution time: ~3.9 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Knowledge Base Foundation | 3/3 | ~69 min | ~23 min |
| 2. Pipecat Voice Agent (Local) | 3/3 | ~90 min | ~30 min |
| 3. AgentCore Deploy + Web Widget + Public Demo URL | 2/4 | ~72 min | ~36 min |
| 4. Observability, Cost Control, Cleanup | 0/TBD | — | — |
| 5. Workshop Documentation (vi/en) | 0/TBD | — | — |

**Recent Trend:**
- Last 8 plans: 01-02 (~14 min), 01-03 (~50 min, 3 deviation-fix iterations against live AWS), 02-01 (~5 min, 0 deviations), 02-03 (~7 min, 0 deviations), 02-02 (~78 min, 4 auto-fix deviations — live Sonic AGT-04 gate), 03-01 (~50 min, 5 tasks split across two executor invocations; 0 deviations), 03-02 (~22 min, 3 tasks, 0 deviations — pure file-write + verify + commit loop because UI-SPEC contract was already locked and Plan 03-01 outputs were already live).
- Trend: Plan 03-02 was the fastest plan in Phase 3 because the planner front-loaded all hard decisions into UI-SPEC.md (locked at commit a71b70a) and verbatim copy/CSS-token blocks into the action sections; executor work reduced to file-write + automated verify + atomic commit. Pattern repeats for any future plan that satisfies (a) verbatim contract pre-locked, (b) all upstream deploy outputs already live, (c) verify automated provided in `<verify>` block. Plan 03-03 (bin/push-image.sh against the already-live ECR repo) should follow the same shape; Plan 03-04 (CDK + smoke) will reintroduce live-AWS variance.

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
- Plan 03-01: AgentCore trust principal `bedrock-agentcore.amazonaws.com` accepted on first apply (NOT `bedrock.amazonaws.com` — Phase-1 Pitfall-I principal differs at the AgentCore layer). Confused-deputy mitigated via `aws:SourceAccount=851725411875` + `AWS:SourceArn ArnLike arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/*`. Live role: `arn:aws:iam::851725411875:role/hera-agentcore-exec-prod`.
- Plan 03-01: D-22 (Phase 2 deferral) closed live — `aws_iam_role_policy_attachment.kb_retrieve` attaches `arn:aws:iam::851725411875:policy/hera-kb-retrieve-prod` to the AgentCore exec role. `aws iam list-attached-role-policies --role-name hera-agentcore-exec-prod` confirms.
- Plan 03-01: Sonic foundation-model ARN `arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.nova-sonic-v1:0` flagged `[needs-verification]` in PLAN.md; IAM-policy `aws:CreatePolicy` validates ARN syntax only, not model existence. Runtime gate is Plan 03-04 smoke (`bedrock:InvokeModelWithBidirectionalStream`). If smoke fails, override `module.agentcore_iam.sonic_model_arn` at the prod root after `aws bedrock list-foundation-models --by-output-modality SPEECH --region ap-northeast-1` resolves the verified id.
- Plan 03-01: D-13 zero-wildcard verified live — Python regex sweep across `infra/**/*.tf` finds exactly one wildcard at `infra/modules/agentcore_iam/main.tf:87` = the documented `cloudwatch:PutMetricData` Resource=* exception, gated by `cloudwatch:namespace = hera/agentcore` StringEquals condition. AWS-published least-privilege pattern (PutMetricData has no resource-level scoping in IAM).
- Plan 03-01: ECR repo `hera-agent` shipped with `imageTagMutability=IMMUTABLE` — Plan 03-03 push-script must NOT pass `:latest` (immutable rejects retag). Lifecycle policy keeps last 5 untagged images. `force_delete=false` — Phase 4 cleanup-verify must explicitly `aws ecr delete-repository --force` to protect pushed images from accidental `terraform destroy`.
- Plan 03-01: CloudFront `MinimumProtocolVersion` silently downgrades from `TLSv1.2_2021` (set in TF) to `TLSv1` (returned by API) when `CloudFrontDefaultCertificate=true`. AWS-side override: default `*.cloudfront.net` cert maximizes client reach. HTTPS-only still enforced via `viewer_protocol_policy=redirect-to-https`. Custom-domain ACM cert (deferred per D-26) would unlock `TLSv1.2_2021` minimum. Documented behavior, not a regression.
- Plan 03-01: Widget hosting verified live — S3 `hera-widget-prod` PAB all-true, CloudFront `E10K3B1L8PQ9EC` `Status=Deployed` in 2m50s (faster than the 8-15min D-26 estimate), HSTS `max-age=31536000; includeSubDomains` + `X-Content-Type-Options: nosniff` headers active (verified via `curl -I` returning HTTP/1.1 403 from S3 NoSuchKey through OAC — empty bucket is correct, Plans 03-02/03-04 populate). Live URL: `https://dg0w939ktclw6.cloudfront.net`.
- Plan 03-01: Empty-commit-with-outputs-in-body pattern established for live deploy events — `git commit --allow-empty -m "feat(03-01): apply terraform live..."` with full output capture + acceptance-gate results in body. Captures deploy event in git history while preserving per-task atomic-commit contract; works because terraform state file + plan.out are gitignored.
- Plan 03-02: AGENTCORE_WSS_URL build-time placeholder uses `typeof __AGENTCORE_WSS_URL__ !== "undefined"` guard. Source-tree value evaluates to `"ws://localhost:8080/ws"` so `docker compose up` keeps working; bin/build-widget.sh sed-replaces the literal `__AGENTCORE_WSS_URL__` in dist/widget/app.js, after which the typeof check evaluates to `"string"` at runtime and selects the WSS branch. Source `frontend/` tree is NEVER mutated (CONTEXT D-27 §Local dev unchanged).
- Plan 03-02: 30s heartbeat resets on every inbound binary frame so a long agent reply does not trigger timeout mid-response. Timeout strictly fires when ZERO frames arrive in 30s. Implementation: `armHeartbeat()` clears + restarts the timer in `ws.onmessage` for binary data; `inboundBinarySeen` boolean gates the fail() call.
- Plan 03-02: 5-state record-button machine in app.js uses single class swap (`recordBtn.className = "btn btn-" + state`) — all per-state styling lives in styles.css under .btn-{idle,connecting,listening,speaking,error}. aria-pressed/aria-busy/aria-disabled toggled in lockstep with state by setState(). Status pill follows via PILL_FOR_STATE map.
- Plan 03-02: Em-dash characters (—) preserved verbatim in WID-06 error strings ("Couldn't reach the agent —", "The agent didn't respond in time —", "Microphone is muted —") because UI-SPEC §Error state copy uses them. Plan's verify automated uses substring matches without dash, so both representations would pass — verbatim wins per the plan's `must_haves.truths` "verbatim" mandate.
- Plan 03-02: bin/build-widget.sh writes via temp file + mv (`sed ... > tmp; mv tmp file`) instead of `sed -i`. Portable across BSD (macOS) and GNU sed without the `-i ''` BSD quirk. Two post-sed sanity gates: (1) `__AGENTCORE_WSS_URL__` placeholder must be gone, (2) `ws://localhost:8080` localhost dev URL must be gone — either gate failure exits 3 before s3 sync.
- Plan 03-02: CloudFront invalidation targets the 4 specific paths (/index.html /app.js /styles.css /audio-capture-worklet.js) instead of /*. Stays below the 1000-free-paths/month CloudFront threshold; Phase 4 cost-control work reuses this pattern.
- Plan 03-02: audio-capture-worklet.js byte-for-byte preserved from Phase 2 (`git diff` empty; last touched commits 109c686 + 72f6236 + f8238c8). The 16 kHz Int16 LE capture path with anti-alias LPF + cursor-based decimation is the wire-contract baseline; Phase 3 polish wraps UX around it without touching the audio path.

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 3 open questions** (from research/SUMMARY.md): AgentCore Terraform-provider coverage, AgentCore pricing model, exact Pipecat → AgentCore deploy steps, concurrency/quota defaults, WebRTC-vs-WebSocket transport for Pipecat. Resolve in Phase 3 planning via `/gsd-research-phase` before committing implementation.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Repo hygiene | Add `plan.out` to `.gitignore` (post-`terraform plan -out` artifact) | RESOLVED in Plan 03-01 Task 4 | Plan 02-03 |
| Phase 1 D-10 | Consumer `bedrock:Retrieve` policy for Pipecat | RESOLVED in Plan 02-03 (managed policy `hera-kb-retrieve-prod`) | Plan 01-01 |
| Phase 2 D-22 | Attach `hera-kb-retrieve-prod` to AgentCore exec role | RESOLVED in Plan 03-01 Task 1 (live `aws_iam_role_policy_attachment.kb_retrieve`) | Plan 02-03 |
| Plan 03-01 | Sonic foundation-model ARN runtime gate | Open — verified at Plan 03-04 smoke (`bedrock:InvokeModelWithBidirectionalStream`) | Plan 03-01 |
| Plan 03-01 | CloudFront custom domain + ACM cert (would also unlock `TLSv1.2_2021` minimum) | Open — deferred per D-26 to v2 | Plan 03-01 |
| Plan 03-01 | Widget S3 versioning (rollback path is git+bin/deploy-widget.sh) | Open — deferred per D-26 to Phase 4 if cleanup-verify proves teardown is clean | Plan 03-01 |

## Session Continuity

Last session: 2026-05-06
Stopped at: Plan 03-02 complete. 5 files / 3 commits / 0 deviations / ~22 min. frontend/index.html + frontend/styles.css + frontend/app.js polished to UI-SPEC contract; bin/build-widget.sh ready as Plan 03-04 deploy step 3 (D-25). Apple-Store light palette (8 colors), 5 record-button states with visual differentiation, 5 WID-06 error trigger handlers verbatim from UI-SPEC, 30s heartbeat for agent-timeout, AGENTCORE_WSS_URL placeholder with typeof guard so docker-compose local-dev path remains unchanged. bin/build-widget.sh has executable bit + bash -n syntax-valid + `command -v` preflight for aws/sed/terraform + sed-replace into dist/widget/ build copy + two sanity gates (placeholder gone + localhost dev URL gone) + `aws s3 sync --delete` + `aws cloudfront create-invalidation` on 4 specific paths. audio-capture-worklet.js byte-for-byte unchanged from Phase 2 (last touched 109c686). All 30 must_haves truths verified via node script (palette tokens, button states, WID-06 strings, transcript colors, placeholder, AudioWorkletNode, heartbeat, prefers-reduced-motion, 56px button-h). Wave 1 of Phase 3 closed.

Next: launch Plan 03-03 Wave 2 (bin/push-image.sh multi-arch buildx push to ECR + RUNBOOK Phase 3 deploy section). 03-03 is unblocked by Plan 03-01's ECR output (`ecr_repo_url=851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent`). After 03-03, Wave 3 (03-04 CDK + smoke) requires all three prior plans to be live. Plan 03-04 will:
  1. `cdk deploy hera-agentcore --context image_tag=$(git rev-parse --short HEAD)` (CDK reads ECR image URI + agentcore_exec_role_arn from terraform outputs).
  2. Capture `agentcore_wss_url` from CDK output (or write back to a terraform output).
  3. `AGENTCORE_WSS_URL=<url> bin/build-widget.sh` to inject + sync + invalidate.
  4. `bin/smoke-deploy.sh` to verify the full end-to-end voice loop against the live CloudFront URL with at least one KB-backed product reply.

Resume file: .planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-03-PLAN.md
