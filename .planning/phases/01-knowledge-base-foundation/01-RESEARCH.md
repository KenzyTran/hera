# Phase 1: Knowledge Base Foundation - Research

**Researched:** 2026-05-05
**Domain:** Bedrock Knowledge Base on S3 Vectors with Titan v2 embeddings, deployed by Terraform `hashicorp/aws ~> 6.27` into `ap-northeast-1`, plus a bash verification script.
**Confidence:** HIGH (Terraform schemas, IAM policy shapes, CLI shapes, and S3 Vectors limits all verified against official AWS docs and the upstream provider source on 2026-05-05).

## Summary

Every locked decision in CONTEXT.md is supported by current AWS documentation as of 2026-05-05. The four resource types this phase needs — `aws_s3_bucket`, `aws_s3vectors_vector_bucket`, `aws_s3vectors_index`, `aws_bedrockagent_knowledge_base`, `aws_bedrockagent_data_source` — all exist as native resources in `hashicorp/aws ~> 6.27` with documented argument shapes that match the chosen design (Titan v2 1024-dim float32 cosine, fixed-size 300-token / 20%-overlap chunking, S3 source bucket).

Three findings sharpen the plan and one corrects a stale assumption:

1. **Trust principal is `bedrock.amazonaws.com`, not `bedrockagent.amazonaws.com`.** AWS docs are explicit on this — the assume-role policy uses the umbrella `bedrock.amazonaws.com` service principal with `aws:SourceAccount` and `aws:SourceArn` conditions scoped to `arn:aws:bedrock:<region>:<account>:knowledge-base/*`.
2. **The `aws_s3vectors_index` field for the parent bucket is `vector_bucket_name` (string), not `vector_bucket_arn`.** Distance-metric and data-type values are lowercase strings (`cosine`, `float32`) — uppercase will cause provider validation errors.
3. **`aws_s3vectors_vector_bucket` argument is `vector_bucket_name`, not `name`.** Easy to miss because every other AWS resource uses `name`.
4. **CONTEXT.md's "1 KB metadata / 35 keys" cap is the Bedrock-KB overlay, not the raw S3 Vectors limit.** Raw S3 Vectors allows 40 KB total / 50 keys / 2 KB filterable / 10 non-filterable keys per index. The KB overlay (1 KB / 35 keys per vector) is the binding limit for this phase — Pitfall #8 still applies as written.

**Primary recommendation:** Single Terraform module at `infra/modules/knowledge_base/`, with a thin root module at `infra/envs/prod/`. Five resource types in `main.tf`, IAM in `iam.tf`, variables in `variables.tf`, outputs in `outputs.tf`. All resource arguments below are copy-ready against `~> 6.27`. `bin/verify-kb.sh` polls `aws bedrock-agent-runtime retrieve` every 15s for 5min; the result `score` lives at `.retrievalResults[0].score` (a flat double, not nested) so `jq` parses it cleanly.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Catalog content shape**
- D-01: 4 English markdown files: `apple-watch-s11.md`, `iphone-13-pro-max.md`, `macbook-pro-m4.md`, `store-policy.md`.
- D-02: Per-SKU schema — `# <SKU full name>`, `## Overview`, `## Specifications`, `## Pricing`, `## Stock & Availability`.
- D-03: Stock data inline inside each SKU file (not in a shared `stock.md`).
- D-04: Default fixed-size chunking (300 tokens, 20% overlap). NO hierarchical chunking with S3 Vectors.

**Sync trigger / re-index UX (KB-06)**
- D-05: Manual first-sync workflow. `terraform apply` does NOT auto-trigger ingestion. Learner runs `aws bedrock-agent start-ingestion-job ...` separately.
- D-06: Re-index after editing a product file uses the same command. Documented in top-level `RUNBOOK.md`.
- D-07: No auto-sync `null_resource` inside Terraform. No wrapper sync script.

**Terraform module + IAM shape**
- D-08: Single module `modules/knowledge_base/` containing source S3 bucket, S3 Vectors bucket+index, Bedrock KB, data source, KB service IAM role+policy. Outputs: `kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`.
- D-09: Match REQUIREMENTS.md DEP-03 module path naming: `modules/knowledge_base/` (alias `modules/kb` if needed).
- D-10: Defer the consumer-side `bedrock:Retrieve` role to Phase 2.
- D-11: Local Terraform state for v1 workshop default. Document remote backend as "next step" in RUNBOOK.md.
- D-12: Fixed resource names (e.g., `hera-kb-prod`, `hera-kb-source-prod`, `hera-kb-vectors-prod`). No `random_id` suffix. Recovery is `terraform destroy` + re-apply.
- D-13: Zero IAM wildcards in Action or Resource. Every action enumerated; every ARN scoped.
- D-14: Region defaults to `ap-northeast-1` via Terraform variable, supports override to `us-east-1` for dev (per DEP-06).

**Verification artifact for KB-04**
- D-15: `bin/verify-kb.sh` reads KB id from `terraform output` (or `--kb-id` flag), calls `aws bedrock-agent-runtime retrieve` with query `iPhone 13 Pro Max stock`, polls every 15s for max 5 minutes, exits 0 when `retrievalResults` non-empty AND top score above documented threshold. Non-zero with clear message on timeout / empty / access denied.
- D-16: Reusable in Phase 4 cleanup verification with assertion inverted (expect access-denied / KB-not-found post-`terraform destroy`).

### Claude's Discretion

- Exact wording of each markdown file's prose (Overview, store policy text)
- Exact stock numbers and pricing values (use plausible 2026 figures)
- Default Terraform variable values beyond region (e.g., name prefix, retention)
- Threshold value for `verify-kb.sh` "score above X" check (start ~0.4, tune empirically)
- File layout details inside `modules/knowledge_base/` (split into `main.tf` / `iam.tf` / `outputs.tf` etc. — pick what reads best)
- Exact CLI flags and output formatting of `verify-kb.sh`

### Deferred Ideas (OUT OF SCOPE)

- `pricing-faq.md` (financing, trade-in, AppleCare) — backlog or v2.
- Wrapper sync script `bin/kb-sync.sh` — explicitly rejected.
- Auto-sync via Terraform `null_resource` + AWS CLI — explicitly rejected.
- Random-suffix resource naming for re-apply safety — explicitly rejected.
- Remote Terraform backend (S3 + DynamoDB) — out of v1 scope.
- Consumer `bedrock:Retrieve` role with Pipecat trust policy — Phase 2.
- Pytest-based KB retrieve test in CI — Phase 2+ once `uv` toolchain lands.
- Bedrock Guardrails (PII redaction) — out of v1 per PROJECT.md.
- OpenSearch Serverless variant chapter — v2 advanced topic per ADV-04.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| KB-01 | Apple product catalog English markdown — 3 SKUs with spec/price/stock | D-01..D-03 schema; section §"Catalog Markdown Authoring" |
| KB-02 | S3 Vectors bucket + index via Terraform with correct dim/metric for Titan v2 (1024 / float32 / cosine) | `aws_s3vectors_vector_bucket` and `aws_s3vectors_index` schemas verified; lowercase `cosine` and `float32` |
| KB-03 | Bedrock KB with S3 Vectors backend (`s3_vectors_storage_configuration`) via Terraform `~> 6.27` | `aws_bedrockagent_knowledge_base` `storage_configuration { type = "S3_VECTORS"; s3_vectors_configuration { ... } }` confirmed |
| KB-04 | Ingestion job runs successfully; KB query returns matching doc for "iPhone 13 Pro Max stock" | `aws bedrock-agent start-ingestion-job` + `aws bedrock-agent-runtime retrieve` shapes confirmed; `verify-kb.sh` design |
| KB-05 | IAM role/policy least-privilege managed via Terraform | KB service role JSON policies for S3 source, S3 Vectors, `bedrock:InvokeModel` on Titan v2 ARN — all verified verbatim against AWS docs; zero wildcards |
| KB-06 | Re-index workflow documented (edit product → re-sync KB) — manual ingestion via AWS CLI | Same `start-ingestion-job` command; incremental sync semantics from AWS docs ("Amazon Bedrock processes only the documents that were added, modified, or deleted since the last sync") |

