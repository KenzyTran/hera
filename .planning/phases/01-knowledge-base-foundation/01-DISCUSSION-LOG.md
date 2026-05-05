# Phase 1: Knowledge Base Foundation - Discussion Log

**Date:** 2026-05-05
**Mode:** discuss (default), Vietnamese-language UI by user request

This log records the gray areas surfaced, the options shown, the user's selections, and the rationale for each pick. Reference only — downstream agents (researcher, planner) read CONTEXT.md, not this file.

---

## Pre-flight context loaded

- `.planning/PROJECT.md` — locked stack (Nova 2 Sonic, Pipecat, AgentCore, S3 Vectors, Terraform `~> 6.27`, ap-northeast-1; no NAT/VPC/PrivateLink; no DynamoDB).
- `.planning/REQUIREMENTS.md` — 6 KB requirements (KB-01 through KB-06) mapped to Phase 1.
- `.planning/ROADMAP.md` — Phase 1 goal and 5 success criteria.
- `.planning/STATE.md` — start of Phase 1, no prior plans.
- `.planning/research/STACK.md` — Titan v2 1024-dim float32 cosine; native `aws_s3vectors_*` and `aws_bedrockagent_knowledge_base` resources in `hashicorp/aws ~> 6.27`; default chunking 300 tokens / 20% overlap.
- `.planning/research/PITFALLS.md` — Pitfalls #3, #8, #9, #17, #20, #23 informed the question framing.
- `.planning/research/ARCHITECTURE.md` — Phase 1 block scoping.
- No prior phase CONTEXT.md (first phase). No SPEC.md. No DECISIONS-INDEX.md.

## Gray areas presented (multi-select)

User selected **all four**:

1. Catalog content shape
2. Sync trigger / re-index UX (KB-06)
3. Terraform module + IAM shape
4. Verification artifact for KB-04

Items already locked by PROJECT.md / STACK.md and therefore NOT asked:
S3 Vectors, Titan v2 dimensions/metric, region, SKU list, English markdown, default chunking, Terraform `~> 6.27`, no VPC/NAT/PrivateLink, no DynamoDB.

---

## Area 1 — Catalog content shape

### Q1.1 — File layout in S3 source bucket
- **Options shown:** one file per SKU (3 files) [Recommended]; split by concern (specs/stock/policy); one combined catalog.md + stock.md; 3 SKU files + store-policy.md sidecar.
- **User selection:** **One file per SKU (3 files)**.
- **Why this matters:** chunking is 300 tokens / 20% overlap. Putting stock and SKU name in the same file keeps the SKU name in every chunk that mentions stock — strengthens recall for KB-04's verification query.

### Q1.2 — Schema inside each SKU file
- **Options shown:** bullet specs + explicit Stock section [Recommended]; prose-only narrative; YAML front-matter + body; Q&A style.
- **User selection:** **Bullet specs + 'Stock' section rõ ràng (Recommended)**.
- **Resulting schema:** `# <SKU>` → `## Overview` (prose) → `## Specifications` (bullets) → `## Pricing` → `## Stock & Availability`.

### Q1.3 — Sidecar files beyond the 3 SKU files
- **Options shown:** only 3 SKU files [Recommended]; 3 SKU + store-policy.md; 3 SKU + pricing-faq.md.
- **User selection:** **3 SKU + `store-policy.md`**.
- **Resulting source bucket:** 4 markdown files total. `store-policy.md` covers return policy, hours, warranty.
- **Deferred:** `pricing-faq.md` (financing, trade-in, AppleCare) — backlog/v2.

---

## Area 2 — Sync trigger / re-index UX (KB-06)

### Q2.1 — First-sync trigger after `terraform apply`
- **Options shown:** manual CLI step in workshop docs [Recommended]; auto sync via Terraform `null_resource` + AWS CLI; wrapper script `bin/kb-sync.sh`.
- **User selection:** **Manual CLI step trong workshop docs (Recommended)**.
- **Why this matters:** keeps Terraform state side-effect-free, makes the API surface visible to learners, easier to debug when sync fails.

