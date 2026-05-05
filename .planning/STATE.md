# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-04)

**Core value:** A Cloud Clubs learner walks the workshop and successfully deploys a voice chatbot in their own AWS account, talking to it through their browser.
**Current focus:** Phase 2 — Pipecat Voice Agent (Local)

## Current Position

Phase: 2 of 5 (Pipecat Voice Agent — Local)
Plan: 1 of 3 in current phase complete (02-01); Wave 1 sibling 02-03 pending; Wave 2 = {02-02} pending
Status: Plan 02-01 complete — Python Pipecat 1.1.0 voice agent core ships at agent/ with FastAPI /ping + /ws on port 8080, AWSNovaSonicLLMService with explicit static creds, lookup_product tool via asyncio.to_thread, SessionContinuationParams(360s) for AGT-05, no AudioConfig override (defaults satisfy AGT-07), 11 unit tests pass with mocked boto3. Six AGT requirements satisfied (AGT-01, AGT-02, AGT-03, AGT-05, AGT-06, AGT-07). Phase 1 untouched. Next: 02-03 (Terraform IAM consumer policy + RUNBOOK Phase 2 sections — Wave 1 sibling, no file overlap with 02-01) then Wave 2 (02-02 — Dockerfile + docker-compose + frontend + AGT-04 voice-loop smoke probe; autonomous: false).
Last activity: 2026-05-05 — Plan 02-01 executed in ~5 min (3 commits b606c8e, a55862d, db64e08). All four research corrections enforced verbatim and grep-checked. Plan executed exactly as written with zero deviations.

Progress: [████████████░░░░░░░░] 27%

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: ~19 min
- Total execution time: ~1.23 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Knowledge Base Foundation | 3/3 | ~69 min | ~23 min |
| 2. Pipecat Voice Agent (Local) | 1/3 | ~5 min | ~5 min |
| 3. AgentCore Deploy + Web Widget + Public Demo URL | 0/TBD | — | — |
| 4. Observability, Cost Control, Cleanup | 0/TBD | — | — |
| 5. Workshop Documentation (vi/en) | 0/TBD | — | — |

**Recent Trend:**
- Last 5 plans: 01-01 (~5 min, 3 tasks, 6 files), 01-02 (~14 min, 3 tasks, 11 files — included a network-error resume mid-execution), 01-03 (~50 min, 5 tasks, 2 plan deliverables + 3 deviation-fix iterations against live AWS), 02-01 (~5 min, 3 tasks, 16 files, 0 deviations — pure greenfield Python with no live-AWS dependency)
- Trend: live-AWS plans cost more wall-clock than offline IaC plans (3 deviation fixes were forced by AWS-side reality the offline `terraform validate` could not catch); offline plans like 02-01 (mocked boto3 via MagicMock) execute clean in single-digit minutes; per-task atomic commits and per-deviation atomic commits keep the blame trail honest

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

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 3 open questions** (from research/SUMMARY.md): AgentCore Terraform-provider coverage, AgentCore pricing model, exact Pipecat → AgentCore deploy steps, concurrency/quota defaults, WebRTC-vs-WebSocket transport for Pipecat. Resolve in Phase 3 planning via `/gsd-research-phase` before committing implementation.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none — first milestone)* | | | |

## Session Continuity

Last session: 2026-05-05
Stopped at: Plan 02-01 complete (16 files / 3 commits / 11 tests pass). Wave 1 sibling 02-03 (Terraform IAM consumer policy + RUNBOOK Phase 2 sections — no file overlap with 02-01) is the natural next executor. Wave 2 = 02-02 (container + compose + frontend + AGT-04 voice-loop smoke probe; autonomous=false — live AWS gate via bin/smoke-voice.sh requires HERA_KB_ID=BKXE19AH89 and Bedrock Nova 2 Sonic access in ap-northeast-1).
Resume file: .planning/phases/02-pipecat-voice-agent-local/02-03-PLAN.md (Wave 1 sibling) or 02-02-PLAN.md after 02-03 completes