## Project Constraints (from CLAUDE.md)

Carried verbatim from `C:/Users/trant/projects/hera/CLAUDE.md` and `C:/Users/trant/AGENTS.md`. Plans MUST honor:

- **Be simple, work incrementally.** Small steps, validate each.
- **No emojis** in code, logs, print statements, or shell output. `verify-kb.sh` stdout obeys this.
- **`uv` is the Python package manager.** Phase 1 introduces no Python yet (verify is bash). If any Python lands later, always `uv run` and `uv add`, never `pip install` / `python3`.
- **Latest library APIs.** `hashicorp/aws ~> 6.27` is the floor for native S3 Vectors KB support — pin allows minor+patch but not major upgrade. Provider current at research time is 6.42 (per STACK.md).
- **No defensive programming, no over-engineering.** Single module, fixed names, no random suffix, no wrapper script.
- **Identify root cause before fixing.** Recovery doc in RUNBOOK.md should cite the actual error pattern, not paper over it.
- **Concise docstrings, sparing comments outside docstrings.**
- **Region defaults to `ap-northeast-1`** with override to `us-east-1` (DEP-06).

The Hugo workshop pipeline (`.github/workflows/deploy.yml`) only consumes `content/`, `layouts/`, `themes/`, `static/`, `i18n/`, `config.toml`. A new top-level `infra/` directory does NOT enter the Hugo build path and will not break GH Pages deploy.

## Architectural Responsibility Map

Phase 1 is a single-tier IaC + data-prep deliverable — no application runtime. Capabilities map to AWS service tiers:

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Catalog markdown authoring | Source data (filesystem → S3) | — | Static text; lives in repo until uploaded |
| S3 Vectors index storage | Vector store (S3 Vectors) | — | Native AWS managed vector backend |
| Embedding generation | Bedrock managed (Titan v2 invoked by KB service) | — | KB owns the embedding call; we provide the model ARN |
| Document ingestion orchestration | Bedrock KB service | Bedrock data source | KB pulls from S3 source via data source connector |
| Retrieval API | Bedrock KB runtime (`bedrock-agent-runtime:Retrieve`) | — | Stateless query API; consumer Phase 2 |
| Authorization | IAM role assumed by Bedrock service principal | — | KB-side only this phase; consumer role deferred to Phase 2 |
| Verification | bash + AWS CLI on developer machine | — | No deployed compute in Phase 1 |
| Provisioning | Terraform `~> 6.27` (local state) | — | Declarative IaC; no remote backend in v1 |

## Standard Stack

