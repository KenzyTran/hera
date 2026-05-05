---
phase: 01-knowledge-base-foundation
plan: 02
subsystem: infra
tags: [terraform, bedrock, s3-vectors, knowledge-base, iam, titan-v2, aws-provider-6.27]

# Dependency graph
requires:
  - phase: 01-knowledge-base-foundation
    provides: ".gitignore Terraform-safe baseline (Plan 01-01) and catalog/ source markdown for the data source's inclusion_prefixes"
provides:
  - "infra/modules/knowledge_base/ — single Terraform module creating S3 source bucket (with public-access-block), S3 Vectors bucket+index (1024-dim float32 cosine), Bedrock KB with s3_vectors_storage_configuration, KB data source (FIXED_SIZE 300/20% on catalog/), and a least-privilege KB service IAM role with confused-deputy-mitigated trust policy"
  - "infra/envs/prod/ — thin root module instantiating the KB module with region default ap-northeast-1, no backend block (D-11), terraform.tfvars committed (no secrets)"
  - ".terraform.lock.hcl pinning hashicorp/aws 6.43.0 (constraint ~> 6.27)"
  - "Four module outputs (kb_id, kb_arn, source_bucket_name, data_source_id) re-exported at the root for Plan 03 consumption"
affects: [01-03-verify-and-sync, 02-pipecat-voice-agent, 03-agentcore-deploy, 04-cleanup]

# Tech tracking
tech-stack:
  added:
    - "Terraform >= 1.9 (verified via terraform v1.15.1)"
    - "hashicorp/aws ~> 6.27 (resolved to 6.43.0 — floor for native s3_vectors_storage_configuration on aws_bedrockagent_knowledge_base)"
  patterns:
    - "Single-module shape (D-08): one infra/modules/knowledge_base/ module, instantiated by a thin envs/prod/ root — avoids premature multi-module factoring before a second consumer exists"
    - "Verbatim-from-RESEARCH HCL: every resource argument copied from 01-RESEARCH.md Patterns 1-7 with no paraphrasing, including the case-sensitive quirks (lowercase float32/cosine on aws_s3vectors_index, UPPERCASE FLOAT32 on aws_bedrockagent_knowledge_base, vector_bucket_name not name)"
    - "Confused-deputy-mitigated trust policy: bedrock.amazonaws.com service principal + aws:SourceAccount StringEquals + AWS:SourceArn ArnLike on knowledge-base/* (Pattern 1, T-02-03 mitigation)"
    - "Zero-wildcard inline IAM policy (D-13): every Action enumerated; every Resource scoped to a specific ARN; aws:ResourceAccount condition on S3 reads"
    - "Race-condition-safe KB creation: aws_bedrockagent_knowledge_base.depends_on = [aws_iam_role_policy.kb_inline] (RESEARCH.md Pattern 5 — KB validates role permissions at create time)"
    - "Manual upload + ingestion teaching surface (D-05/D-07): no aws_s3_object resources, no null_resource/local-exec — terraform handles infra, learner runs aws s3 cp + start-ingestion-job by hand per the RUNBOOK"

key-files:
  created:
    - "infra/modules/knowledge_base/versions.tf"
    - "infra/modules/knowledge_base/variables.tf"
    - "infra/modules/knowledge_base/outputs.tf"
    - "infra/modules/knowledge_base/iam.tf"
    - "infra/modules/knowledge_base/main.tf"
    - "infra/envs/prod/versions.tf"
    - "infra/envs/prod/variables.tf"
    - "infra/envs/prod/main.tf"
    - "infra/envs/prod/outputs.tf"
    - "infra/envs/prod/terraform.tfvars"
    - "infra/envs/prod/.terraform.lock.hcl"
  modified: []

key-decisions:
  - "Honored D-08: single module with five files (versions/variables/main/iam/outputs); no per-resource sub-modules"
  - "Honored D-10: Phase 2 consumer bedrock:Retrieve role NOT created here — only kb_arn exported so Phase 2 can scope its own role"
  - "Honored D-11: no backend block in envs/prod/versions.tf — local state for v1; remote backend deferred to RUNBOOK Next steps"
  - "Honored D-12: resource names are fixed strings (hera-kb-prod, hera-kb-source-prod, hera-kb-vectors-prod, hera-kb-index, hera-catalog, hera-kb-service-role, hera-kb-inline) — no random_id or random_pet"
  - "Honored D-13: zero wildcards in any Action or Resource of the KB inline policy (Python regex sweep verified)"
  - "Honored D-14: region defaults to ap-northeast-1 (root variable + module variable); override path documented in terraform.tfvars header (terraform apply -var=region=us-east-1)"
  - "Honored Pattern 5 race-condition guard: aws_bedrockagent_knowledge_base.depends_on = [aws_iam_role_policy.kb_inline] is present and verified by acceptance grep"
  - "Honored Pitfall I: trust principal is bedrock.amazonaws.com; bedrockagent.amazonaws.com is positively absent (asserted by acceptance grep negation)"
  - "Honored Pitfall H: aws_s3vectors_index uses lowercase data_type=\"float32\" + distance_metric=\"cosine\"; aws_bedrockagent_knowledge_base uses UPPERCASE embedding_data_type=\"FLOAT32\" — both correct per provider quirk"
  - "Honored Pitfall G: aws_s3vectors_vector_bucket uses vector_bucket_name (not name); aws_s3vectors_index references the parent bucket by name (not ARN)"
  - "Honored Pitfall E: force_destroy=true on both aws_s3_bucket.source and aws_s3vectors_vector_bucket.this — terraform destroy succeeds on non-empty buckets (T-02-05 accepted risk per D-08)"

