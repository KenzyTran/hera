# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-04)

**Core value:** A Cloud Clubs learner walks the workshop and successfully deploys a voice chatbot in their own AWS account, talking to it through their browser.
**Current focus:** Phase 2 — Pipecat Voice Agent (Local)

## Current Position

Phase: 2 of 5 (Pipecat Voice Agent — Local)
Plan: 0 of 3 in current phase
Status: Phase 2 planned (3 plans, 2 waves; checker passed iteration 2 with 0 blockers). 02-RESEARCH.md prescribed 7 named patterns + 4 critical corrections (Python 3.12 not 3.11, ARM64 multi-arch buildx, AWSNovaSonicLLMService StaticCredentialsResolver kwargs, FastAPI /ping + /ws on port 8080 per AgentCore HTTP contract). 02-PATTERNS.md mapped 23 files (15 greenfield + 8 in-repo analogs from Phase 1 IaC + verify-kb.sh). All 8 AGT requirements covered (02-01: AGT-01/02/03/05/06/07; 02-02: AGT-04/08; 02-03: closes Phase 1 D-10 by shipping the IAM consumer policy). Ready for `/gsd-execute-phase 2`.
Last activity: 2026-05-05 — Plan-phase complete: research + pattern map + plan + checker (2 iterations) + revision; AGT-04 latency gate scripted via `bin/smoke-voice.sh` + `bin/_smoke_voice_probe.py` (Plan 02-02 Task 4, autonomous: false, blocks on LATENCY_MS<3000).

Progress: [██████████░░░░░░░░░░] 20%

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: ~23 min
- Total execution time: ~1.15 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Knowledge Base Foundation | 3/3 | ~69 min | ~23 min |
| 2. Pipecat Voice Agent (Local) | 0/3 | — | — |
| 3. AgentCore Deploy + Web Widget + Public Demo URL | 0/TBD | — | — |
| 4. Observability, Cost Control, Cleanup | 0/TBD | — | — |
| 5. Workshop Documentation (vi/en) | 0/TBD | — | — |

**Recent Trend:**
- Last 5 plans: 01-01 (~5 min, 3 tasks, 6 files), 01-02 (~14 min, 3 tasks, 11 files — included a network-error resume mid-execution), 01-03 (~50 min, 5 tasks, 2 plan deliverables + 3 deviation-fix iterations against live AWS)
- Trend: live-AWS plans cost more wall-clock than offline IaC plans (3 deviation fixes were forced by AWS-side reality the offline `terraform validate` could not catch); per-task atomic commits and per-deviation atomic commits keep the blame trail honest

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
Stopped at: Phase 2 planned. 3 plans (02-01 Python agent core, 02-02 container+compose+frontend+AGT-04 scripted gate, 02-03 Terraform IAM consumer policy + RUNBOOK). Wave 1 = {02-01, 02-03} parallel, Wave 2 = {02-02}. Plan 02-02 is autonomous=false (live AWS gate via bin/smoke-voice.sh — must be run with HERA_KB_ID=BKXE19AH89 and Bedrock Nova 2 Sonic access in ap-northeast-1). Next is `/gsd-execute-phase 2`.
Resume file: .planning/phases/02-pipecat-voice-agent-local/02-01-PLAN.md (start with Wave 1)
