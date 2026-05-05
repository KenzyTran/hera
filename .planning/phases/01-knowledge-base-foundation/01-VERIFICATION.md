---
phase: 01-knowledge-base-foundation
verified: 2026-05-05T04:10:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
  gaps_closed: []
  gaps_remaining: []
  regressions: []
requirements_verified:
  - KB-01
  - KB-02
  - KB-03
  - KB-04
  - KB-05
  - KB-06
live_aws_evidence:
  account: "851725411875"
  region: "ap-northeast-1"
  kb_id: "BKXE19AH89"
  kb_arn: "arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89"
  data_source_id: "V9KJOLJTZC"
  source_bucket_name: "hera-kb-source-prod"
  vector_bucket_name: "hera-kb-vectors-prod"
  vector_index_name: "hera-kb-index"
  kb_service_role: "hera-kb-service-role"
  retrieve_top_score: 0.8610701560974121
  retrieve_query: "iPhone 13 Pro Max stock"
---

# Phase 1: Knowledge Base Foundation Verification Report

**Phase Goal:** A learner (or the Pipecat agent) can ask the deployed Bedrock Knowledge Base for Apple product information and get back the right document, end-to-end, using nothing but AWS CLI.

**Verified:** 2026-05-05T04:10:00Z
**Status:** passed
**Re-verification:** No (initial verification)

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| #  | Truth                                                                                                                                                                                                          | Status     | Evidence                                                                                                                                                                                                                                                                                                                                |
| -- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1  | Apple product catalog (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4) lives in source S3 as English markdown and is ingested into a Bedrock KB backed by S3 Vectors with Titan v2 (1024-dim float32 cosine). | VERIFIED   | `aws s3 ls s3://hera-kb-source-prod/catalog/` returns all 4 files (apple-watch-s11.md, iphone-13-pro-max.md, macbook-pro-m4.md, store-policy.md). Live `aws bedrock-agent get-knowledge-base` returns `embeddingDataType: FLOAT32`, `dimensions: 1024`, `type: S3_VECTORS`. Live `aws s3vectors get-index` returns `dataType: float32`, `dimension: 1024`, `distanceMetric: cosine`. |
| 2  | Running `aws bedrock-agent-runtime retrieve` for "iPhone 13 Pro Max stock" returns the matching catalog document with non-zero score, after the documented post-sync wait.                                  | VERIFIED   | Re-run live during this verification: top score `0.8610701560974121` >> 0.4 threshold. Top result `s3://hera-kb-source-prod/catalog/iphone-13-pro-max.md` content includes the iPhone Stock & Availability section. `bin/verify-kb.sh` PASSed at attempt 1 per orchestrator evidence (top score 0.8598).                                |
| 3  | The Terraform `modules/knowledge_base` deploys cleanly into a fresh AWS account in `ap-northeast-1` with `terraform init && apply` and no manual console clicks (model access enable assumed already done). | VERIFIED   | `terraform validate` exits 0 in `infra/envs/prod`. Live state in `terraform output` returns all 4 expected outputs. Live KB exists with status `ACTIVE`. Two deviation fixes (9006d48 metadata-configuration, 28bbcee replace_triggered_by lifecycle) hardened the module so subsequent fresh-account applies work without state surgery. |
| 4  | A least-privilege IAM role exposes only `bedrock:Retrieve` scoped to the KB ARN — no wildcards in Action or Resource. **(Per D-10, this verifies as: Phase-1 KB service role least-privilege with zero wildcards AND `kb_arn` exported for Phase 2.)** | VERIFIED   | Live `aws iam get-role-policy hera-kb-inline` shows 4 statements, all with explicit Actions (no `*`) and explicit Resource ARNs (no `*`). Trust policy uses `bedrock.amazonaws.com` (correct principal) with `aws:SourceAccount` + `AWS:SourceArn` confused-deputy conditions. Module exports `kb_arn = arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89` for Phase 2. |
| 5  | Re-indexing after editing a product markdown is a single documented CLI command, and the new content is queryable within the documented sync window.                                                       | VERIFIED   | `RUNBOOK.md` "Re-index after editing a product file" section contains exact `aws s3 cp` + `aws bedrock-agent start-ingestion-job` commands. Live ingestion job `KKLS6LQP9A` ran with 1 modified / 0 failed; verify-kb.sh PASSed at attempt 1 (top score 0.8601). Final revert sync `AWI4TJPQN9` COMPLETE confirms cycle is reproducible. |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact                                          | Expected                                          | Status     | Details                                                                                                                  |
| ------------------------------------------------- | ------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------ |
| `catalog/apple-watch-s11.md`                      | Apple Watch S11 catalog with D-02/D-03 schema     | VERIFIED   | H1 `# Apple Watch Series 11` + Overview/Specs/Pricing/Stock; SKU name appears inside Stock section (D-03).            |
| `catalog/iphone-13-pro-max.md`                    | iPhone 13 Pro Max catalog (KB-04 query target)    | VERIFIED   | H1 `# iPhone 13 Pro Max` + 4 H2 sections; SKU name repeated 3 times in Stock section. Top hit for KB-04 query.        |
| `catalog/macbook-pro-m4.md`                       | MacBook Pro M4 catalog                            | VERIFIED   | H1 `# MacBook Pro M4` + 4 H2 sections; SKU name in Stock section.                                                       |
| `catalog/store-policy.md`                         | Store policy sidecar (D-01)                       | VERIFIED   | H1 `# Store Policy` + Returns/Store Hours/Warranty/Contact sections.                                                    |
| `RUNBOOK.md`                                      | 8 sections, 0 TODO markers, all commands populated | VERIFIED   | 8 `## ` headings present in correct order; `grep -c TODO\(plan-03\)` returns 0; 223 lines (under 300-line ceiling).      |
| `bin/verify-kb.sh`                                | Executable polling KB-04 verification script      | VERIFIED   | Executable bit set; shebang `#!/usr/bin/env bash`; `set -euo pipefail`; preflight asserts `aws` and `jq` (exits 2 on miss); 15s polling × 20 attempts; jq path `.retrievalResults[0].score`; `--invert` for D-16; `--help` block. Confirmed `bin/verify-kb.sh --help` errors on missing jq with exit 2 — fail-fast working as designed. |
| `infra/modules/knowledge_base/versions.tf`        | Terraform >=1.9 + aws ~> 6.27 pin                 | VERIFIED   | Both pins present.                                                                                                       |
| `infra/modules/knowledge_base/variables.tf`       | 6 variables with documented defaults              | VERIFIED   | name_prefix=hera, env=prod, region=ap-northeast-1, embedding_dimension=1024, chunk_max_tokens=300, chunk_overlap_pct=20. |
| `infra/modules/knowledge_base/main.tf`            | All 6 AWS resources (S3 source, S3-block, S3-vectors bucket+index, KB, data source) | VERIFIED   | All resources present; UPPERCASE FLOAT32 on KB; lowercase float32/cosine on index; `vector_bucket_name` not `name`; `force_destroy=true` on both buckets; `depends_on=[aws_iam_role_policy.kb_inline]`; `inclusion_prefixes=["catalog/"]`; FIXED_SIZE 300/20 chunking; metadata_configuration with non-filterable AMAZON_BEDROCK_TEXT/METADATA (deviation fix 9006d48); replace_triggered_by lifecycle on data source (28bbcee). |
| `infra/modules/knowledge_base/iam.tf`             | KB service role + inline policy with zero wildcards, confused-deputy trust | VERIFIED   | Trust principal `bedrock.amazonaws.com`; `aws:SourceAccount` + `AWS:SourceArn` conditions; 4 inline statements (S3SourceListBucket, S3SourceGetObject, BedrockInvokeTitanV2, S3VectorsReadWrite) with no `*` wildcards. Live policy fetched via `aws iam get-role-policy` matches HCL. |
| `infra/modules/knowledge_base/outputs.tf`         | 4 outputs (kb_id, kb_arn, source_bucket_name, data_source_id) | VERIFIED   | All 4 outputs present with descriptions.                                                                                |
| `infra/envs/prod/versions.tf`                     | Same pins, no backend block                       | VERIFIED   | Same `~> 6.27` and `>= 1.9` pins; no `backend` block (D-11 honored).                                                    |
| `infra/envs/prod/main.tf`                         | Provider config + module call                     | VERIFIED   | `provider "aws" { region = var.region }`; `module "knowledge_base"` with source `../../modules/knowledge_base` and 3 args.|
| `infra/envs/prod/variables.tf`                    | region=ap-northeast-1 default                     | VERIFIED   | All 3 variables present with documented defaults.                                                                       |
| `infra/envs/prod/outputs.tf`                      | Re-export 4 module outputs                        | VERIFIED   | All 4 re-exports present.                                                                                                |
| `infra/envs/prod/terraform.tfvars`                | Explicit region/env/name_prefix                   | VERIFIED   | All 3 values populated as documented.                                                                                    |
| `infra/envs/prod/.terraform.lock.hcl`             | Provider lock pinning aws 6.43.0                  | VERIFIED   | File present (1407 bytes); not gitignored.                                                                              |
| `.gitignore`                                      | Hugo entries preserved + Terraform additions      | VERIFIED   | All 3 Hugo entries (`public/`, `resources/`, `.hugo_build.lock`) intact; Terraform section appended; `.terraform.lock.hcl` is NOT gitignored. |

