---
phase: 01-knowledge-base-foundation
plan: 02
type: execute
wave: 1
depends_on:
  - "01-01"
files_modified:
  - infra/envs/prod/versions.tf
  - infra/envs/prod/main.tf
  - infra/envs/prod/variables.tf
  - infra/envs/prod/outputs.tf
  - infra/envs/prod/terraform.tfvars
  - infra/modules/knowledge_base/versions.tf
  - infra/modules/knowledge_base/variables.tf
  - infra/modules/knowledge_base/main.tf
  - infra/modules/knowledge_base/iam.tf
  - infra/modules/knowledge_base/outputs.tf
autonomous: true
requirements:
  - KB-02
  - KB-03
  - KB-05

must_haves:
  truths:
    - "Terraform code uses hashicorp/aws ~> 6.27 (the floor for native S3 Vectors KB support) and Terraform >= 1.9."
    - "All resource arguments are copy-verbatim from 01-RESEARCH.md Patterns 1-7 — no guessed argument names, no guessed casing, no wildcards."
    - "KB service IAM role trust policy uses bedrock.amazonaws.com (NOT bedrockagent.amazonaws.com) and includes both aws:SourceAccount AND aws:SourceArn conditions (confused-deputy mitigation per RESEARCH.md Pattern 1)."
    - "The KB inline IAM policy has ZERO wildcards in Action or Resource — every action enumerated, every ARN scoped (D-13)."
    - "Resource names are fixed: hera-kb-prod, hera-kb-source-prod, hera-kb-vectors-prod (D-12 — no random_id suffix)."
    - "Source S3 bucket has aws_s3_bucket_public_access_block with all four settings = true (security threat T-02-01)."
    - "Both buckets (source S3 and S3 Vectors) have force_destroy = true so terraform destroy succeeds on a non-empty bucket (Pitfall E)."
    - "aws_bedrockagent_knowledge_base has depends_on = [aws_iam_role_policy.kb_inline] — required because KB validates role permissions at create time (RESEARCH.md Pattern 5)."
    - "Region defaults to ap-northeast-1 in the root variables.tf, supports override to us-east-1 (D-14, DEP-06)."
    - "The Phase 2 consumer role (bedrock:Retrieve for Pipecat) is NOT created (D-10 — deferred). Only kb_arn is exported so Phase 2 can scope its own role."
    - "cd infra/envs/prod && terraform init && terraform validate exits 0 with no AWS credentials — code is structurally valid before any AWS call."
    - "No emojis anywhere in *.tf files (CLAUDE.md mandate)."
  artifacts:
    - path: "infra/envs/prod/versions.tf"
      provides: "Terraform >= 1.9 and hashicorp/aws ~> 6.27 pin at the root level"
      contains: "hashicorp/aws"
    - path: "infra/envs/prod/main.tf"
      provides: "AWS provider config + knowledge_base module instantiation"
      contains: "module \"knowledge_base\""
    - path: "infra/envs/prod/variables.tf"
      provides: "region (default ap-northeast-1), env (default prod), name_prefix (default hera)"
      contains: "default     = \"ap-northeast-1\""
    - path: "infra/envs/prod/outputs.tf"
      provides: "Re-exports kb_id, kb_arn, source_bucket_name, data_source_id from the module"
      contains: "value       = module.knowledge_base.kb_arn"
    - path: "infra/modules/knowledge_base/main.tf"
      provides: "S3 source bucket + public-access-block, S3 Vectors bucket + index, Bedrock KB, KB data source"
      contains: "resource \"aws_bedrockagent_knowledge_base\""
    - path: "infra/modules/knowledge_base/iam.tf"
      provides: "KB service role + trust policy + inline permissions policy (zero wildcards)"
      contains: "aws:SourceAccount"
    - path: "infra/modules/knowledge_base/variables.tf"
      provides: "name_prefix, env, region, embedding_dimension (1024), chunk_max_tokens (300), chunk_overlap_pct (20)"
      contains: "default     = 1024"
    - path: "infra/modules/knowledge_base/outputs.tf"
      provides: "kb_id, kb_arn, source_bucket_name, data_source_id (D-08)"
      contains: "output \"kb_arn\""
  key_links:
    - from: "infra/envs/prod/main.tf"
      to: "infra/modules/knowledge_base/"
      via: "module \"knowledge_base\" { source = \"../../modules/knowledge_base\" }"
      pattern: "source\\s*=\\s*\"\\.\\./\\.\\./modules/knowledge_base\""
    - from: "aws_bedrockagent_knowledge_base.this"
      to: "aws_iam_role_policy.kb_inline"
      via: "depends_on attribute (race-condition mitigation per RESEARCH.md Pattern 5)"
      pattern: "depends_on\\s*=\\s*\\[aws_iam_role_policy\\.kb_inline\\]"
    - from: "aws_bedrockagent_knowledge_base.this.storage_configuration.s3_vectors_configuration"
      to: "aws_s3vectors_index.this.index_arn"
      via: "index_arn attribute reference"
      pattern: "index_arn\\s*=\\s*aws_s3vectors_index\\.this\\.index_arn"
    - from: "aws_bedrockagent_data_source.catalog"
      to: "aws_s3_bucket.source"
      via: "bucket_arn + inclusion_prefixes = [\"catalog/\"]"
      pattern: "inclusion_prefixes\\s*=\\s*\\[\"catalog/\"\\]"
---

<objective>
Build the Terraform infrastructure-as-code for Phase 1 — a single `modules/knowledge_base/` module instantiated by a thin root at `envs/prod/`. The module creates: S3 source markdown bucket (with public-access-block), S3 Vectors bucket + index (1024-dim float32 cosine for Titan v2), Bedrock Knowledge Base (with `s3_vectors_storage_configuration`), Bedrock data source (FIXED_SIZE 300/20% chunking on the `catalog/` prefix), and a least-privilege KB service IAM role.

This plan is **code-only**. It does NOT run `terraform apply`, does NOT call AWS, does NOT cost money. It ends at `terraform init && terraform validate` succeeding locally with no AWS credentials needed. Plan 03 owns the live `apply`, ingestion job, and verification.

