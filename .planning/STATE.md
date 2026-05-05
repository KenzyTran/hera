# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-04)

**Core value:** A Cloud Clubs learner walks the workshop and successfully deploys a voice chatbot in their own AWS account, talking to it through their browser.
**Current focus:** Phase 1 — Knowledge Base Foundation

## Current Position

Phase: 1 of 5 (Knowledge Base Foundation)
Plan: 1 of 3 in current phase
Status: Plan 01-01 complete; ready to execute Plan 01-02 (Terraform module)
Last activity: 2026-05-05 — Executed Plan 01-01 (repo skeleton + catalog): 3 tasks committed atomically (5d6cffa, d049be7, 8c425b8); KB-01 prerequisite satisfied; `.gitignore` Terraform-safe before any `terraform init`

Progress: [███░░░░░░░] 7%

## Performance Metrics

**Velocity:**
- Total plans completed: 1
- Average duration: ~5 min
- Total execution time: ~0.08 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Knowledge Base Foundation | 1/3 | ~5 min | ~5 min |
| 2. Pipecat Voice Agent (Local) | 0/TBD | — | — |
| 3. AgentCore Deploy + Web Widget + Public Demo URL | 0/TBD | — | — |
| 4. Observability, Cost Control, Cleanup | 0/TBD | — | — |
| 5. Workshop Documentation (vi/en) | 0/TBD | — | — |

**Recent Trend:**
- Last 5 plans: 01-01 (~5 min, 3 tasks, 6 files)
- Trend: first plan in scope; metrics will accumulate

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
Stopped at: Completed Plan 01-01 (repo skeleton + catalog); next is Plan 01-02 (Terraform module + root infra)
Resume file: .planning/phases/01-knowledge-base-foundation/01-02-terraform-kb-module-PLAN.md