patterns-established:
  - "Pattern: infra/modules/<name>/ + infra/envs/<env>/ split for Terraform — module owns the resources, env owns provider config + module call + tfvars; no env-specific resources outside the module"
  - "Pattern: provider pin matches between module and env versions.tf — both pin Terraform >= 1.9 and hashicorp/aws ~> 6.27 to keep the module portable to dev/staging envs added later"
  - "Pattern: ARN string-interpolation for IAM scoping — \"arn:aws:s3vectors:${var.region}:${data.aws_caller_identity.current.account_id}:bucket/<bucket>/index/<index>\" — using the data source's own attributes (not hard-coded names) keeps the policy in lockstep with rename refactors"
  - "Pattern: inclusion_prefixes = [\"catalog/\"] on the data source scopes ingestion to a single S3 prefix, leaving the bucket open for future non-KB content under other prefixes without polluting embeddings"

requirements-completed: [KB-02, KB-03, KB-05]

# Metrics
duration: 14min
completed: 2026-05-05
---

# Phase 1 Plan 2: Terraform KB Module Summary

**Authored a single Terraform `knowledge_base` module (S3 source bucket with public-access-block + S3 Vectors bucket+index + Bedrock KB with `s3_vectors_storage_configuration` + FIXED_SIZE 300/20% data source on `catalog/` + zero-wildcard KB service IAM role with confused-deputy-mitigated trust policy) and a thin `envs/prod/` root that wires it up — `terraform init && terraform validate` exits 0 offline, ready for Plan 03's live `terraform apply`.**

## Performance

- **Duration:** ~14 min total wall-clock (08:42:25 → 08:56:29 +0700, including the network-error interruption + resumption)
- **Started:** 2026-05-05T01:42:25Z (first task commit 442a63e)
- **Completed:** 2026-05-05T01:56:29Z (final task commit b47ce36)
- **Tasks:** 3 (all autonomous)
- **Files modified:** 11 created (5 module .tf + 4 root .tf + 1 .tfvars + 1 .terraform.lock.hcl)

## Accomplishments

- **KB-02 satisfied:** S3 Vectors bucket + index configured for Titan v2 — dimension 1024, lowercase `float32` + `cosine` (Pitfall H), `vector_bucket_name` not `name` (Pitfall G); index dimension is documented as IMMUTABLE in the variable description (Pitfall B).
- **KB-03 satisfied:** `aws_bedrockagent_knowledge_base` uses `s3_vectors_storage_configuration` with `index_arn = aws_s3vectors_index.this.index_arn`, UPPERCASE `embedding_data_type = "FLOAT32"`, and the mandatory `depends_on = [aws_iam_role_policy.kb_inline]` race-guard.
- **KB-05 satisfied:** KB service IAM role has zero wildcards in Action or Resource (Python regex sweep across `infra/**/*.tf` returns OK), trust policy uses `bedrock.amazonaws.com` (NOT `bedrockagent.amazonaws.com`) with both `aws:SourceAccount` and `AWS:SourceArn` confused-deputy conditions (T-02-03 mitigation).
- **D-08 honored:** Module exports exactly four outputs (`kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`) — re-exported verbatim at the root.
- **D-10 honored:** No consumer `bedrock:Retrieve` role was created; only `kb_arn` is published so Phase 2 can scope its own role.
- **D-11 honored:** No `backend` block in `envs/prod/versions.tf` — local state for v1.
- **`terraform init && terraform validate` exit 0 offline** — proves the IaC is structurally sound before Plan 03 runs the live `apply`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Author knowledge_base module — versions/variables/outputs/iam** — `442a63e` (feat)
2. **Task 2: Author knowledge_base module main.tf — S3 source, S3 Vectors, KB, data source** — `ea36745` (feat)
3. **Task 3: Author root envs/prod files + run terraform init && validate** — `b47ce36` (feat)