Purpose: Phase 1 success criterion #3 is "the Terraform `modules/knowledge_base` deploys cleanly into a fresh AWS account in `ap-northeast-1` with `terraform init && apply` and no manual console clicks." That criterion is verified for-real in Plan 03; this plan delivers the code that makes it possible. Per D-10 the consumer-side `bedrock:Retrieve` role for Pipecat is deferred to Phase 2 — Phase 1 only outputs `kb_arn` so Phase 2 can scope its own role policy without guessing.

Output: Five module files (`versions.tf`, `variables.tf`, `main.tf`, `iam.tf`, `outputs.tf`) under `infra/modules/knowledge_base/`, four root files (`versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`) plus a `terraform.tfvars` under `infra/envs/prod/`.
</objective>

<execution_context>
@C:/Users/trant/projects/hera/.claude/get-shit-done/workflows/execute-plan.md
@C:/Users/trant/projects/hera/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@C:/Users/trant/projects/hera/.planning/PROJECT.md
@C:/Users/trant/projects/hera/.planning/REQUIREMENTS.md
@C:/Users/trant/projects/hera/.planning/ROADMAP.md
@C:/Users/trant/projects/hera/.planning/STATE.md
@C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md
@C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md
@C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-PATTERNS.md
@C:/Users/trant/projects/hera/CLAUDE.md
@C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-01-repo-skeleton-and-catalog-PLAN.md