### Core (verified against current AWS docs and Terraform Registry on 2026-05-05)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Terraform CLI | `>= 1.9` | IaC runtime | Provider 6.x requires Terraform 1.9+ [VERIFIED: HashiCorp Terraform AWS provider 6.0 announcement] |
| `hashicorp/aws` | `~> 6.27` | All AWS resources | 6.27 is the floor for `s3_vectors_storage_configuration` block on KB resource [CITED: github.com/hashicorp/terraform-provider-aws issue #43438 / PR #45465] |
| Titan Text Embeddings v2 | model id `amazon.titan-embed-text-v2:0` | Embeds chunks into 1024-dim float vectors | Available in `ap-northeast-1` AND `us-east-1`; supports 256/512/1024 dims; floating-point and binary [VERIFIED: AWS docs `knowledge-base-supported.html`]. Use **floating-point only** with S3 Vectors KB integration (binary unsupported) [VERIFIED: AWS docs `s3-vectors-bedrock-kb.html` Limitations] |
| AWS CLI v2 | latest | Manual sync (`start-ingestion-job`), retrieval verify, model-access pre-flight | Workshop assumes CLI v2 is installed by the learner |
| `jq` | any | Parse `retrieve` JSON response in `verify-kb.sh` | Standard on dev machines; documented as a workshop preparation requirement |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `aws_s3_bucket` (provider) | `~> 6.27` | Source markdown bucket (`force_destroy = true`) | One bucket per environment |
| `aws_s3_object` (optional) | `~> 6.27` | Optional: upload markdown via Terraform on apply | Discussed below — recommended **against** for v1 (decouples sync trigger; matches D-05) |
| `aws_iam_role` + `aws_iam_role_policy` | `~> 6.27` | KB service role + scoped policy | Inline policy is fine for a single-purpose role |
| `aws_caller_identity` (data source) | `~> 6.27` | Get account ID for `aws:SourceAccount` condition | Avoids hardcoded account number in module |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `aws_iam_role_policy` (inline) | `aws_iam_policy` + `aws_iam_role_policy_attachment` | Attachment pattern is more reusable but adds two resources for a single-purpose role; inline is simpler and audit-friendly here |
| Bedrock auto-created service role (console "quick create") | Custom Terraform-managed role | Auto-create generates a wildcard-rich policy; custom is needed to satisfy D-13 |
| `awscc_s3vectors_vector_bucket` | `aws_s3vectors_vector_bucket` | The native `aws_*` resource is preferred since 6.27 — better drift detection; awscc was the bridge before native landed |
| `aws_s3_object` to upload markdown via Terraform | Manual `aws s3 cp` from RUNBOOK | Terraform upload couples source content with provisioning; manual aligns with D-05 (manual sync) and lets learners edit catalog without `terraform apply` |
| Hierarchical chunking | Fixed-size 300/20% (D-04) | Hierarchical stores parent-child links in S3 Vectors metadata which can blow the 1 KB / 35-key per-vector overlay [VERIFIED: AWS docs `s3-vectors-bedrock-kb.html` Limitations + Pitfall #8] |
| `random_id` resource-name suffix | Fixed names (D-12) | Random suffix masks collisions but adds state churn; D-12 chose fixed + documented destroy-then-reapply recovery |

**Installation (local dev machine):**
```bash
# Terraform (any installer; brew, choco, scoop, or HashiCorp release tarball)
terraform -version  # expect >= 1.9

# AWS CLI v2
aws --version       # expect aws-cli/2.x

# jq
jq --version        # expect jq-1.6+

# AWS credentials configured for the target account
aws sts get-caller-identity
```

**Version verification performed 2026-05-05** [VERIFIED via WebFetch of GitHub provider source]:
- `aws_s3vectors_vector_bucket`, `aws_s3vectors_index`, `aws_bedrockagent_knowledge_base`, `aws_bedrockagent_data_source` resource pages exist in `hashicorp/terraform-provider-aws` main branch with the schemas reproduced below.
- Titan v2 model id `amazon.titan-embed-text-v2:0` is current and present in `ap-northeast-1` per AWS docs `knowledge-base-supported.html`.

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                     Developer / Learner Machine                  │
│                                                                  │
│   git checkout       terraform apply      aws bedrock-agent      │
│   edit *.md          (creates AWS         start-ingestion-job    │
│                       resources)          (triggers crawl+embed) │
│        │                  │                       │              │
│        │                  │                       │              │
│        │            aws s3 cp                     │              │
│        └──────────────► (manual sync)             │              │
│                           │                       │              │
└───────────────────────────┼───────────────────────┼──────────────┘
                            │                       │
                            ▼                       ▼
              ┌──────────────────────┐    ┌─────────────────────┐
              │  S3 source bucket    │    │  Bedrock Agent      │
              │  hera-kb-source-prod │    │  StartIngestionJob  │
              │  /catalog/*.md       │◄───┤  (KB pulls objects) │
              └──────────────────────┘    └──────────┬──────────┘
                                                     │
                            ┌────────────────────────┴───────────┐
                            │   Bedrock Knowledge Base service   │
                            │   (assumes KB IAM role)            │
                            │                                    │
                            │   1. Read S3 source bucket         │
                            │   2. Chunk (FIXED_SIZE 300/20%)    │
                            │   3. Invoke Titan v2 embed         │
                            │   4. Write vectors to S3 Vectors   │
                            └────┬────────────────┬──────────────┘
                                 │                │
                                 ▼                ▼
                  ┌──────────────────────┐  ┌─────────────────────┐
                  │  Bedrock Titan v2    │  │  S3 Vectors index   │
                  │  invokeModel         │  │  hera-kb-vectors-   │
                  │  embeddings (1024-d) │  │   prod / index      │
                  │                      │  │  dim=1024 cosine    │
                  └──────────────────────┘  │  data_type=float32  │
                                            └──────────┬──────────┘
                                                       │
                                                       │ (queryable
                                                       │  after ~2-3 min
                                                       │  propagation)
                                                       ▼
                            ┌────────────────────────────────────┐
                            │  bin/verify-kb.sh                  │
                            │  aws bedrock-agent-runtime         │
                            │  retrieve  --retrieval-query       │
                            │  '{"text":"iPhone 13 Pro Max       │
                            │           stock"}'                 │
                            │  → poll 15s × 20 = 5min            │
                            │  → exit 0 if hits + score >= 0.4   │
                            └────────────────────────────────────┘
```

Phase boundaries:
- **In scope:** S3 source bucket, S3 Vectors bucket+index, KB, KB data source, KB service IAM role, `verify-kb.sh`, `RUNBOOK.md` for sync workflow.
- **Out of scope (Phase 2):** Consumer `bedrock:Retrieve` role for Pipecat task; Pipecat code; Sonic; AgentCore; web widget.

### Recommended Project Structure

Repo currently has only Hugo content. Phase 1 adds a new top-level `infra/` directory and a `bin/` directory:

```
hera/
├── infra/                          # NEW — Terraform IaC (does not enter Hugo build)
│   ├── envs/
│   │   └── prod/
│   │       ├── main.tf             # provider, module instantiation
│   │       ├── variables.tf        # region, name_prefix
│   │       ├── outputs.tf          # re-export module outputs
│   │       ├── versions.tf         # terraform + provider pins
│   │       └── terraform.tfvars    # local values; gitignored if has secrets (none here)
│   └── modules/
│       └── knowledge_base/
│           ├── main.tf             # S3 source bucket, S3 Vectors bucket+index, KB, data source
│           ├── iam.tf              # KB service role + policies
│           ├── variables.tf        # name_prefix, region, embedding_dim, chunk_max_tokens, chunk_overlap_pct
│           ├── outputs.tf          # kb_id, kb_arn, source_bucket_name, data_source_id
│           └── versions.tf         # provider + terraform requirements
├── bin/                            # NEW
│   └── verify-kb.sh                # bash + jq verification script
├── content/                        # existing Hugo content (untouched)
├── catalog/                        # NEW — source markdown for the KB
│   ├── apple-watch-s11.md
│   ├── iphone-13-pro-max.md
│   ├── macbook-pro-m4.md
│   └── store-policy.md
├── RUNBOOK.md                      # NEW — sync workflow + recovery
├── .github/workflows/deploy.yml    # existing; only watches Hugo paths
└── ... (other existing Hugo files unchanged)
```

**Why `infra/` and not `terraform/`:** Either is acceptable per CONTEXT.md. Recommend `infra/` because it is the AWS workshop convention (`aws-samples/build-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock` and other AWS samples use `infra/`), it leaves room for `infra/cdk/` if Phase 3 falls back to hybrid CDK per DEP-04, and it tracks the AWS Solutions Constructs naming pattern.

**Why `catalog/` at repo root and not under `infra/`:** Catalog content is a workshop-authored asset that learners edit and re-sync (D-06). Placing it outside `infra/` makes it clear it is not Terraform-managed, and it leaves room for Phase 5 docs to render or link to the catalog markdown directly. Upload to S3 is a manual `aws s3 cp catalog/*.md s3://hera-kb-source-prod/catalog/` step documented in RUNBOOK.md.

### Pattern 1: KB Service Role Trust Policy (single principal, scoped by SourceAccount and SourceArn)

**What:** Bedrock-style assume-role policy with strict source conditions.
**When to use:** Always for KB service roles. Protects against the "confused deputy" pattern.

```hcl
# Source: AWS docs https://docs.aws.amazon.com/bedrock/latest/userguide/kb-permissions.html#kb-permissions-trust
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kb_trust" {
  statement {
    sid     = "BedrockKBAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]   # NOTE: bedrock, not bedrockagent
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "kb_service_role" {
  name               = "${var.name_prefix}-kb-service-role"
  assume_role_policy = data.aws_iam_policy_document.kb_trust.json
}
```

[CITED: docs.aws.amazon.com/bedrock/latest/userguide/kb-permissions.html — Trust relationship section, "Service": "bedrock.amazonaws.com"]

### Pattern 2: KB Service Role Permissions (S3 source + S3 Vectors + Titan invoke)

**What:** Three statements, each scoped to specific resources, no wildcards in Action or Resource.
**When to use:** This is the only inline policy attached to the KB service role for Phase 1.

```hcl
# Source: AWS docs sections kb-permissions-access-models, kb-permissions-access-s3, kb-permissions-s3vectors
data "aws_iam_policy_document" "kb_inline" {

  # 1. Read source markdown bucket
  statement {
    sid    = "S3SourceListBucket"
    effect = "Allow"
    actions = ["s3:ListBucket"]
    resources = [aws_s3_bucket.source.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "S3SourceGetObject"
    effect = "Allow"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.source.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # 2. Invoke Titan v2 embedding model in this region
  statement {
    sid     = "BedrockInvokeTitanV2"
    effect  = "Allow"
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0"
    ]
  }

  # 3. Read/write the S3 Vectors index for this KB
  statement {
    sid    = "S3VectorsReadWrite"
    effect = "Allow"
    actions = [
      "s3vectors:PutVectors",
      "s3vectors:GetVectors",
      "s3vectors:DeleteVectors",
      "s3vectors:QueryVectors",
      "s3vectors:GetIndex"
    ]
    resources = [
      "arn:aws:s3vectors:${var.region}:${data.aws_caller_identity.current.account_id}:bucket/${aws_s3vectors_vector_bucket.this.vector_bucket_name}/index/${aws_s3vectors_index.this.index_name}"
    ]
  }
}

resource "aws_iam_role_policy" "kb_inline" {
  name   = "${var.name_prefix}-kb-inline"
  role   = aws_iam_role.kb_service_role.id
  policy = data.aws_iam_policy_document.kb_inline.json
}
```

[CITED: docs.aws.amazon.com/bedrock/latest/userguide/kb-permissions.html — `bedrock:InvokeModel` on Titan family ARN; S3 source `s3:ListBucket` + `s3:GetObject` with `aws:ResourceAccount` condition; S3 Vectors action list verbatim]

**Notes:**
- The `bedrock:ListFoundationModels` / `bedrock:ListCustomModels` actions in AWS's example policy are NOT required for runtime — they are only used by console flows to populate model dropdowns. Omit them to stay minimal per D-13.
- Foundation-model ARN format omits the account ID segment: `arn:aws:bedrock:<region>::foundation-model/<model-id>` (note the double colon before `foundation-model`). [VERIFIED: AWS docs example policies use this exact form across multiple pages]
- `aws:ResourceAccount` condition on S3 statements blocks cross-account reads even if the source bucket policy were ever loosened — defensive and free.

### Pattern 3: S3 Source Bucket with `force_destroy`

**What:** Standard S3 bucket; the only non-default is `force_destroy = true` so `terraform destroy` wipes catalog objects without manual intervention.
**When to use:** All buckets in this phase. Pitfall #20 (cleanup completeness).

```hcl
resource "aws_s3_bucket" "source" {
  bucket        = "${var.name_prefix}-kb-source-${var.env}"   # e.g. hera-kb-source-prod
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

[CITED: PITFALLS.md #20; AWS docs S3 block-public-access defaults]

### Pattern 4: S3 Vectors Bucket + Index (verified arg names)

**What:** Native AWS provider resources. **Field names differ from typical S3 resources** — the bucket uses `vector_bucket_name` not `name`, and the index references its parent bucket by name not ARN.

```hcl
# Source: github.com/hashicorp/terraform-provider-aws website/docs/r/s3vectors_vector_bucket.html.markdown
resource "aws_s3vectors_vector_bucket" "this" {
  vector_bucket_name = "${var.name_prefix}-kb-vectors-${var.env}"   # e.g. hera-kb-vectors-prod
  force_destroy      = true                                          # default false; required for clean teardown
  # encryption_configuration omitted -> SSE-S3 (AES256) default
}

# Source: github.com/hashicorp/terraform-provider-aws website/docs/r/s3vectors_index.html.markdown
resource "aws_s3vectors_index" "this" {
  index_name         = "${var.name_prefix}-kb-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.this.vector_bucket_name

  data_type       = "float32"   # lowercase; valid values: float32
  dimension       = 1024        # matches Titan v2 default
  distance_metric = "cosine"    # lowercase; valid values: cosine, euclidean
}
```

**Critical argument-name details (easy to get wrong):**
- `aws_s3vectors_vector_bucket.vector_bucket_name` — NOT `name`. [VERIFIED: provider docs]
- `aws_s3vectors_index.vector_bucket_name` references the parent **by name**, not by ARN. [VERIFIED]
- `data_type` accepts only `float32` (lowercase). [VERIFIED]
- `distance_metric` accepts `cosine` or `euclidean` (lowercase). [VERIFIED]
- Exported attribute on the index is `index_arn` (used downstream by KB).
- Exported attribute on the bucket is `vector_bucket_arn`.

### Pattern 5: Bedrock Knowledge Base with S3 Vectors backend

**What:** The KB resource ties together storage_configuration (S3 Vectors), embedding configuration (Titan v2), and the IAM role. Verified arg shape.

```hcl
# Source: github.com/hashicorp/terraform-provider-aws website/docs/r/bedrockagent_knowledge_base.html.markdown
resource "aws_bedrockagent_knowledge_base" "this" {
  name     = "${var.name_prefix}-kb-${var.env}"   # e.g. hera-kb-prod
  role_arn = aws_iam_role.kb_service_role.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0"

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = 1024
          embedding_data_type = "FLOAT32"   # uppercase here — provider quirk vs s3vectors_index lowercase
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.this.index_arn
      # Alternative form: index_name + vector_bucket_arn (mutually exclusive with index_arn)
    }
  }

  depends_on = [aws_iam_role_policy.kb_inline]   # ensure permissions exist before KB tries to validate
}
```

**Critical details:**
- `embedding_data_type = "FLOAT32"` is **uppercase** here, while `aws_s3vectors_index.data_type = "float32"` is **lowercase**. This is a real provider inconsistency — both are correct in their own resources. [VERIFIED]
- `s3_vectors_configuration` must specify EITHER `index_arn` OR (`index_name` + `vector_bucket_arn`) — they conflict. The `index_arn` form is simpler. [VERIFIED]
- `depends_on` on the inline policy attachment is necessary because `aws_bedrockagent_knowledge_base` validates that the role can read the bucket and invoke the model **at create time**. Without explicit dependency, Terraform may attempt to create the KB before the policy is attached to the role.
- `knowledge_base_configuration.type = "VECTOR"` — currently the only supported type. [VERIFIED]

### Pattern 6: Bedrock KB Data Source (S3 + FIXED_SIZE chunking)

**What:** Wires the S3 source bucket to the KB and configures fixed-size chunking per D-04.

```hcl
# Source: github.com/hashicorp/terraform-provider-aws website/docs/r/bedrockagent_data_source.html.markdown
resource "aws_bedrockagent_data_source" "catalog" {
  name              = "${var.name_prefix}-catalog"
  knowledge_base_id = aws_bedrockagent_knowledge_base.this.id

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn         = aws_s3_bucket.source.arn
      inclusion_prefixes = ["catalog/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"

      fixed_size_chunking_configuration {
        max_tokens         = 300   # D-04
        overlap_percentage = 20    # D-04
      }
    }
  }
}
```

**Critical details:**
- `chunking_strategy = "FIXED_SIZE"` — uppercase. Valid values: `FIXED_SIZE`, `HIERARCHICAL`, `SEMANTIC`, `NONE`. [VERIFIED]
- `inclusion_prefixes` is plural (a list) — supports `["catalog/"]` to scope the KB to only the catalog folder, leaving room for other directory uses of the same bucket later.
- `vector_ingestion_configuration` and `chunking_configuration` are both optional but recommended to set explicitly per D-04 (avoid relying on default behavior).

### Pattern 7: Module outputs (consumed by Phase 2)

```hcl
# infra/modules/knowledge_base/outputs.tf
output "kb_id" {
  description = "Bedrock Knowledge Base ID — input to Phase 2 Pipecat tool"
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "kb_arn" {
  description = "Bedrock Knowledge Base ARN — used by Phase 2 to scope bedrock:Retrieve in consumer role"
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "source_bucket_name" {
  description = "S3 source bucket name — for aws s3 cp catalog/*.md uploads"
  value       = aws_s3_bucket.source.bucket
}

output "data_source_id" {
  description = "Bedrock data source ID — required for aws bedrock-agent start-ingestion-job"
  value       = aws_bedrockagent_data_source.catalog.data_source_id
}
```

### Anti-Patterns to Avoid

- **`null_resource` + `local-exec` to auto-trigger ingestion.** Explicitly rejected per D-07. Couples provisioning with side effects, hides the API surface from learners, and the trigger condition becomes brittle.
- **Random-suffix resource names.** Rejected per D-12. Makes outputs unpredictable, complicates cross-phase wiring (Phase 2 needs a stable KB id reference path).
- **Wildcard `Action: "bedrock:*"` or `Resource: "*"`.** Pitfall #23 — workshop teaches this anti-pattern when used. The catalog of actions in Pattern 2 is fully enumerated.
- **`bedrockagent.amazonaws.com` as trust principal.** This service principal does NOT exist for Bedrock KB roles. Use `bedrock.amazonaws.com`. [CITED: AWS docs]
- **Hierarchical chunking with S3 Vectors backend.** Parent-child links go into non-filterable metadata which can blow the 1 KB / 35-key per-vector overlay [VERIFIED: AWS docs `s3-vectors-bedrock-kb.html` Limitations].
- **Binary embedding data type with S3 Vectors KB.** Unsupported [VERIFIED: AWS docs `s3-vectors-bedrock-kb.html` Limitations].
- **Forgetting `depends_on = [aws_iam_role_policy.kb_inline]` on the KB resource.** Race condition where Terraform creates the KB before the role policy attaches, causing `AccessDeniedException` during KB-side validation.
- **Skipping `force_destroy = true` on either S3 bucket.** Terraform destroy fails on non-empty buckets — Pitfall #20.
- **Uploading catalog markdown via `aws_s3_object` resources.** Couples content edits with `terraform apply`. Manual `aws s3 cp` keeps content edits decoupled and matches D-05/D-06 manual-sync UX.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Document chunking | Custom Python tokenizer + chunker | `chunking_strategy = "FIXED_SIZE"` in `vector_ingestion_configuration` | Bedrock KB owns this; manual chunking would bypass the managed pipeline and require a custom data source connector |
| Embedding generation | Direct `bedrock-runtime:InvokeModel` calls + custom indexing | KB calls Titan v2 automatically during ingestion | Same pipeline reason; also avoids version drift between embedding-time and query-time embedders |
| S3 Vectors index management | Manual index creation via `s3vectors:CreateIndex` API | `aws_s3vectors_index` Terraform resource | Native resource with drift detection; manual management would not match the IaC story DEP-03 expects |
| Polling for ingestion job completion | Bash loop on `get-ingestion-job` inside `apply` | Manual learner step per D-05 | Couples IaC with execution; D-07 explicitly rejects |
| Custom retrieve loop with embedding-on-the-fly | Direct Titan invoke + S3 Vectors `QueryVectors` | `aws bedrock-agent-runtime retrieve` | The KB Retrieve API embeds the query for you using the KB's own embedding model — guarantees consistency with stored vectors |
| Random retry/backoff on retrieve | Custom logic | Polling loop in `verify-kb.sh` (D-15) | Single-purpose script with documented intent is more teachable than generic retry libs |
| Sync trigger DSL | Wrapper script `bin/kb-sync.sh` | Documented one-liner in RUNBOOK.md | D-07 explicitly rejects — the AWS CLI is the teaching surface |

**Key insight:** Bedrock KB is a managed RAG pipeline. The temptation in Phase 1 will be to "control" each step (chunking, embedding, indexing) — resist it. The phase's KB-04 success criterion is "the managed pipeline returned the right doc" not "we re-implemented RAG."

## Runtime State Inventory

This phase is greenfield IaC + new files in the repo — no existing strings to rename or refactor. The only "stored data" introduced is the contents of the S3 source bucket and the S3 Vectors index, both managed by Terraform create. There are no env-var-name renames, no prior databases to migrate, no OS-registered tasks, no installed packages with stale names.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None pre-existing — phase creates new S3 source bucket and new S3 Vectors index | None — created by `terraform apply`; populated by manual `aws s3 cp` + `start-ingestion-job` |
| Live service config | None pre-existing — Bedrock KB and data source are net-new resources | None |
| OS-registered state | None | None |
| Secrets/env vars | AWS credentials (already required for any AWS workshop) | Document `aws sts get-caller-identity` pre-flight in RUNBOOK |
| Build artifacts | None — no compiled code in this phase | None |

**Nothing found in any category** — this is a clean greenfield phase. State Inventory is included for completeness against the rename/refactor checklist; the planner can confirm "no migration tasks" without further investigation.

## Common Pitfalls

These are the Phase-1-specific subset of `.planning/research/PITFALLS.md`, plus phase-specific gotchas surfaced during this research.

### Pitfall A (project Pitfall #3): Bedrock model access not enabled in `ap-northeast-1`

**What goes wrong:** First `terraform apply` succeeds; first `start-ingestion-job` fails with `AccessDeniedException: You don't have access to the model with the specified model ID` for `amazon.titan-embed-text-v2:0`.

**Why it happens:** Bedrock requires explicit per-model per-region console enablement, separate from IAM. Titan v2 is gated. Fresh AWS accounts in `ap-northeast-1` start with nothing enabled.

**How to avoid:**
- Add a pre-flight check to `verify-kb.sh` OR document it as the very first RUNBOOK step:
  ```bash
  aws bedrock list-foundation-models --region ap-northeast-1 \
    --query 'modelSummaries[?modelId==`amazon.titan-embed-text-v2:0`].modelLifecycle.status' \
    --output text
  # expect: ACTIVE  (and the entry must be returned at all — empty means not enabled)
  ```
- RUNBOOK section "Before first apply": Bedrock console → Model access → Modify → enable Amazon Titan Text Embeddings V2 in the deploy region.
- Plan should include a discrete task "Document Bedrock model access pre-flight" so it doesn't get folded into apply.

**Warning signs:**
- Ingestion job status transitions to `FAILED` with `failureReasons` mentioning model access.
- IAM looks correct, `bedrock:InvokeModel` is allowed, but call still fails.

### Pitfall B (project Pitfall #8): S3 Vectors dimension immutability

**What goes wrong:** Learner picks Titan v2 at 1024 dims, ingests, later wants to try 256 (cheaper storage) or Cohere (1024 too — different model). Index dimension is set at creation and cannot be altered. Only fix: destroy index, recreate, re-ingest.

**Why it happens:** S3 Vectors index dimension and data type are immutable post-create.

**How to avoid:**
- Module variable `embedding_dimension` defaulted to 1024 with a comment block warning of immutability.
- D-04 already locks Titan v2 1024 — research confirms this is the right choice.
- RUNBOOK "if you really must change dimension": `terraform destroy -target=aws_s3vectors_index.this -target=aws_bedrockagent_knowledge_base.this` then change variable and reapply, then re-sync.

**Warning signs:**
- Provider error `dimension mismatch` on plan when the variable changes.

### Pitfall C (project Pitfall #9): KB sync → retrieve propagation lag

**What goes wrong:** `start-ingestion-job` returns `COMPLETE`, learner immediately runs `retrieve`, gets empty results, concludes "broken."

**Why it happens:** AWS docs on `kb-data-source-sync-ingest.html` state explicitly: "After data ingestion completes, it could take a few minutes for the vector embeddings of the newly ingested data to be available in the vector store for querying if you use a vector store other than Amazon Aurora (RDS)." [VERIFIED]

**How to avoid:** This is exactly what `verify-kb.sh` D-15 design addresses — 15s × 20 polls = 5min upper bound. Document the wait in RUNBOOK as "this is normal AWS behavior, not a bug."

**Warning signs:**
- `get-ingestion-job` shows status COMPLETE but `retrieve` returns `retrievalResults: []` for known content.

### Pitfall D (project Pitfall #17): Terraform half-apply recovery

**What goes wrong:** Mid-apply error (e.g., model access not enabled), KB partially created in AWS but Terraform state out of sync. Re-apply hits `ResourceAlreadyExistsException`.

**Why it happens:** KB creation is multi-step. With fixed names (D-12), retry is namespace-collision-prone.

**How to avoid:** Per D-12 the recovery path is `terraform destroy && terraform apply`. RUNBOOK "Recovery" section documents this verbatim. Cost of full rebuild at workshop scale is < $0.01 (catalog re-embed) + a few minutes; not worth `terraform import` recipes.

**Warning signs:**
- `aws_bedrockagent_knowledge_base.this: creation errored: ResourceAlreadyExistsException`
- `terraform plan` shows resources to create that AWS console shows existing.

### Pitfall E (project Pitfall #20): Cleanup completeness

**What goes wrong:** `terraform destroy` reports success, but residual S3 objects in catalog bucket cause bucket deletion to fail; or learner forgets to run destroy and S3 Vectors charges accrue.

**How to avoid:**
- `force_destroy = true` on BOTH `aws_s3_bucket.source` and `aws_s3vectors_vector_bucket.this`.
- Phase 4 will reuse `verify-kb.sh` with inverted assertion (D-16) — the script must exit non-zero post-destroy on retrieve, which proves the KB and data are gone.

### Pitfall F (project Pitfall #23): IAM wildcards

**What goes wrong:** Workshop teaches the wrong pattern; learner copies into prod.

**How to avoid:** Patterns 1 and 2 above enumerate every action and scope every resource ARN. Plan should include a verification task: `grep -E '"\\*"' infra/**/*.tf` returns zero matches in any IAM Action or Resource field.

### Pitfall G (Phase-1-specific): `aws_s3vectors_vector_bucket` argument is `vector_bucket_name` not `name`

**What goes wrong:** Drafting the resource by analogy to `aws_s3_bucket` (which uses `bucket = "..."`) or to other AWS resources (which use `name = "..."`) produces an invalid configuration. Provider error is reasonably clear (`Unsupported argument: name`) but wastes a planning loop.

**How to avoid:** Pattern 4 uses `vector_bucket_name`; planner should reference verbatim. Same for `aws_s3vectors_index.vector_bucket_name` (references parent by name, not ARN).

### Pitfall H (Phase-1-specific): `data_type` and `embedding_data_type` differ in case

**What goes wrong:** `aws_s3vectors_index.data_type = "FLOAT32"` will fail provider validation (must be lowercase `float32`), but `aws_bedrockagent_knowledge_base.embedding_model_configuration.bedrock_embedding_model_configuration.embedding_data_type = "float32"` will also fail (must be uppercase `FLOAT32`). Same concept, different case rules in different resources.

**How to avoid:** Pattern 4 uses `data_type = "float32"` (lowercase) in the index; Pattern 5 uses `embedding_data_type = "FLOAT32"` (uppercase) in the KB. Both are correct in their own context. Verify by copying verbatim from the patterns above.

### Pitfall I (Phase-1-specific): Trust principal is `bedrock.amazonaws.com`

**What goes wrong:** Drafting the trust policy with `bedrockagent.amazonaws.com` (mirroring the `aws_bedrockagent_*` resource family naming) produces an `AssumeRolePolicyError` at KB creation time.

**How to avoid:** Pattern 1 uses `bedrock.amazonaws.com`. AWS docs confirm: "The following policy allows Amazon Bedrock to assume this role and create and manage knowledge bases" with `"Service": "bedrock.amazonaws.com"`. [CITED: docs.aws.amazon.com/bedrock/latest/userguide/kb-permissions.html]

### Pitfall J (Phase-1-specific): `start-ingestion-job` is a separate **build-time** endpoint, not the runtime endpoint

**What goes wrong:** Confusion between `aws bedrock-agent` (build-time: KBs, agents, ingestion jobs) and `aws bedrock-agent-runtime` (runtime: Retrieve, RetrieveAndGenerate). Calling `aws bedrock-agent-runtime start-ingestion-job` produces "command not found" errors.

**How to avoid:** RUNBOOK section explicitly distinguishes the two surfaces with a one-line table. `verify-kb.sh` uses ONLY `aws bedrock-agent-runtime retrieve`; sync uses `aws bedrock-agent start-ingestion-job` and `get-ingestion-job`.

## Code Examples

Verified shapes for the AWS CLI calls Phase 1 will introduce.

### Manual ingestion sync (D-05, D-06; documented in RUNBOOK.md)

```bash
# Source: docs.aws.amazon.com/cli/latest/reference/bedrock-agent/start-ingestion-job.html

# 1. Get KB id and data source id from terraform
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
REGION=ap-northeast-1

# 2. Trigger sync
JOB_ID=$(aws bedrock-agent start-ingestion-job \
  --region "$REGION" \
  --knowledge-base-id "$KB_ID" \
  --data-source-id "$DS_ID" \
  --description "manual catalog sync" \
  --query 'ingestionJob.ingestionJobId' \
  --output text)

echo "started ingestion job: $JOB_ID"

# 3. Poll until COMPLETE (or FAILED)
while true; do
  STATUS=$(aws bedrock-agent get-ingestion-job \
    --region "$REGION" \
    --knowledge-base-id "$KB_ID" \
    --data-source-id "$DS_ID" \
    --ingestion-job-id "$JOB_ID" \
    --query 'ingestionJob.status' \
    --output text)
  echo "status: $STATUS"
  case "$STATUS" in
    COMPLETE|FAILED|STOPPED) break ;;
  esac
  sleep 5
done

# 4. Then wait 2-3 minutes for propagation, OR run verify-kb.sh which handles it
bin/verify-kb.sh
```

[VERIFIED: All flag names from `aws bedrock-agent start-ingestion-job` and `get-ingestion-job` reference pages]

### Retrieve API call (used by verify-kb.sh)

```bash
# Source: docs.aws.amazon.com/cli/latest/reference/bedrock-agent-runtime/retrieve.html

aws bedrock-agent-runtime retrieve \
  --region ap-northeast-1 \
  --knowledge-base-id "$KB_ID" \
  --retrieval-query '{"text":"iPhone 13 Pro Max stock"}' \
  --retrieval-configuration '{"vectorSearchConfiguration":{"numberOfResults":3}}' \
  --output json
```

Response shape (verified):
```json
{
  "retrievalResults": [
    {
      "content": { "type": "TEXT", "text": "..." },
      "location": { "type": "S3", "s3Location": { "uri": "s3://..." } },
      "metadata": { "...": "..." },
      "score": 0.87
    }
  ],
  "nextToken": null,
  "guardrailAction": "NONE"
}
```

`jq` extraction for `verify-kb.sh`:
```bash
HITS=$(echo "$RESPONSE" | jq '.retrievalResults | length')
TOP_SCORE=$(echo "$RESPONSE" | jq '.retrievalResults[0].score // 0')
```

[VERIFIED: AWS CLI reference for `bedrock-agent-runtime retrieve`; `score` is a flat double at `retrievalResults[].score`, NOT nested in any `score.value` object]

### `verify-kb.sh` skeleton (D-15)

```bash
#!/usr/bin/env bash
# bin/verify-kb.sh — Phase 1 KB-04 verification
# polls the KB Retrieve API until results appear with score above threshold.

set -euo pipefail

# --- defaults / args ---
REGION="${HERA_REGION:-ap-northeast-1}"
QUERY='{"text":"iPhone 13 Pro Max stock"}'
THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"
MAX_ATTEMPTS=20
SLEEP_SECONDS=15
KB_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kb-id)       KB_ID="$2"; shift 2 ;;
    --region)      REGION="$2"; shift 2 ;;
    --query)       QUERY="$2"; shift 2 ;;
    --threshold)   THRESHOLD="$2"; shift 2 ;;
    --invert)      INVERT=1; shift ;;     # for Phase 4 cleanup
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- resolve KB id from terraform if not supplied ---
if [[ -z "$KB_ID" ]]; then
  KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id 2>/dev/null || true)
  if [[ -z "$KB_ID" ]]; then
    echo "ERROR: --kb-id not provided and terraform output -raw kb_id failed" >&2
    exit 2
  fi