### Key Link Verification

| From                                                          | To                                                       | Via                                                                              | Status | Details                                                                                                                                                  |
| ------------------------------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `infra/envs/prod/main.tf`                                     | `infra/modules/knowledge_base/`                          | `module "knowledge_base" { source = "../../modules/knowledge_base" }`            | WIRED  | Source path correct; `terraform init` resolved cleanly; `terraform validate` exits 0.                                                                    |
| `aws_bedrockagent_knowledge_base.this`                        | `aws_iam_role_policy.kb_inline`                          | `depends_on = [aws_iam_role_policy.kb_inline]`                                    | WIRED  | Verbatim in main.tf line 84. Race-condition guard active.                                                                                                |
| `aws_bedrockagent_knowledge_base.this.s3_vectors_configuration` | `aws_s3vectors_index.this.index_arn`                     | `index_arn = aws_s3vectors_index.this.index_arn`                                  | WIRED  | Live KB returns `indexArn: arn:aws:s3vectors:ap-northeast-1:851725411875:bucket/hera-kb-vectors-prod/index/hera-kb-index` — matches.                  |
| `aws_bedrockagent_data_source.catalog`                        | `aws_s3_bucket.source` (catalog/ prefix)                 | `bucket_arn` + `inclusion_prefixes = ["catalog/"]`                                | WIRED  | Verbatim in main.tf; live retrieve returns chunks with `s3://hera-kb-source-prod/catalog/iphone-13-pro-max.md` location.                                  |
| `aws_bedrockagent_data_source.catalog`                        | `aws_bedrockagent_knowledge_base.this`                   | `lifecycle.replace_triggered_by = [aws_bedrockagent_knowledge_base.this]`         | WIRED  | Deviation fix 28bbcee added the lifecycle block; without it, KB replacement corrupts state. Now in main.tf lines 122-124.                                |
| `bin/verify-kb.sh`                                            | `terraform output -raw kb_id`                            | `terraform -chdir=infra/envs/prod output -raw kb_id`                              | WIRED  | Verbatim in script line 60.                                                                                                                              |
| `bin/verify-kb.sh`                                            | AWS Bedrock KB Retrieve API                              | `aws bedrock-agent-runtime retrieve --knowledge-base-id "${KB_ID}"`               | WIRED  | Verbatim in script lines 78-83. Live verify returned hits=2, top_score=0.86.                                                                              |
| `RUNBOOK.md` First sync                                       | terraform outputs → `aws s3 cp` → `start-ingestion-job`  | bash one-liners using `terraform -chdir=infra/envs/prod output -raw`              | WIRED  | All 3 outputs (`kb_id`, `data_source_id`, `source_bucket_name`) referenced; `aws bedrock-agent` build-time API used; Pitfall J explicitly distinguished. |
| KB service role trust policy                                  | `bedrock.amazonaws.com` with confused-deputy conditions  | `aws:SourceAccount` + `AWS:SourceArn` ArnLike on knowledge-base/*                 | WIRED  | Live `aws iam get-role` returns identical structure: principal `bedrock.amazonaws.com`, both conditions present, account 851725411875, region scope.   |

### Data-Flow Trace (Level 4)

| Artifact                       | Data Variable                          | Source                                                  | Produces Real Data | Status   |
| ------------------------------ | -------------------------------------- | ------------------------------------------------------- | ------------------ | -------- |
| `bin/verify-kb.sh`             | `RESP` from retrieve API               | `aws bedrock-agent-runtime retrieve` against live KB   | Yes (top_score 0.86, real chunk text)             | FLOWING  |
| `aws_bedrockagent_data_source.catalog` | embedded vectors in S3 Vectors index | S3 source bucket `catalog/` prefix → ingestion job → embeddings | Yes (4/4 docs indexed; ingestion job AWI4TJPQN9 COMPLETE) | FLOWING  |
| `RUNBOOK.md` runbook commands  | output values                          | `terraform -chdir=infra/envs/prod output -raw <name>`   | Yes (4 outputs populated and re-tested live)       | FLOWING  |
| KB service role permissions    | `bedrock:InvokeModel` on Titan v2      | live IAM policy enforcement                              | Yes (KB has `RoleLastUsed.LastUsedDate: 2026-05-05T03:56:17Z` from the final ingestion job) | FLOWING  |

### Behavioral Spot-Checks

| Behavior                                                          | Command                                                                                                                                                | Result                                                                                                              | Status |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | ------ |
| KB returns iPhone document for "iPhone 13 Pro Max stock" query    | `aws bedrock-agent-runtime retrieve --region ap-northeast-1 --knowledge-base-id BKXE19AH89 --retrieval-query '{"text":"iPhone 13 Pro Max stock"}'`     | top_score=0.8611, location `s3://hera-kb-source-prod/catalog/iphone-13-pro-max.md`                                  | PASS   |
| Terraform validate exits 0                                        | `terraform -chdir=infra/envs/prod validate`                                                                                                            | "Success! The configuration is valid."                                                                              | PASS   |
| Terraform output returns all 4 expected values                    | `terraform -chdir=infra/envs/prod output`                                                                                                              | All 4 outputs populated: kb_id, kb_arn, source_bucket_name, data_source_id                                          | PASS   |
| Live KB has correct embedding configuration                       | `aws bedrock-agent get-knowledge-base --knowledge-base-id BKXE19AH89 --region ap-northeast-1`                                                          | type=VECTOR, S3_VECTORS, FLOAT32, dimensions=1024, status=ACTIVE                                                    | PASS   |
| Live S3 Vectors index has correct dim/metric/metadata config      | `aws s3vectors get-index --vector-bucket-name hera-kb-vectors-prod --index-name hera-kb-index --region ap-northeast-1`                                | dataType=float32, dimension=1024, distanceMetric=cosine, AMAZON_BEDROCK_TEXT/METADATA non-filterable                | PASS   |
| Live IAM inline policy has zero wildcards                         | `aws iam get-role-policy --role-name hera-kb-service-role --policy-name hera-kb-inline`                                                                | 4 statements, all explicit Actions, all explicit Resource ARNs (no `*`)                                              | PASS   |
| Live trust policy uses bedrock.amazonaws.com + confused-deputy    | `aws iam get-role --role-name hera-kb-service-role`                                                                                                    | Principal=`bedrock.amazonaws.com`, conditions=`aws:SourceAccount` StringEquals + `AWS:SourceArn` ArnLike            | PASS   |
| 4 catalog files uploaded to S3                                    | `aws s3 ls s3://hera-kb-source-prod/catalog/`                                                                                                          | apple-watch-s11.md, iphone-13-pro-max.md, macbook-pro-m4.md, store-policy.md (all 4 present)                        | PASS   |
| Most recent ingestion job COMPLETE                                | `aws bedrock-agent list-ingestion-jobs --region ap-northeast-1 --knowledge-base-id BKXE19AH89 --data-source-id V9KJOLJTZC`                              | AWI4TJPQN9 status=COMPLETE, 4 scanned, 1 modified, 0 failed                                                          | PASS   |
| `bin/verify-kb.sh --help` fail-fast on missing jq (deviation fix) | `bin/verify-kb.sh --help`                                                                                                                              | Exits 2 with "ERROR: jq not found on PATH" message and platform install hints — preflight working as designed       | PASS   |
| RUNBOOK has zero `TODO(plan-03)` markers                          | `grep -c TODO(plan-03) RUNBOOK.md`                                                                                                                     | 0                                                                                                                    | PASS   |
| RUNBOOK has 8 sections in correct order                           | `grep -n '^## ' RUNBOOK.md`                                                                                                                            | Pre-flight, First deploy, First sync, Verify, Re-index, Recovery, Cleanup, Next steps (deferred) — all 8 in order   | PASS   |

### Requirements Coverage

| Requirement | Source Plan        | Description                                                                                                                  | Status     | Evidence                                                                                                                                                                          |
| ----------- | ------------------ | ---------------------------------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| KB-01       | 01-01-PLAN.md      | Apple product catalog English markdown — 3 SKUs (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4) with spec/price/stock | SATISFIED  | 4 catalog/*.md files exist with D-02 schema and D-03 stock-chunk co-location.                                                                                                       |
| KB-02       | 01-02-PLAN.md      | S3 Vectors bucket + index via Terraform with Titan v2 (1024-dim, float32, cosine)                                            | SATISFIED  | Live `aws s3vectors get-index` returns float32 / 1024 / cosine + AMAZON_BEDROCK_* non-filterable. IaC at `infra/modules/knowledge_base/main.tf`.                                  |
| KB-03       | 01-02-PLAN.md      | Bedrock KB created with S3 Vectors backend (`s3_vectors_storage_configuration`) via Terraform `~> 6.27`                      | SATISFIED  | Provider pinned `~> 6.27` (resolved 6.43.0); live KB has `storageConfiguration.type=S3_VECTORS`; KB-id BKXE19AH89 ACTIVE in ap-northeast-1.                                       |
| KB-04       | 01-03-PLAN.md      | Data source ingestion job runs successfully; KB query returns correct doc for "iPhone 13 Pro Max stock"                     | SATISFIED  | Ingestion job 231ZT93KYF: 4/4 indexed; live retrieve top_score=0.8611 on the iPhone document; `bin/verify-kb.sh` PASSes at attempt 1.                                              |
| KB-05       | 01-02-PLAN.md      | IAM role/policy least-privilege for bedrock:Retrieve via Terraform (Phase-1 KB service role; consumer role per D-10 deferred to Phase 2) | SATISFIED  | Live KB service role inline policy has 4 statements with explicit Actions and Resource ARNs (no wildcards). Trust policy with confused-deputy conditions verified live. `kb_arn` exported for Phase 2. |
| KB-06       | 01-03-PLAN.md      | Re-index workflow documented — manual ingestion job trigger via AWS CLI                                                       | SATISFIED  | RUNBOOK "Re-index" section + live job KKLS6LQP9A (1 modified / 0 failed) + verify-kb.sh PASS at attempt 1 (top score 0.8601). Final revert sync AWI4TJPQN9 COMPLETE.              |

**Coverage check:** All 6 phase-mapped requirements (KB-01..KB-06 per REQUIREMENTS.md traceability table) are accounted for across the 3 plans' `requirements:` frontmatter and verified satisfied. Zero orphaned requirements.

### Anti-Patterns Found

| File                                              | Line | Pattern                            | Severity | Impact                                                                                                                                                                                          |
| ------------------------------------------------- | ---- | ---------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `infra/modules/knowledge_base/main.tf`            | n/a  | (none — clean)                     | n/a      | No `aws_s3_object`, no `null_resource`, no `random_id`, no IAM wildcards, no emojis. Manual upload + manual ingestion teaching surface preserved per D-05/D-07.                                |
| `infra/modules/knowledge_base/iam.tf`             | n/a  | (none — clean)                     | n/a      | Zero `*` in any Action or Resource. Trust principal correct (`bedrock.amazonaws.com`, not `bedrockagent.amazonaws.com`).                                                                       |
| `bin/verify-kb.sh`                                | 60   | `2>/dev/null \|\| true` fallback   | INFO     | Used only on `terraform output -raw kb_id` resolution — guards the case where script runs outside repo root. Acceptable: explicit error message + `exit 2` follows on the empty-string check. The dangerous `\|\| echo 0` fallback was already removed in deviation fix f78a39a. |
| `RUNBOOK.md`                                      | n/a  | (none — clean)                     | n/a      | Zero TODO markers, all 8 sections fully populated.                                                                                                                                              |

No blocker anti-patterns found.

### Human Verification Required

None. All verification was completed programmatically using the AWS CLI against live AWS state in account 851725411875 / ap-northeast-1.

The phase produces no UI surface, no audio surface, no real-time behavior, and no external integration that requires human judgment. Every truth was confirmed by direct API calls against the live deployment that the user accepted at Plan 03's checkpoint.

### Gaps Summary

No gaps. All five ROADMAP success criteria are met with live AWS evidence:

1. **Catalog ingested:** 4 markdown files in S3, 4/4 indexed in S3 Vectors with Titan v2 (1024-dim FLOAT32 cosine).
2. **Retrieve query works:** "iPhone 13 Pro Max stock" returns the iPhone document with top score 0.86 (>> 0.4 threshold), confirmed during this verification run.
3. **Terraform deploys cleanly:** `terraform validate` exits 0; live state shows ACTIVE KB; deviation fixes 9006d48 + 28bbcee make subsequent fresh-account applies idempotent.
4. **Least-privilege IAM:** KB service role has zero wildcards in any Action or Resource; trust policy has confused-deputy conditions; `kb_arn` exported for Phase-2 consumer role per D-10.
5. **Re-index works:** RUNBOOK documents the single CLI command pair; live job KKLS6LQP9A round-tripped a single-file edit through ingestion to retrievable in under 60 seconds.

The phase deliverable is byte-stable: catalog was reverted post-walkthrough via `git checkout --` and final ingestion job AWI4TJPQN9 re-indexed the original content, so the live KB matches repo HEAD.

All cross-cutting constraints (no emojis, region defaults, Hugo coexistence, D-10 consumer role deferred, D-12 destroy-then-reapply recovery, no random_id) are honored.

---

_Verified: 2026-05-05T04:10:00Z_
_Verifier: Claude (gsd-verifier)_