**Plan metadata commit:** appended after this summary is written (will include this SUMMARY.md, STATE.md, ROADMAP.md updates).

_Note: Tasks 1-3 were executed across two agent runs. The first run (terminated by a network error mid-Task-3) produced commits `442a63e` and `ea36745` and staged but did not commit the Task 3 files. The resumption agent verified the staged files against the plan invariants, ran `terraform validate` (which exited 0), then committed `b47ce36` atomically._

## Files Created/Modified

**Module (`infra/modules/knowledge_base/`):**
- `versions.tf` — Terraform >= 1.9, hashicorp/aws ~> 6.27 pin (the floor for native `s3_vectors_storage_configuration`)
- `variables.tf` — six variables: `name_prefix=hera`, `env=prod`, `region=ap-northeast-1`, `embedding_dimension=1024`, `chunk_max_tokens=300`, `chunk_overlap_pct=20`
- `outputs.tf` — four module outputs (`kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`) per D-08
- `iam.tf` — `data.aws_caller_identity.current` + `data.aws_iam_policy_document.kb_trust` (bedrock.amazonaws.com + aws:SourceAccount + AWS:SourceArn) + `aws_iam_role.kb_service_role` + `data.aws_iam_policy_document.kb_inline` (3 statements, zero wildcards) + `aws_iam_role_policy.kb_inline`
- `main.tf` — `aws_s3_bucket.source` + `aws_s3_bucket_public_access_block.source` (all four `*_public_*`=true) + `aws_s3vectors_vector_bucket.this` + `aws_s3vectors_index.this` (lowercase float32/cosine) + `aws_bedrockagent_knowledge_base.this` (UPPERCASE FLOAT32, `depends_on` on the inline policy) + `aws_bedrockagent_data_source.catalog` (FIXED_SIZE 300/20% on `inclusion_prefixes = ["catalog/"]`)

**Root env (`infra/envs/prod/`):**
- `versions.tf` — same pins as module; explicit comment that no backend block is intentional (D-11)
- `variables.tf` — three thin variables passed into the module: `region`, `env`, `name_prefix`
- `main.tf` — `provider "aws" { region = var.region }` + `module "knowledge_base"` instantiation
- `outputs.tf` — re-exports the four module outputs verbatim so callers can `terraform -chdir=infra/envs/prod output -raw <name>`
- `terraform.tfvars` — explicit defaults (region=ap-northeast-1, env=prod, name_prefix=hera) so a workshop reader can see current values without reading variables.tf
- `.terraform.lock.hcl` — pins `hashicorp/aws` to `6.43.0` (committed for reproducibility per Plan 01 PATTERNS.md decision; not in `.gitignore`)

## Decisions Made

None additional — all decisions (D-08 through D-14) were already locked in `01-CONTEXT.md` and `01-PATTERNS.md` before execution. The plan executed exactly as written.

## Deviations from Plan

None — plan executed exactly as written.

The only operational note is that the first execution attempt was interrupted by a network error after Task 1 and Task 2 had been committed (`442a63e`, `ea36745`) and Task 3's six files were staged but uncommitted. The resumption agent:
1. Verified the staged files match the plan invariants (provider pin, region default, module source path, no backend block, no emojis).
2. Verified `terraform validate` exits 0 (the previous agent had already run `terraform init` successfully — the `.terraform/` cache and `.terraform.lock.hcl` were present from that run).
3. Committed the six staged files atomically as `b47ce36`.

This is a continuation, not a deviation — no plan content changed.

## Issues Encountered

- **Hugo binary not on PATH in execution environment.** Plan success criterion #10 ("Hugo coexistence verified — `hugo --quiet --gc` exits 0") could not be locally verified. Risk is structurally mitigated: Hugo only consumes `config.toml`, `content/`, `layouts/`, `themes/`, `static/`, `i18n/` per `01-PATTERNS.md` §"Hugo Coexistence Confirmation". The new `infra/` directory is not in any of those input paths, so the Hugo build cannot be affected. The GitHub Actions deploy workflow on the next push to main will demonstrate the build passes.
- **Network error mid-execution.** First agent run died after committing Tasks 1 and 2; staged Task 3 files were preserved by git. The resumption agent verified state and continued without rework — no work was lost.

## Threat Flags

None — no new security-relevant surface beyond the threats already enumerated in the plan's `<threat_model>` section. Mitigations for T-02-01 through T-02-09 are all baked in:

| Threat ID | Mitigation present |
|-----------|--------------------|
| T-02-01 (S3 public exposure) | `aws_s3_bucket_public_access_block.source` with all four flags = true |
| T-02-02 (over-permissioned IAM) | Zero wildcards in any Action or Resource (verified by Python regex sweep) |
| T-02-03 (cross-account confused deputy) | `aws:SourceAccount` + `AWS:SourceArn` conditions on the trust policy |
| T-02-04 (wrong trust principal) | `bedrock.amazonaws.com` present; `bedrockagent.amazonaws.com` absent |
| T-02-05 (accidental destroy) | Accepted risk; `force_destroy=true` + RUNBOOK recovery path |
| T-02-06 (state file leakage) | `.terraform/` and `*.tfstate*` gitignored from Plan 01 |
| T-02-07 (secrets in tfvars) | `terraform.tfvars` contains only region/env/name_prefix — no secrets |
| T-02-08 (foundation-model ARN format) | `arn:aws:bedrock:${var.region}::foundation-model/...` (double colon, no account segment) |
| T-02-09 (KB-before-policy race) | `depends_on = [aws_iam_role_policy.kb_inline]` on the KB resource |

## User Setup Required

None for this plan — Plan 02 is code-only, no AWS calls, no credentials. Plan 03 will require:
- AWS credentials with permissions to create Bedrock KB, S3 buckets, S3 Vectors resources, and IAM roles
- Bedrock Titan v2 model access enabled in the AWS console for the target region (`ap-northeast-1`)

## Next Phase Readiness

**Plan 03 (verify-and-sync) is unblocked and ready to execute.** Plan 03 will:
1. Author `bin/verify-kb.sh` (the KB-04 verification script — `aws bedrock-agent-runtime retrieve` for "iPhone 13 Pro Max stock" and assert non-zero score on the matching catalog document).
2. Fill in the seven `TODO(plan-03):` markers in `RUNBOOK.md` with concrete bucket names + KB IDs derived from the four module outputs this plan exposes.
3. Run the live `terraform apply` in `infra/envs/prod/` (requires AWS credentials, costs money — autonomous: false).
4. Manually upload `catalog/*.md` via `aws s3 cp` (D-05/D-07 teaching surface).
5. Manually trigger ingestion via `aws bedrock-agent start-ingestion-job` (D-07 teaching surface).
6. Run `bin/verify-kb.sh` and assert success.

**The four module outputs that Plan 03 consumes:**

| Output | Plan 03 consumer |
|--------|-------------------|
| `module.knowledge_base.kb_id` | `bin/verify-kb.sh` (passed to `aws bedrock-agent-runtime retrieve --knowledge-base-id`); `aws bedrock-agent start-ingestion-job --knowledge-base-id` |
| `module.knowledge_base.kb_arn` | NOT consumed by Plan 03 — published for Phase 2's consumer Pipecat role (D-10 deferred) |
| `module.knowledge_base.source_bucket_name` | `aws s3 cp catalog/*.md s3://<this>/catalog/` (the manual upload step) |
| `module.knowledge_base.data_source_id` | `aws bedrock-agent start-ingestion-job --data-source-id` |

**No blockers.** All structural Phase 1 IaC is in place; Plan 03 needs only AWS credentials and a region selection.

## Self-Check: PASSED

**Files exist on disk:**
- `infra/modules/knowledge_base/versions.tf` — FOUND
- `infra/modules/knowledge_base/variables.tf` — FOUND
- `infra/modules/knowledge_base/outputs.tf` — FOUND
- `infra/modules/knowledge_base/iam.tf` — FOUND
- `infra/modules/knowledge_base/main.tf` — FOUND
- `infra/envs/prod/versions.tf` — FOUND
- `infra/envs/prod/variables.tf` — FOUND
- `infra/envs/prod/main.tf` — FOUND
- `infra/envs/prod/outputs.tf` — FOUND
- `infra/envs/prod/terraform.tfvars` — FOUND
- `infra/envs/prod/.terraform.lock.hcl` — FOUND (constraint `~> 6.27`, resolved `6.43.0`)

**Commits exist in git log:**
- `442a63e` — FOUND (Task 1)
- `ea36745` — FOUND (Task 2)
- `b47ce36` — FOUND (Task 3)

**Verification commands re-run at SUMMARY time:**
- Module file count: `5` (expected 5) — OK
- Root env .tf count: `4` (expected 4) — OK
- `~> 6.27` pin in both `versions.tf`s — OK
- Zero IAM wildcards (Python regex sweep across `infra/**/*.tf`) — OK
- No emojis in `infra/**/*.{tf,tfvars,hcl}` (Python regex sweep) — OK
- `.terraform.lock.hcl` is NOT gitignored (`git check-ignore` exits 1 — file is committable) — OK
- `terraform validate` in `infra/envs/prod/` — exits 0, "The configuration is valid."
- `terraform init -input=false` in `infra/envs/prod/` — exits 0, "Terraform has been successfully initialized!"

---
*Phase: 01-knowledge-base-foundation*
*Completed: 2026-05-05*