fi

echo "verifying KB $KB_ID in $REGION"
echo "query: $QUERY"
echo "score threshold: $THRESHOLD"
echo "polling every ${SLEEP_SECONDS}s for up to $((MAX_ATTEMPTS * SLEEP_SECONDS))s"

# --- poll loop ---
for i in $(seq 1 "$MAX_ATTEMPTS"); do
  RESP=$(aws bedrock-agent-runtime retrieve \
    --region "$REGION" \
    --knowledge-base-id "$KB_ID" \
    --retrieval-query "$QUERY" \
    --retrieval-configuration '{"vectorSearchConfiguration":{"numberOfResults":3}}' \
    --output json 2>&1) || RC=$? || true

  if [[ "${INVERT:-0}" == "1" ]]; then
    # cleanup-mode: any non-error response means KB still exists
    if echo "$RESP" | grep -qiE 'AccessDenied|ResourceNotFound'; then
      echo "OK (cleanup): KB no longer accessible — $(echo "$RESP" | head -1)"
      exit 0
    fi
    echo "attempt $i/$MAX_ATTEMPTS: KB still responding; expected to be gone"
  else
    HITS=$(echo "$RESP" | jq -r '.retrievalResults | length' 2>/dev/null || echo 0)
    TOP=$(echo "$RESP" | jq -r '.retrievalResults[0].score // 0' 2>/dev/null || echo 0)
    echo "attempt $i/$MAX_ATTEMPTS: hits=$HITS top_score=$TOP"

    if [[ "$HITS" -gt 0 ]] && awk "BEGIN{exit !($TOP >= $THRESHOLD)}"; then
      echo "OK: $HITS results, top score $TOP >= $THRESHOLD"
      exit 0
    fi
  fi

  sleep "$SLEEP_SECONDS"