### Q2.2 — Re-index workflow when product files change
- **Options shown:** same `start-ingestion-job` documented in RUNBOOK.md [Recommended]; wrapper `bin/kb-resync.sh`; document incremental sync + destroy/recreate fallback.
- **User selection:** **Cùng `start-ingestion-job` command, document trong RUNBOOK.md (Recommended)**.
- **Resulting artifact:** RUNBOOK.md at repo root captures the sync command, the 2–3 min propagation wait (Pitfall #9), and the destroy+re-apply recovery path (Pitfall #17).

---

## Area 3 — Terraform module + IAM shape

### Q3.1 — Module structure
- **Options shown:** single `modules/knowledge_base` [Recommended]; split into `source_s3` + `vector_store` + `knowledge_base`; single module with IAM inlined into root.
- **User selection:** **Single `modules/knowledge_base` (Recommended)**.
- **Module surface:** source S3 bucket, S3 Vectors bucket, vector index, Bedrock KB resource, KB data source, KB service IAM role + policy, outputs.

### Q3.2 — Consumer-side `bedrock:Retrieve` role
- **Options shown:** defer to Phase 2 [Recommended]; create in Phase 1 with KB ARN scope; create a policy-only artifact in Phase 1 for Phase 2 to attach.
- **User selection:** **Defer sang Phase 2 (Recommended)**.
- **Phase 2 hand-off:** Phase 1 outputs `kb_arn` only; Phase 2 creates the Pipecat task role and the scoped `bedrock:Retrieve` policy together.

### Q3.3 — State backend and cleanup safety
- **Options shown:** local state + `force_destroy=true` + no random suffix [Recommended]; local + `force_destroy=true` + random suffix; S3+DynamoDB remote backend from day one.
- **User selection:** **Local state + `force_destroy=true` + KHÔNG random suffix (Recommended)**.
- **Recovery path:** documented in RUNBOOK.md as `terraform destroy -target` + re-apply.

---

## Area 4 — Verification artifact for KB-04

### Q4.1 — Verification artifact shape
- **Options shown:** `bin/verify-kb.sh` polling retrieve [Recommended]; documented command only; inline Terraform `null_resource` test; pytest test in `tests/test_kb_retrieve.py`.
- **User selection:** **Ship `bin/verify-kb.sh` script polling retrieve (Recommended)**.
- **Script contract:**
  - Reads `kb_id` from `terraform output` or `--kb-id` flag.
  - Calls `aws bedrock-agent-runtime retrieve` with query "iPhone 13 Pro Max stock".
  - Polls every 15s, max 5 minutes.
  - Exit 0 when `retrievalResults` is non-empty AND top score above documented threshold.
  - Exit non-zero with clear message on timeout / empty / access denied.
- **Reuse:** Phase 4 cleanup-verify can call the same script with assertion inverted.

---

## Claude's Discretion (deferred to planner / executor)

- Exact prose wording for each markdown file.
- Plausible 2026 stock counts and pricing values.
- Default values for Terraform variables beyond `region`.
- The exact retrieval-score threshold used by `verify-kb.sh` (start ~0.4, tune from real measurements).
- Internal layout of `modules/knowledge_base/` (e.g., split into `main.tf`, `iam.tf`, `outputs.tf`).
- CLI flags / output formatting of `verify-kb.sh`.

## Deferred Ideas (captured, out of phase scope)

- Pricing FAQ document (`pricing-faq.md`).
- Wrapper sync script (`bin/kb-sync.sh`).
- Terraform `null_resource` auto-sync.
- Random-suffix resource naming.
- Remote Terraform backend bootstrap.
- Consumer `bedrock:Retrieve` role (Phase 2).
- Pytest-based CI test (Phase 2+).
- Bedrock Guardrails / PII redaction (post-v1).
- OpenSearch Serverless alternative chapter (v2 ADV-04).

---

*Discussion completed: 2026-05-05.*
*Next step: `/gsd-plan-phase 1`*