<interfaces>
<!-- Plan 01 created the catalog/ directory but no code interfaces. Plan 02 creates the first Terraform contracts. -->
<!-- Module outputs that Plan 03 will consume: -->
<!--   module.knowledge_base.kb_id              -> string (KB ID)               consumed by bin/verify-kb.sh and start-ingestion-job -->
<!--   module.knowledge_base.kb_arn             -> string (KB ARN)              consumed by Phase 2 consumer role (D-10) -->
<!--   module.knowledge_base.source_bucket_name -> string (S3 bucket name)      consumed by aws s3 cp catalog/*.md ... -->
<!--   module.knowledge_base.data_source_id     -> string (data source UUID)    consumed by aws bedrock-agent start-ingestion-job -->
<!-- The root envs/prod/outputs.tf re-exports all four with identical names. -->
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Author the knowledge_base module — versions.tf, variables.tf, outputs.tf, iam.tf</name>
  <files>infra/modules/knowledge_base/versions.tf, infra/modules/knowledge_base/variables.tf, infra/modules/knowledge_base/outputs.tf, infra/modules/knowledge_base/iam.tf</files>
  <read_first>
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Standard Stack" (provider pin, Terraform version)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pattern 1: KB Service Role Trust Policy" (lines 262-302) — VERBATIM HCL for the trust policy with bedrock.amazonaws.com + aws:SourceAccount + aws:SourceArn
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pattern 2: KB Service Role Permissions" (lines 304-372) — VERBATIM HCL for the inline policy with three statements: S3 source list/get, Bedrock InvokeModel on Titan v2 ARN, S3 Vectors read/write
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pattern 7: Module outputs" (lines 513-536) — VERBATIM HCL for the four outputs
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md D-08 (single-module shape, output list), D-10 (consumer role DEFERRED), D-12 (fixed names), D-13 (zero wildcards), D-14 (region default ap-northeast-1)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pitfall I" — trust principal is bedrock.amazonaws.com NOT bedrockagent.amazonaws.com
  </read_first>
  <action>
Create four files under `infra/modules/knowledge_base/`. All HCL is copied verbatim from 01-RESEARCH.md Patterns 1, 2, and 7. No emojis. Concise comments only where the "why" is non-obvious.

**File 1: `infra/modules/knowledge_base/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
  }
}
```

The `~> 6.27` pin is the floor for native `s3_vectors_storage_configuration` block on `aws_bedrockagent_knowledge_base` (RESEARCH.md §Standard Stack). It allows 6.27.x through 6.x but blocks a 7.0 major upgrade.

**File 2: `infra/modules/knowledge_base/variables.tf`**

```hcl
variable "name_prefix" {
  description = "Prefix for all named resources (e.g. \"hera\" -> hera-kb-prod, hera-kb-source-prod, hera-kb-vectors-prod). Fixed names per D-12; no random suffix."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment name suffix (e.g. \"prod\" -> hera-kb-prod). Phase 1 only ships prod; dev environment is added in Phase 2 if needed."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region for ARN constructions (embedding_model_arn, S3 Vectors index ARN, IAM scope). Inherits from provider config; passed in for ARN string interpolation only. Default ap-northeast-1 per CLAUDE.md and DEP-06."
  type        = string
  default     = "ap-northeast-1"
}

variable "embedding_dimension" {
  description = "Vector dimension. MUST match the embedding model. 1024 is Titan v2 default. WARNING: S3 Vectors index dimension is IMMUTABLE post-create; changing this requires destroy+recreate of aws_s3vectors_index AND aws_bedrockagent_knowledge_base (Pitfall B / project Pitfall #8)."
  type        = number
  default     = 1024
}

variable "chunk_max_tokens" {
  description = "FIXED_SIZE chunking max tokens per chunk (D-04)."
  type        = number
  default     = 300
}

variable "chunk_overlap_pct" {
  description = "FIXED_SIZE chunking overlap percentage between adjacent chunks (D-04)."
  type        = number
  default     = 20
}
```

**File 3: `infra/modules/knowledge_base/outputs.tf`** — VERBATIM from RESEARCH.md Pattern 7:

```hcl
output "kb_id" {
  description = "Bedrock Knowledge Base ID. Consumed by aws bedrock-agent start-ingestion-job (Plan 03) and by the Phase 2 Pipecat tool."
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "kb_arn" {
  description = "Bedrock Knowledge Base ARN. Used by Phase 2 to scope bedrock:Retrieve in the consumer role (D-10 deferred)."
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "source_bucket_name" {
  description = "S3 source bucket name. Use with: aws s3 cp catalog/*.md s3://<this>/catalog/"
  value       = aws_s3_bucket.source.bucket
}

output "data_source_id" {
  description = "Bedrock data source ID. Required for aws bedrock-agent start-ingestion-job."
  value       = aws_bedrockagent_data_source.catalog.data_source_id
}
```

**File 4: `infra/modules/knowledge_base/iam.tf`** — VERBATIM from RESEARCH.md Pattern 1 + Pattern 2. Combined into one file:

```hcl
data "aws_caller_identity" "current" {}

# --- KB service role trust policy ---
# Service principal is bedrock.amazonaws.com (Pitfall I — NOT bedrockagent.amazonaws.com).
# aws:SourceAccount + aws:SourceArn conditions defend against the cross-account "confused deputy" pattern.
data "aws_iam_policy_document" "kb_trust" {
  statement {
    sid     = "BedrockKBAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
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

# --- KB service role inline permissions policy ---
# Three statements; zero wildcards in Action or Resource (D-13). Every action enumerated.
data "aws_iam_policy_document" "kb_inline" {

  # 1. Read source markdown bucket
  statement {
    sid       = "S3SourceListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.source.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "S3SourceGetObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.source.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # 2. Invoke Titan v2 embedding model in this region (foundation-model ARN format omits account segment)
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
      "s3vectors:GetIndex",
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

**Critical do-not-paraphrase items (RESEARCH.md cited verbatim):**
- Service principal is `bedrock.amazonaws.com`. NOT `bedrockagent.amazonaws.com`.
- Foundation-model ARN has a double colon before `foundation-model` (no account segment): `arn:aws:bedrock:<region>::foundation-model/<model-id>`.
- Action lists are explicit, no `s3vectors:*` or `bedrock:*` wildcards.
- The S3 Vectors resource ARN scopes to the specific bucket/index by name, not by ARN reference (matching RESEARCH.md Pattern 2).
- The `aws:ResourceAccount` condition on S3 statements blocks cross-account reads even if the source bucket policy were ever loosened.

The `aws_iam_role_policy.kb_inline` resource references `aws_s3_bucket.source` and `aws_s3vectors_vector_bucket.this` and `aws_s3vectors_index.this` — those resources are defined in `main.tf` (Task 2). Terraform resolves cross-file references within the same module, so this is fine.
  </action>
  <acceptance_criteria>
    - All four files exist: `test -f infra/modules/knowledge_base/versions.tf && test -f infra/modules/knowledge_base/variables.tf && test -f infra/modules/knowledge_base/outputs.tf && test -f infra/modules/knowledge_base/iam.tf`.
    - `versions.tf` pins provider to `~> 6.27`: `grep -q '~> 6\.27' infra/modules/knowledge_base/versions.tf`.
    - `versions.tf` requires Terraform >= 1.9: `grep -q 'required_version = ">= 1\.9"' infra/modules/knowledge_base/versions.tf`.
    - `variables.tf` declares the six variables with correct defaults: `grep -q 'default     = "hera"' infra/modules/knowledge_base/variables.tf` AND `grep -q 'default     = "prod"' infra/modules/knowledge_base/variables.tf` AND `grep -q 'default     = "ap-northeast-1"' infra/modules/knowledge_base/variables.tf` AND `grep -q 'default     = 1024' infra/modules/knowledge_base/variables.tf` AND `grep -q 'default     = 300' infra/modules/knowledge_base/variables.tf` AND `grep -q 'default     = 20' infra/modules/knowledge_base/variables.tf`.
    - `outputs.tf` exports the four required outputs (D-08): `grep -qE '^output "kb_id"' infra/modules/knowledge_base/outputs.tf` AND `grep -qE '^output "kb_arn"' infra/modules/knowledge_base/outputs.tf` AND `grep -qE '^output "source_bucket_name"' infra/modules/knowledge_base/outputs.tf` AND `grep -qE '^output "data_source_id"' infra/modules/knowledge_base/outputs.tf`.
    - `iam.tf` trust policy uses `bedrock.amazonaws.com`: `grep -q 'bedrock\.amazonaws\.com' infra/modules/knowledge_base/iam.tf`.
    - `iam.tf` does NOT use `bedrockagent.amazonaws.com` (Pitfall I): `! grep -q 'bedrockagent\.amazonaws\.com' infra/modules/knowledge_base/iam.tf`.
    - `iam.tf` includes both confused-deputy conditions: `grep -q 'aws:SourceAccount' infra/modules/knowledge_base/iam.tf` AND `grep -q 'AWS:SourceArn' infra/modules/knowledge_base/iam.tf`.
    - `iam.tf` enumerates exactly the right S3 Vectors actions (no wildcard): `grep -q 's3vectors:PutVectors' infra/modules/knowledge_base/iam.tf` AND `grep -q 's3vectors:GetVectors' infra/modules/knowledge_base/iam.tf` AND `grep -q 's3vectors:DeleteVectors' infra/modules/knowledge_base/iam.tf` AND `grep -q 's3vectors:QueryVectors' infra/modules/knowledge_base/iam.tf` AND `grep -q 's3vectors:GetIndex' infra/modules/knowledge_base/iam.tf`.
    - `iam.tf` references the Titan v2 ARN with the double-colon format: `grep -q 'arn:aws:bedrock:\${var\.region}::foundation-model/amazon\.titan-embed-text-v2:0' infra/modules/knowledge_base/iam.tf`.
    - Zero wildcards in any IAM Action or Resource (D-13, security threat T-02-02): `! grep -E '"\\*"' infra/modules/knowledge_base/iam.tf | grep -E '(actions|resources|Action|Resource)'`. Stricter check: `python3 -c "import re, sys, pathlib; t=pathlib.Path('infra/modules/knowledge_base/iam.tf').read_text(encoding='utf-8'); bad=[m.group(0) for m in re.finditer(r'(actions|resources)\s*=\s*\[[^\]]*\"\\*\"', t)]; print('BAD:', bad) if bad else print('OK'); sys.exit(1 if bad else 0)"` exits 0.
    - No emojis: `python3 -c "import sys, re, pathlib; bad=[p for p in pathlib.Path('infra/modules/knowledge_base').glob('*.tf') if re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', p.read_text(encoding='utf-8'))]; sys.exit(0 if not bad else (print(bad) or 1))"` exits 0.
  </acceptance_criteria>
  <verify>
    <automated>test -f infra/modules/knowledge_base/versions.tf && test -f infra/modules/knowledge_base/variables.tf && test -f infra/modules/knowledge_base/outputs.tf && test -f infra/modules/knowledge_base/iam.tf && grep -q '~> 6\.27' infra/modules/knowledge_base/versions.tf && grep -q 'bedrock\.amazonaws\.com' infra/modules/knowledge_base/iam.tf && ! grep -q 'bedrockagent\.amazonaws\.com' infra/modules/knowledge_base/iam.tf && grep -q 'aws:SourceAccount' infra/modules/knowledge_base/iam.tf && grep -q 'AWS:SourceArn' infra/modules/knowledge_base/iam.tf && grep -q 'arn:aws:bedrock:\${var\.region}::foundation-model/amazon\.titan-embed-text-v2:0' infra/modules/knowledge_base/iam.tf</automated>
  </verify>
  <done>
    versions.tf pins provider/Terraform; variables.tf declares the 6 variables with documented defaults; outputs.tf exports the 4 required outputs (D-08); iam.tf creates the trust + inline policies with zero wildcards (D-13), confused-deputy conditions (T-02-02), correct service principal (Pitfall I), and verbatim Titan v2 ARN (Pitfall H format).
  </done>
</task>

<task type="auto">
  <name>Task 2: Author the knowledge_base module main.tf — S3 source, S3 Vectors, KB, data source</name>
  <files>infra/modules/knowledge_base/main.tf</files>
  <read_first>
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pattern 3: S3 Source Bucket with force_destroy" (lines 379-399) — VERBATIM aws_s3_bucket + aws_s3_bucket_public_access_block
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pattern 4: S3 Vectors Bucket + Index" (lines 401-431) — VERBATIM aws_s3vectors_vector_bucket + aws_s3vectors_index, with critical argument-name details (vector_bucket_name not name; lowercase float32 / cosine)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pattern 5: Bedrock Knowledge Base with S3 Vectors backend" (lines 432-475) — VERBATIM aws_bedrockagent_knowledge_base, including the depends_on and the FLOAT32 uppercase quirk
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pattern 6: Bedrock KB Data Source" (lines 476-511) — VERBATIM aws_bedrockagent_data_source with FIXED_SIZE chunking on the catalog/ prefix
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Anti-Patterns to Avoid" (lines 538-548) — including "Forgetting depends_on = [aws_iam_role_policy.kb_inline]"
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md D-08 (resource list), D-12 (fixed names), D-04 (FIXED_SIZE 300/20%)
    - infra/modules/knowledge_base/iam.tf (Task 1 output — main.tf references aws_iam_role.kb_service_role.arn and aws_iam_role_policy.kb_inline)
  </read_first>
  <action>
Create `infra/modules/knowledge_base/main.tf`. All HCL is copied verbatim from 01-RESEARCH.md Patterns 3, 4, 5, 6. Inline comments only where the "why" or a known foot-gun is non-obvious. No emojis.

```hcl
# --- S3 source bucket (markdown catalog) ---
# force_destroy = true so terraform destroy succeeds even with objects in the bucket (Pitfall E / Pitfall #20).
# Recovery from accidental destroy is git checkout + re-upload of catalog/*.md (RUNBOOK.md).

resource "aws_s3_bucket" "source" {
  bucket        = "${var.name_prefix}-kb-source-${var.env}"
  force_destroy = true
}

# Block ALL public access on the source bucket. Defense in depth — even if a future bucket
# policy were loosened, this blocks public reads/writes/ACLs at the account level.
resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- S3 Vectors bucket + index ---
# Pitfall G: argument is vector_bucket_name, NOT name.
# Pitfall H: data_type and distance_metric are LOWERCASE here (uppercase in the KB resource is a separate provider quirk).
# Pitfall B: dimension is IMMUTABLE post-create; changing it requires destroy + recreate.

resource "aws_s3vectors_vector_bucket" "this" {
  vector_bucket_name = "${var.name_prefix}-kb-vectors-${var.env}"
  force_destroy      = true
  # encryption_configuration omitted -> SSE-S3 (AES256) default
}

resource "aws_s3vectors_index" "this" {
  index_name         = "${var.name_prefix}-kb-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.this.vector_bucket_name

  data_type       = "float32"
  dimension       = var.embedding_dimension
  distance_metric = "cosine"
}

# --- Bedrock Knowledge Base ---
# embedding_data_type is UPPERCASE here (FLOAT32) — provider inconsistency vs aws_s3vectors_index lowercase. Both are correct in their own context (Pitfall H).
# depends_on on the inline policy is required: KB validates role permissions at create time. Without this, Terraform may try to create the KB before the inline policy attaches and trigger a transient AccessDeniedException (RESEARCH.md Pattern 5 / Anti-Patterns).

resource "aws_bedrockagent_knowledge_base" "this" {
  name     = "${var.name_prefix}-kb-${var.env}"
  role_arn = aws_iam_role.kb_service_role.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0"

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = var.embedding_dimension
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.this.index_arn
    }
  }

  depends_on = [aws_iam_role_policy.kb_inline]
}

# --- Bedrock KB Data Source ---
# Wires the S3 source bucket to the KB. inclusion_prefixes scopes ingestion to the catalog/ prefix
# so other directory uses of the same bucket stay out of the KB.
# FIXED_SIZE chunking with 300 tokens / 20% overlap per D-04. Hierarchical chunking is rejected because parent-child links can blow the per-vector metadata overlay (Pitfall #8 / Anti-Patterns).

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
        max_tokens         = var.chunk_max_tokens
        overlap_percentage = var.chunk_overlap_pct
      }
    }
  }
}
```

**Critical do-not-paraphrase items:**
- `aws_s3vectors_vector_bucket` argument is `vector_bucket_name`, not `name` (Pitfall G).
- `aws_s3vectors_index.vector_bucket_name` references the parent **by name**, not ARN (Pitfall G).
- `aws_s3vectors_index.data_type = "float32"` (lowercase). `aws_s3vectors_index.distance_metric = "cosine"` (lowercase).
- `aws_bedrockagent_knowledge_base.embedding_model_configuration.bedrock_embedding_model_configuration.embedding_data_type = "FLOAT32"` (UPPERCASE — different from the index resource above; this is a real provider inconsistency, both are correct).
- `aws_bedrockagent_knowledge_base.knowledge_base_configuration.type = "VECTOR"` and `aws_bedrockagent_knowledge_base.storage_configuration.type = "S3_VECTORS"` (both UPPERCASE).
- `aws_bedrockagent_knowledge_base.depends_on = [aws_iam_role_policy.kb_inline]` is mandatory.
- `aws_bedrockagent_data_source.vector_ingestion_configuration.chunking_configuration.chunking_strategy = "FIXED_SIZE"` (UPPERCASE).
- `aws_bedrockagent_data_source.data_source_configuration.s3_configuration.inclusion_prefixes = ["catalog/"]` is plural (a list), value matches the Plan 01 catalog directory + the manual upload path documented in Plan 03 RUNBOOK.
- `aws_s3_bucket_public_access_block` has all four `*_public_*` settings = true (security threat T-02-01).
- `force_destroy = true` on BOTH `aws_s3_bucket.source` and `aws_s3vectors_vector_bucket.this` (Pitfall E).

DO NOT add `aws_s3_object` resources to upload `catalog/*.md` via Terraform. Per D-05 / D-07 the manual `aws s3 cp` documented in RUNBOOK is the teaching surface — Terraform-managed uploads couple content edits with `terraform apply` and pollute state.

DO NOT add `null_resource` / `local-exec` to auto-trigger the ingestion job. Per D-07 the manual `start-ingestion-job` documented in Plan 03 RUNBOOK is the teaching surface.
  </action>
  <acceptance_criteria>
    - File exists: `test -f infra/modules/knowledge_base/main.tf`.
    - All five required resources are present: `grep -qE '^resource "aws_s3_bucket" "source"' infra/modules/knowledge_base/main.tf` AND `grep -qE '^resource "aws_s3_bucket_public_access_block" "source"' infra/modules/knowledge_base/main.tf` AND `grep -qE '^resource "aws_s3vectors_vector_bucket" "this"' infra/modules/knowledge_base/main.tf` AND `grep -qE '^resource "aws_s3vectors_index" "this"' infra/modules/knowledge_base/main.tf` AND `grep -qE '^resource "aws_bedrockagent_knowledge_base" "this"' infra/modules/knowledge_base/main.tf` AND `grep -qE '^resource "aws_bedrockagent_data_source" "catalog"' infra/modules/knowledge_base/main.tf`.
    - Source bucket has `force_destroy = true`: `grep -A 3 'resource "aws_s3_bucket" "source"' infra/modules/knowledge_base/main.tf | grep -q 'force_destroy = true'`.
    - All four public-access-block settings are `true` (T-02-01): `grep -q 'block_public_acls       = true' infra/modules/knowledge_base/main.tf` AND `grep -q 'block_public_policy     = true' infra/modules/knowledge_base/main.tf` AND `grep -q 'ignore_public_acls      = true' infra/modules/knowledge_base/main.tf` AND `grep -q 'restrict_public_buckets = true' infra/modules/knowledge_base/main.tf`.
    - S3 Vectors bucket uses `vector_bucket_name` not `name` (Pitfall G): `grep -q 'vector_bucket_name = "${var\.name_prefix}-kb-vectors' infra/modules/knowledge_base/main.tf` AND `! grep -E '^\s*name\s*=\s*"\${var\.name_prefix}-kb-vectors' infra/modules/knowledge_base/main.tf` (the bucket resource MUST NOT use `name = ...`).
    - S3 Vectors index uses lowercase `float32` and `cosine` (Pitfall H): `grep -q 'data_type       = "float32"' infra/modules/knowledge_base/main.tf` AND `grep -q 'distance_metric = "cosine"' infra/modules/knowledge_base/main.tf`.
    - KB embedding configuration uses UPPERCASE `FLOAT32` (Pitfall H — different from above): `grep -q 'embedding_data_type = "FLOAT32"' infra/modules/knowledge_base/main.tf`.
    - KB has the storage_configuration with S3_VECTORS: `grep -q 'type = "S3_VECTORS"' infra/modules/knowledge_base/main.tf` AND `grep -q 's3_vectors_configuration {' infra/modules/knowledge_base/main.tf` AND `grep -q 'index_arn = aws_s3vectors_index\.this\.index_arn' infra/modules/knowledge_base/main.tf`.
    - KB has the mandatory depends_on (RESEARCH.md Anti-Patterns): `grep -qE 'depends_on\s*=\s*\[aws_iam_role_policy\.kb_inline\]' infra/modules/knowledge_base/main.tf`.
    - Data source uses FIXED_SIZE chunking with 300/20%: `grep -q 'chunking_strategy = "FIXED_SIZE"' infra/modules/knowledge_base/main.tf` AND `grep -q 'max_tokens         = var\.chunk_max_tokens' infra/modules/knowledge_base/main.tf` AND `grep -q 'overlap_percentage = var\.chunk_overlap_pct' infra/modules/knowledge_base/main.tf`.
    - Data source scopes to catalog/ prefix: `grep -q 'inclusion_prefixes = \["catalog/"\]' infra/modules/knowledge_base/main.tf`.
    - No `aws_s3_object` resource (rejected anti-pattern): `! grep -qE '^resource "aws_s3_object"' infra/modules/knowledge_base/main.tf`.
    - No `null_resource` (rejected anti-pattern, D-07): `! grep -qE '^resource "null_resource"' infra/modules/knowledge_base/main.tf`.
    - No `random_id` resource (rejected anti-pattern, D-12): `! grep -qE '^resource "random_id"' infra/modules/knowledge_base/main.tf`.
    - No emojis: `python3 -c "import sys, re, pathlib; sys.exit(1 if re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', pathlib.Path('infra/modules/knowledge_base/main.tf').read_text(encoding='utf-8')) else 0)"` exits 0.
  </acceptance_criteria>
  <verify>
    <automated>test -f infra/modules/knowledge_base/main.tf && grep -q 'resource "aws_s3_bucket" "source"' infra/modules/knowledge_base/main.tf && grep -q 'resource "aws_s3_bucket_public_access_block" "source"' infra/modules/knowledge_base/main.tf && grep -q 'resource "aws_s3vectors_vector_bucket" "this"' infra/modules/knowledge_base/main.tf && grep -q 'resource "aws_s3vectors_index" "this"' infra/modules/knowledge_base/main.tf && grep -q 'resource "aws_bedrockagent_knowledge_base" "this"' infra/modules/knowledge_base/main.tf && grep -q 'resource "aws_bedrockagent_data_source" "catalog"' infra/modules/knowledge_base/main.tf && grep -q 'force_destroy = true' infra/modules/knowledge_base/main.tf && grep -q 'block_public_acls       = true' infra/modules/knowledge_base/main.tf && grep -q 'data_type       = "float32"' infra/modules/knowledge_base/main.tf && grep -q 'embedding_data_type = "FLOAT32"' infra/modules/knowledge_base/main.tf && grep -q 'depends_on = \[aws_iam_role_policy\.kb_inline\]' infra/modules/knowledge_base/main.tf && grep -q 'inclusion_prefixes = \["catalog/"\]' infra/modules/knowledge_base/main.tf</automated>
  </verify>
  <done>
    main.tf creates all five resource types with verbatim argument shapes from RESEARCH.md Patterns 3-6. Pitfalls G (vector_bucket_name), H (case mismatches), E (force_destroy), and Pattern 5 race condition (depends_on) are all addressed. Anti-patterns (aws_s3_object, null_resource, random_id) are absent.
  </done>
</task>

<task type="auto">
  <name>Task 3: Author the root envs/prod/ files and run terraform init && validate</name>
  <files>infra/envs/prod/versions.tf, infra/envs/prod/main.tf, infra/envs/prod/variables.tf, infra/envs/prod/outputs.tf, infra/envs/prod/terraform.tfvars</files>
  <read_first>
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Recommended Project Structure" (lines 224-260) — root module layout
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md D-09 (module path naming), D-11 (local state — no backend block), D-14 (region default ap-northeast-1, override us-east-1)
    - infra/modules/knowledge_base/outputs.tf (Task 1 output — root re-exports the four module outputs verbatim)
    - infra/modules/knowledge_base/variables.tf (Task 1 output — root passes name_prefix, env, region into the module)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-PATTERNS.md §".gitignore (modify)" — terraform.tfvars is committed (no secrets in Phase 1)
  </read_first>
  <action>
Create five files under `infra/envs/prod/`. The root is intentionally thin — it only configures the AWS provider and instantiates the `knowledge_base` module. Per D-11 there is NO `backend` block (local state for v1; remote backend deferred to RUNBOOK "Next steps"). Per D-14 region default is `ap-northeast-1` with override path documented.

**File 1: `infra/envs/prod/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
  }
  # No backend block — local state for v1 (D-11). See RUNBOOK "Next steps (deferred)" for remote backend migration.
}
```

**File 2: `infra/envs/prod/variables.tf`**

```hcl
variable "region" {
  description = "AWS region for prod deployment. Default ap-northeast-1; override to us-east-1 for dev (DEP-06)."
  type        = string
  default     = "ap-northeast-1"
}

variable "env" {
  description = "Environment suffix for resource names. \"prod\" yields hera-kb-prod (D-12 fixed names)."
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "Resource name prefix. Default \"hera\" (project name)."
  type        = string
  default     = "hera"
}
```

**File 3: `infra/envs/prod/main.tf`**

```hcl
provider "aws" {
  region = var.region
}

module "knowledge_base" {
  source = "../../modules/knowledge_base"

  name_prefix = var.name_prefix
  env         = var.env
  region      = var.region
}
```

**File 4: `infra/envs/prod/outputs.tf`** — re-exports the four module outputs verbatim so callers can `terraform -chdir=infra/envs/prod output -raw <name>` without descending into the module:

```hcl
output "kb_id" {
  description = "Bedrock Knowledge Base ID."
  value       = module.knowledge_base.kb_id
}

output "kb_arn" {
  description = "Bedrock Knowledge Base ARN. Consumed by Phase 2 to scope the consumer Pipecat role (D-10 deferred)."
  value       = module.knowledge_base.kb_arn
}

output "source_bucket_name" {
  description = "S3 source bucket name. Use with: aws s3 cp catalog/*.md s3://$(this)/catalog/"
  value       = module.knowledge_base.source_bucket_name
}

output "data_source_id" {
  description = "Bedrock data source ID. Required by aws bedrock-agent start-ingestion-job."
  value       = module.knowledge_base.data_source_id
}
```

**File 5: `infra/envs/prod/terraform.tfvars`** — committed (no secrets per PATTERNS.md). Contains only the documented defaults made explicit so a learner can see the current values without reading variables.tf:

```hcl
# Hera KB prod environment values.
# All three of these have defaults in variables.tf; this file makes them explicit for the workshop reader.
# Override at apply time with: terraform apply -var=region=us-east-1

region      = "ap-northeast-1"
env         = "prod"
name_prefix = "hera"
```

**Then run `terraform init && terraform validate` to prove the code parses and the module wires correctly. This is offline — no AWS credentials needed (init downloads the provider, validate checks syntax + types).**

```bash
cd infra/envs/prod
terraform init -input=false
terraform validate
cd ../../..
```

Both commands MUST exit 0. After `terraform init` succeeds, a `.terraform.lock.hcl` file appears in `infra/envs/prod/` — leave it in place (PATTERNS.md decision: commit the lock file for reproducibility; .gitignore from Plan 01 does NOT ignore it).

If `terraform validate` fails, do NOT proceed. Read the error, identify the root cause (per CLAUDE.md: prove the problem, then fix), and adjust the offending file. Common error patterns and the file to look at:

| Error pattern | File to fix |
|---------------|-------------|
| `Unsupported argument: name` on aws_s3vectors_vector_bucket | infra/modules/knowledge_base/main.tf — change `name` to `vector_bucket_name` |
| `Invalid value for argument "data_type"` | main.tf — must be lowercase `float32` |
| `Invalid value for argument "embedding_data_type"` | main.tf — must be UPPERCASE `FLOAT32` |
| `Reference to undeclared resource` (e.g. aws_iam_role_policy.kb_inline) | iam.tf — confirm Task 1 created the resource with that exact name |
| `Module not found at "../../modules/knowledge_base"` | check directory structure: `ls infra/modules/knowledge_base/` should list 5 .tf files |
  </action>
  <acceptance_criteria>
    - All five files exist: `test -f infra/envs/prod/versions.tf && test -f infra/envs/prod/main.tf && test -f infra/envs/prod/variables.tf && test -f infra/envs/prod/outputs.tf && test -f infra/envs/prod/terraform.tfvars`.
    - Root versions.tf pins to `~> 6.27` and `>= 1.9`: `grep -q '~> 6\.27' infra/envs/prod/versions.tf` AND `grep -q 'required_version = ">= 1\.9"' infra/envs/prod/versions.tf`.
    - Root versions.tf has NO backend block (D-11): `! grep -qE '^\s*backend\s+"' infra/envs/prod/versions.tf`.
    - Root variables.tf defaults region to `ap-northeast-1`: `grep -q 'default     = "ap-northeast-1"' infra/envs/prod/variables.tf`.
    - Root main.tf instantiates the module from the correct relative path: `grep -q 'source = "\.\./\.\./modules/knowledge_base"' infra/envs/prod/main.tf`.
    - Root main.tf passes name_prefix, env, region to the module: `grep -q 'name_prefix = var\.name_prefix' infra/envs/prod/main.tf` AND `grep -q 'env         = var\.env' infra/envs/prod/main.tf` AND `grep -q 'region      = var\.region' infra/envs/prod/main.tf`.
    - Root outputs.tf re-exports all four module outputs: `grep -q 'value       = module\.knowledge_base\.kb_id' infra/envs/prod/outputs.tf` AND `grep -q 'value       = module\.knowledge_base\.kb_arn' infra/envs/prod/outputs.tf` AND `grep -q 'value       = module\.knowledge_base\.source_bucket_name' infra/envs/prod/outputs.tf` AND `grep -q 'value       = module\.knowledge_base\.data_source_id' infra/envs/prod/outputs.tf`.
    - terraform.tfvars contains the three values: `grep -q 'region      = "ap-northeast-1"' infra/envs/prod/terraform.tfvars` AND `grep -q 'env         = "prod"' infra/envs/prod/terraform.tfvars` AND `grep -q 'name_prefix = "hera"' infra/envs/prod/terraform.tfvars`.
    - `cd infra/envs/prod && terraform init -input=false` exits 0 (provider download + module wiring succeeds offline).
    - `cd infra/envs/prod && terraform validate` exits 0 (syntax + type check passes — proves all argument names and casing are correct).
    - After `terraform init`, `.terraform.lock.hcl` exists in `infra/envs/prod/` (it MUST appear and MUST not be gitignored per Plan 01 + PATTERNS.md): `test -f infra/envs/prod/.terraform.lock.hcl`.
    - No emojis in any *.tf or .tfvars file under `infra/envs/prod/`: `python3 -c "import sys, re, pathlib; bad=[p for p in list(pathlib.Path('infra/envs/prod').glob('*.tf')) + list(pathlib.Path('infra/envs/prod').glob('*.tfvars')) if re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', p.read_text(encoding='utf-8'))]; sys.exit(0 if not bad else (print(bad) or 1))"` exits 0.
  </acceptance_criteria>
  <verify>
    <automated>test -f infra/envs/prod/versions.tf && test -f infra/envs/prod/main.tf && test -f infra/envs/prod/variables.tf && test -f infra/envs/prod/outputs.tf && test -f infra/envs/prod/terraform.tfvars && grep -q 'source = "\.\./\.\./modules/knowledge_base"' infra/envs/prod/main.tf && grep -q 'default     = "ap-northeast-1"' infra/envs/prod/variables.tf && (cd infra/envs/prod && terraform init -input=false && terraform validate) && test -f infra/envs/prod/.terraform.lock.hcl</automated>
  </verify>
  <done>
    Root files exist, the module wires correctly, `terraform init && terraform validate` exits 0 in offline mode, and the lock file is generated and ready to commit. The Phase 1 IaC is structurally sound and ready for Plan 03's live `terraform apply`.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Terraform local state -> filesystem -> git | State files contain ARNs, resource IDs, and (in some configurations) sensitive values. Plan 01 ignored `*.tfstate*`; this plan does not write state but creates the configuration that will produce state in Plan 03. |
| Bedrock service principal -> KB service role | The trust policy must scope assumption to this account AND to KB ARNs in this region (confused-deputy mitigation). |
| KB service role -> S3 source bucket / Titan v2 / S3 Vectors index | The inline policy must be least-privilege — every action enumerated, every ARN scoped. |
| AWS API call from operator's machine -> AWS account | Out of scope for this plan; Plan 03 is the first plan that calls AWS. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation |
|-----------|----------|-----------|----------|-------------|------------|
| T-02-01 | Information Disclosure | aws_s3_bucket.source (public exposure of catalog content) | high | mitigate | Task 2 creates `aws_s3_bucket_public_access_block` with all four `*_public_*` settings = `true`. Static website hosting is NOT enabled. Acceptance criteria check all four flags by exact-string grep. |
| T-02-02 | Elevation of Privilege | KB service role inline policy (over-permissioning) | high | mitigate | Task 1 enforces D-13: every Action is enumerated (no `bedrock:*` or `s3vectors:*` wildcards), every Resource is scoped to a specific ARN constructed from this region + this account + the specific bucket/index/model. Acceptance criterion runs a Python regex check that fails if any `actions = [...]` or `resources = [...]` block contains `"*"`. |
| T-02-03 | Elevation of Privilege | KB service role trust policy (cross-account confused deputy) | high | mitigate | Task 1 includes `aws:SourceAccount` (StringEquals on caller account) AND `AWS:SourceArn` (ArnLike on `arn:aws:bedrock:<region>:<account>:knowledge-base/*`) per RESEARCH.md Pattern 1. Acceptance criteria grep for both literals. Without these conditions, any AWS account whose Bedrock service tries to assume this role would succeed. |
| T-02-04 | Tampering | Trust principal misconfiguration | medium | mitigate | Task 1 acceptance criteria positively assert `bedrock.amazonaws.com` AND negatively assert `bedrockagent.amazonaws.com` is absent (Pitfall I — wrong principal silently fails at KB create time). |
| T-02-05 | Denial of Service | Accidental `terraform destroy` deletes catalog content | medium | accept | D-08 mandates `force_destroy = true` on the source bucket so destroy succeeds; this is an accepted risk per D-12. RUNBOOK.md (filled in Plan 03) documents the recovery: git checkout `catalog/` + re-upload + re-sync. Recovery cost is < $0.01 plus a few minutes. |
| T-02-06 | Information Disclosure | Local Terraform state file leakage | high | mitigate | Plan 01 added `*.tfstate*`, `.terraform/` to `.gitignore` BEFORE this plan runs `terraform init`. Acceptance criterion in Task 3 only requires `terraform init && validate` (no state-mutating operations); but even so, any state file produced by `init` (provider cache only — not a `.tfstate`) is gitignored by `.terraform/`. |
| T-02-07 | Information Disclosure | terraform.tfvars committed with secrets | low | mitigate | terraform.tfvars contains ONLY region, env, name_prefix — no AWS keys, no account IDs. PATTERNS.md verified. If a future variable adds a secret value, that variable MUST move to `terraform.tfvars.local` and be added to `.gitignore`. |
| T-02-08 | Spoofing | Foundation-model ARN format wrong (extra account segment) | low | mitigate | Task 1 asserts the verbatim form `arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0` (note double colon — no account segment). RESEARCH.md verified this format across multiple AWS docs pages. |
| T-02-09 | Tampering | Race condition where KB created before role policy attaches | medium | mitigate | Task 2 mandates `depends_on = [aws_iam_role_policy.kb_inline]` on the KB resource (RESEARCH.md Pattern 5 / Anti-Patterns). Without this, KB creation can transiently fail with AccessDenied during role-validation step. |

**No high-severity threats remain unmitigated.** T-02-01, T-02-02, T-02-03, T-02-06 are all `high` and all have concrete mitigations baked into the acceptance criteria. T-02-05 is the documented `accept` risk per D-08.
</threat_model>

<verification>

After all three tasks complete, the following checks must pass:

```bash
# 1. Module file count = 5
test "$(ls -1 infra/modules/knowledge_base/*.tf 2>/dev/null | wc -l)" -eq 5

# 2. Root file count = 4 .tf + 1 .tfvars = 5
test "$(ls -1 infra/envs/prod/*.tf 2>/dev/null | wc -l)" -eq 4
test -f infra/envs/prod/terraform.tfvars

# 3. Provider pin appears in BOTH versions.tf files
grep -q '~> 6\.27' infra/modules/knowledge_base/versions.tf
grep -q '~> 6\.27' infra/envs/prod/versions.tf

# 4. Zero IAM wildcards anywhere (D-13)
python3 -c "
import re, sys, pathlib
bad = []
for p in pathlib.Path('infra').rglob('*.tf'):
    t = p.read_text(encoding='utf-8')
    for m in re.finditer(r'(actions|resources)\s*=\s*\[[^\]]*\"\*\"', t):
        bad.append((str(p), m.group(0)[:80]))
if bad:
    print('FAIL — wildcard found in IAM:')
    for x in bad: print(' ', x)
    sys.exit(1)
print('OK: zero IAM wildcards')
"

# 5. terraform init && validate pass offline (no AWS credentials needed)
cd infra/envs/prod
terraform init -input=false
terraform validate
cd ../../..

# 6. .terraform.lock.hcl exists and is NOT gitignored (Plan 01 + PATTERNS.md decision)
test -f infra/envs/prod/.terraform.lock.hcl
git check-ignore infra/envs/prod/.terraform.lock.hcl 2>/dev/null && { echo "FAIL: lock file is gitignored"; exit 1; } || echo "OK: lock file is committable"

# 7. No emojis anywhere in infra/
python3 -c "
import re, sys, pathlib
bad = [p for p in pathlib.Path('infra').rglob('*') if p.is_file() and p.suffix in ('.tf', '.tfvars', '.hcl') and re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', p.read_text(encoding='utf-8', errors='ignore'))]
sys.exit(0 if not bad else (print(bad) or 1))
"

# 8. Hugo build still works (Hugo coexistence)
hugo --quiet --gc
```

All eight checks must exit 0 / print success.

</verification>

<success_criteria>

Plan 02 succeeds when:

1. **Module shape (D-08, D-09):** `infra/modules/knowledge_base/` exists with five files (`versions.tf`, `variables.tf`, `main.tf`, `iam.tf`, `outputs.tf`) and creates exactly the resources documented in D-08: source S3 bucket (with public-access-block), S3 Vectors bucket+index, Bedrock KB, data source, KB service role+policy. The four required outputs (`kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`) are exported.
2. **KB-02 verified by code:** `aws_s3vectors_vector_bucket` and `aws_s3vectors_index` are configured for Titan v2 — dimension 1024, data_type `float32` (lowercase), distance_metric `cosine` (lowercase). Pitfalls G and H (argument naming + case sensitivity) are addressed by verbatim copies from RESEARCH.md Pattern 4.
3. **KB-03 verified by code:** `aws_bedrockagent_knowledge_base` uses `s3_vectors_storage_configuration` with `index_arn` reference to the index, embedding_data_type `FLOAT32` (uppercase per the resource quirk), `depends_on = [aws_iam_role_policy.kb_inline]` to prevent the create-time race condition (RESEARCH.md Pattern 5).
4. **KB-05 verified by code:** KB service role has zero wildcards in Action or Resource (D-13). Trust policy uses `bedrock.amazonaws.com` (NOT `bedrockagent.amazonaws.com` — Pitfall I) with `aws:SourceAccount` AND `AWS:SourceArn` conditions (T-02-03 mitigation). Inline policy has three statements: S3 source list/get with `aws:ResourceAccount` condition, Bedrock InvokeModel scoped to the Titan v2 ARN, S3 Vectors actions enumerated and scoped to the specific bucket/index.
5. **Region defaults (D-14, DEP-06):** Region defaults to `ap-northeast-1`. Override path `terraform apply -var=region=us-east-1` is supported and documented in RUNBOOK (Plan 03).
6. **D-10 honored:** No consumer `bedrock:Retrieve` role exists in this module. Only `kb_arn` is exported so Phase 2 can scope its own role.
7. **D-11 honored:** No `backend` block in `infra/envs/prod/versions.tf` — local state for v1.
8. **D-12 honored:** Resource names are fixed strings derived from `${var.name_prefix}-kb-{...}-${var.env}`. No `random_id` or `random_pet` resource exists.
9. **`terraform init && terraform validate` pass offline:** Code is structurally valid and the module wires correctly without any AWS credentials. This proves the IaC will work in Plan 03's live apply.
10. **Hugo coexistence verified:** `hugo --quiet --gc` still exits 0 — the new `infra/` directory does not enter the Hugo build path.

</success_criteria>

<output>
After completion, create `.planning/phases/01-knowledge-base-foundation/01-02-SUMMARY.md` per the standard summary template. Include:
- All ten files created (5 module + 4 root + 1 tfvars)
- The `.terraform.lock.hcl` location (committed for reproducibility)
- Confirmation `terraform init && terraform validate` exited 0
- Confirmation Hugo build still passes
- The four module outputs (`kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`) and which Plan 03 task / which AWS CLI call consumes each
- Note that Plan 03 (verify script + RUNBOOK fill-in + live apply + ingestion + verify) is next
</output>