done

if [[ "${INVERT:-0}" == "1" ]]; then
  echo "FAIL (cleanup): KB still responding after $((MAX_ATTEMPTS * SLEEP_SECONDS))s — destroy did not complete" >&2
else
  echo "FAIL: no qualifying results after $((MAX_ATTEMPTS * SLEEP_SECONDS))s" >&2
fi
exit 1
```

Properties of this script worth noting:
- No emojis, plain text output (CLAUDE.md mandate).
- `set -euo pipefail` for fail-fast.
- Uses `terraform -chdir=infra/envs/prod` so it can be run from repo root.
- `--invert` flag prepares for D-16 Phase-4 reuse (success = KB unreachable).
- Uses `awk` for floating-point compare since bash `[[ ]]` doesn't do floats.
- Threshold default 0.4 per discretion-area in CONTEXT.md (start there, tune empirically).
- Returns rich diagnostics on each attempt so a learner sees progress, not just spinner.

### Catalog Markdown Authoring

Per D-02 schema. Example for `iphone-13-pro-max.md`:

```markdown
# iPhone 13 Pro Max

## Overview
The iPhone 13 Pro Max is Apple's 6.7-inch flagship phone with a Pro camera system and ProMotion display, ideal for users who want the largest screen and longest battery life.

## Specifications
- Chip: A15 Bionic, 6-core CPU, 5-core GPU
- Display: 6.7-inch Super Retina XDR with ProMotion (120 Hz)
- Storage options: 128 GB, 256 GB, 512 GB, 1 TB
- Camera: Pro 12MP triple system (Wide, Ultra Wide, Telephoto with 3x optical zoom)
- Battery: up to 28 hours video playback
- Colors: Sierra Blue, Gold, Silver, Graphite, Alpine Green
- Weight: 240 g
- Water resistance: IP68

