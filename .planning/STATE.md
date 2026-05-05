# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-04)

**Core value:** A Cloud Clubs learner walks the workshop and successfully deploys a voice chatbot in their own AWS account, talking to it through their browser.
**Current focus:** Phase 1 — Knowledge Base Foundation

## Current Position

Phase: 1 of 5 (Knowledge Base Foundation)
Plan: 2 of 3 in current phase
Status: Plan 01-02 complete; ready to execute Plan 01-03 (verify + sync, requires AWS credentials)
Last activity: 2026-05-05 — Executed Plan 01-02 (Terraform KB module + envs/prod root): 3 tasks committed atomically (442a63e, ea36745, b47ce36); KB-02/KB-03/KB-05 satisfied at the IaC level; `terraform init && terraform validate` exits 0 offline; first run interrupted by network error mid-Task-3, resumed and completed cleanly

Progress: [█████░░░░░] 13%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: ~10 min
- Total execution time: ~0.32 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Knowledge Base Foundation | 2/3 | ~19 min | ~10 min |
| 2. Pipecat Voice Agent (Local) | 0/TBD | — | — |
| 3. AgentCore Deploy + Web Widget + Public Demo URL | 0/TBD | — | — |
| 4. Observability, Cost Control, Cleanup | 0/TBD | — | — |
| 5. Workshop Documentation (vi/en) | 0/TBD | — | — |

**Recent Trend:**
- Last 5 plans: 01-01 (~5 min, 3 tasks, 6 files), 01-02 (~14 min, 3 tasks, 11 files — included a network-error resume mid-execution)
- Trend: per-task atomic commits with no rework; resume-from-staged-files path is proven (01-02 executor died mid-flight and the second agent picked up exactly where the first left off, no work lost)

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
Stopped at: Completed Plan 01-02 (Terraform KB module + envs/prod root); next is Plan 01-03 (verify-and-sync — requires AWS credentials, not autonomous)
Resume file: .planning/phases/01-knowledge-base-foundation/01-03-verify-and-sync-PLAN.md