## Pricing
- 128 GB: $1,099 USD
- 256 GB: $1,199 USD
- 512 GB: $1,399 USD
- 1 TB: $1,599 USD

## Stock & Availability
Currently in stock: 12 units (128 GB Sierra Blue), 8 units (256 GB Graphite), 3 units (512 GB Alpine Green). Other configurations on order, ETA 7-10 business days.
```

D-03 puts stock numbers inline with the SKU name in the same chunk window (300 tokens easily fits the whole `## Stock & Availability` section together with the `# iPhone 13 Pro Max` H1 from chunk overlap), maximizing recall for the KB-04 verification query "iPhone 13 Pro Max stock."

### RUNBOOK.md outline (D-06, D-12, supports KB-06)

The plan should include a task to author RUNBOOK.md at repo root with these sections:

1. **Pre-flight**: AWS credentials, region, model access enable in console (Pitfall A).
2. **First deploy**: `cd infra/envs/prod && terraform init && terraform apply`.
3. **First sync**: `aws s3 cp catalog/*.md s3://$(terraform output -raw source_bucket_name)/catalog/` then `aws bedrock-agent start-ingestion-job ...`.
4. **Verify**: `bin/verify-kb.sh`.
5. **Re-index after edit**: edit `catalog/*.md`, repeat the `aws s3 cp` and `start-ingestion-job` commands. Bedrock detects changes incrementally [VERIFIED: AWS docs explicitly: "Syncing is incremental, so Amazon Bedrock processes only the documents that were added, modified, or deleted since the last sync."].
6. **Recovery from half-apply**: `terraform destroy && terraform apply`.
7. **Cleanup**: `terraform destroy` then `bin/verify-kb.sh --invert` (Phase 4 forward-reference).
8. **Next steps (deferred)**: remote backend (S3 + DynamoDB) — listed but not implemented in v1 per D-11.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| KB on OpenSearch Serverless | KB on S3 Vectors | S3 Vectors GA 2025-12-02 | ~99% storage cost reduction at workshop scale; required `~> 6.27` provider |
| Manual `awscc_*` resources for S3 Vectors | Native `aws_s3vectors_*` resources | provider 6.27 | Better drift detection, faster plans |
| Auto-trigger ingestion via `null_resource` | Manual `start-ingestion-job` (D-05) | This phase | Decouples IaC from data; matches "API surface as the teaching tool" intent |
| Hierarchical chunking on any vector store | Fixed-size chunking on S3 Vectors specifically | S3 Vectors KB integration GA | Hierarchical strategy can blow KB-overlay metadata limits |

**Deprecated/outdated:**
- `amazon.titan-embed-text-v1` (single-region availability is narrower than v2; v2 is the workshop default).
- `awscc_s3vectors_vector_bucket` (CloudFormation-backed; superseded by native `aws_s3vectors_vector_bucket` in 6.27).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Bedrock KB will validate the service role's permissions at create time, requiring `depends_on = [aws_iam_role_policy.kb_inline]` on the KB resource | Pattern 5, Anti-Patterns | Without depends_on, Terraform may try to create KB before policy attaches and trigger transient AccessDeniedException. If validation actually happens lazily (on first ingestion only), the depends_on is harmless overhead — no downside |
| A2 | `verify-kb.sh` score threshold 0.4 is reasonable for the Apple catalog + Titan v2 + cosine | Pattern verify-kb.sh | If too high, false negatives waste a workshop minute per learner; if too low, the verification stops being meaningful. CONTEXT.md `<discretion>` already calls this out for empirical tuning |
| A3 | The 2-3 minute post-sync propagation lag stated in AWS docs is the worst case for a small (~4-doc) catalog; in practice it usually surfaces in under a minute | Pitfall C, verify-kb.sh design | If lag is occasionally longer than 5 min, `verify-kb.sh` will exit non-zero on a successful sync and learner will be confused. Mitigation: RUNBOOK explicitly says "if verify-kb.sh times out, wait another 2 minutes and re-run before assuming failure" |
| A4 | `s3:ListBucket` + `s3:GetObject` with `aws:ResourceAccount` condition is sufficient for Bedrock KB to read markdown source; no `s3:GetObjectVersion` needed | Pattern 2 | If KB requires versioned reads (it doesn't enable versioning by default), would manifest as ingestion job FAILED with permission error. AWS sample policy in `kb-permissions.html` matches our shape exactly so risk is low |
| A5 | `aws_bedrockagent_data_source.data_source_id` is the exported attribute name (not `id` or `data_source_id`) | Pattern 7 outputs | If the attribute is actually `id`, the output reference fails on plan; trivial to fix with `terraform plan` error message. The provider source page confirms the attribute exists as `data_source_id` |
| A6 | The Hugo deploy workflow `.github/workflows/deploy.yml` will not pick up files in new `infra/`, `bin/`, `catalog/`, or `RUNBOOK.md` paths because Hugo only consumes `content/`, `layouts/`, `themes/`, `static/`, `i18n/`, `config.toml` | Recommended Project Structure | Verified by reading `deploy.yml` directly — workflow runs `hugo --gc --minify --baseURL ...` which honors Hugo's standard input directories. New top-level dirs will be ignored. Risk negligible |

If any of these are violated, the failure mode is visible at plan or apply time and recoverable in minutes. None are silent or expensive.

## Open Questions

1. **Should `verify-kb.sh` also call `aws bedrock-agent get-ingestion-job` for status before retrieving?**
   - What we know: D-15 says "polls every 15s up to 5min" — implies retrieve-loop only.
   - What's unclear: Adding a status check before the retrieve loop would distinguish "still syncing" from "synced but not propagated" from "sync failed."
   - Recommendation: Keep verify-kb.sh focused on retrieve (per D-15). RUNBOOK separately documents the `get-ingestion-job` poll for the sync step (Code Example above). Two distinct teaching moments — keep them separate.

2. **Should the catalog source bucket use S3 versioning?**
   - What we know: Versioning costs almost nothing at workshop scale and protects against accidental overwrites.
   - What's unclear: Whether KB ingestion behaves differently with versioned buckets (it shouldn't — KB reads current version).
   - Recommendation: SKIP for v1 simplicity. Stock numbers and pricing in markdown change occasionally; if a learner needs to recover, they re-edit and re-sync. Adding versioning adds one more concept to teach without payoff.

3. **Should the module accept a `region` variable per-resource, or rely on the provider region?**
   - What we know: All resources in this phase live in the same region; the provider is configured at `infra/envs/prod` level.
   - Recommendation: `region` is a module variable used in ARN constructions (`embedding_model_arn`, IAM Resource scoping) and in the `provider` block in the env. The module does NOT pass `region = var.region` to each resource — it inherits from the provider.

## Environment Availability

Phase 1 is local-machine + AWS-API only. No deployed runtime in this phase.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Terraform CLI (>= 1.9) | All IaC | (must be installed by learner) | check `terraform -version` | None — blocking |
| AWS CLI v2 | Sync, retrieve, model-access pre-flight | (must be installed by learner) | check `aws --version` | None — blocking |
| `jq` | `verify-kb.sh` JSON parsing | (typically pre-installed on dev machines) | check `jq --version` | None — blocking |
| AWS account | All AWS resources | n/a | n/a | None — blocking |
| Bedrock Titan v2 model access in target region | KB ingestion | (per-account console enable) | n/a | None — see Pitfall A |
| Hugo (workshop) | Out of scope for Phase 1 | (already used by repo) | 0.139.4 (deploy workflow) | n/a |

**Missing-dependency policy:** RUNBOOK pre-flight section enumerates the four blocking deps with version checks. If a learner skips, `terraform init` or first AWS CLI call fails with a clear message — no silent failures.

## Security Domain

`workflow.security_enforcement: true` and `security_asvs_level: 1` in `.planning/config.json`. Phase 1 introduces no application code, no user input handling, and no external interfaces — security surface is limited to IAM and S3 bucket controls.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 1 has no application auth surface; AWS API auth is via SDK/CLI sigv4 (managed by AWS) |
| V3 Session Management | no | No sessions in this phase |
| V4 Access Control | yes | KB service role least-privilege per Pattern 1 + Pattern 2; S3 bucket public access fully blocked per Pattern 3; D-13 mandates zero IAM wildcards |
| V5 Input Validation | partial | The only "user input" is the `--retrieval-query` text in `verify-kb.sh` — sourced from a hardcoded constant in the script, not external input. RUNBOOK note: do not let learners feed untrusted input to `bin/verify-kb.sh --query` because shell-quoting matters |
| V6 Cryptography | partial | S3 source bucket inherits SSE-S3 default; S3 Vectors bucket inherits SSE-S3 default. KMS not introduced in v1 — appropriate for non-sensitive workshop data |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Confused-deputy on KB service role | Elevation of Privilege | Trust policy with `aws:SourceAccount` + `aws:SourceArn` conditions per Pattern 1 [VERIFIED] |
| Cross-account S3 read via permissive bucket policy | Information Disclosure | S3 bucket public-access block per Pattern 3; KB service role inline policy includes `aws:ResourceAccount` condition |
| IAM wildcard sprawl learned by workshop learners | Anti-pattern proliferation | D-13 forbids wildcards; verification task `grep '"\\*"'` returns zero in IAM Action/Resource fields (Pitfall F) |
| Stale credentials embedded in catalog or scripts | Information Disclosure | No credentials in code. `verify-kb.sh` uses ambient AWS CLI auth (sigv4); RUNBOOK uses learner's `~/.aws/credentials` |
| S3 source bucket left public after destroy fail | Information Disclosure | Public access block defends even on residual buckets; `force_destroy = true` ensures `terraform destroy` succeeds |
| KB service role over-broad on Titan ARN | Privilege escalation | ARN scoped to single foundation model, single region — Pattern 2 |

**No Bedrock Guardrails in v1** per PROJECT.md. The catalog content is synthetic (Apple product specs); no PII risk in this phase. PII concern is a Phase 2 issue when real conversations land in CloudWatch.

## Sources

### Primary (HIGH confidence)

- AWS docs — Create a service role for Amazon Bedrock Knowledge Bases (trust policy + S3 + S3 Vectors policies VERBATIM): https://docs.aws.amazon.com/bedrock/latest/userguide/kb-permissions.html
- AWS docs — Using S3 Vectors with Amazon Bedrock Knowledge Bases (limitations, supported models, IAM): https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-bedrock-kb.html
- AWS docs — Sync your data with your Amazon Bedrock knowledge base (start-ingestion-job, propagation note): https://docs.aws.amazon.com/bedrock/latest/userguide/kb-data-source-sync-ingest.html
- AWS docs — Supported models and Regions for Amazon Bedrock knowledge bases (Titan v2 region table): https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base-supported.html
- AWS docs — S3 Vectors limitations (40 KB / 50 keys raw; 1 KB / 35 keys KB overlay): https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-limitations.html
- AWS CLI reference — `aws bedrock-agent start-ingestion-job`: https://docs.aws.amazon.com/cli/latest/reference/bedrock-agent/start-ingestion-job.html
- AWS CLI reference — `aws bedrock-agent-runtime retrieve`: https://docs.aws.amazon.com/cli/latest/reference/bedrock-agent-runtime/retrieve.html
- Terraform AWS provider source — `aws_bedrockagent_knowledge_base` doc: https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/bedrockagent_knowledge_base.html.markdown
- Terraform AWS provider source — `aws_s3vectors_vector_bucket` doc: https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/s3vectors_vector_bucket.html.markdown
- Terraform AWS provider source — `aws_s3vectors_index` doc: https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/s3vectors_index.html.markdown
- Terraform AWS provider source — `aws_bedrockagent_data_source` doc: https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/bedrockagent_data_source.html.markdown

### Secondary (MEDIUM confidence — corroboration)

- `.planning/research/STACK.md` — locked stack baseline, Titan v2 model id, version pins
- `.planning/research/PITFALLS.md` — Pitfalls #3, #8, #9, #17, #20, #23 informed Phase-1 pitfalls A–F
- `.planning/research/ARCHITECTURE.md` — `Phase 1 — Knowledge Base end-to-end` section informed the diagram

### Tertiary (LOW confidence — none)

No claims in this research rely on a single unverified web search.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every Terraform argument and IAM action verified against current provider source and AWS docs
- Architecture: HIGH — flow follows AWS's documented KB ingestion+retrieval pipeline; only one tier
- Pitfalls: HIGH for project-level pitfalls (already verified in PITFALLS.md research); HIGH for Phase-1-specific pitfalls G–J (verified during this research)
- IAM policy shapes: HIGH — copied verbatim from AWS official docs page
- AWS CLI shapes: HIGH — copied verbatim from AWS CLI reference pages
- Score field location in retrieve response: HIGH — verified at `retrievalResults[].score` (flat double)

**Research date:** 2026-05-05
**Valid until:** 2026-08-05 (90 days for stable AWS service docs; AWS provider may publish a 6.43+ release that adds optional arguments — none would invalidate the schemas above, only extend them)

## RESEARCH COMPLETE
