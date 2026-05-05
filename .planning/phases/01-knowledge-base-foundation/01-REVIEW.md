---
phase: 01-knowledge-base-foundation
reviewed: 2026-05-05T00:00:00Z
depth: standard
files_reviewed: 18
files_reviewed_list:
  - .gitignore
  - CLAUDE.md
  - RUNBOOK.md
  - bin/verify-kb.sh
  - catalog/apple-watch-s11.md
  - catalog/iphone-13-pro-max.md
  - catalog/macbook-pro-m4.md
  - catalog/store-policy.md
  - infra/envs/prod/main.tf
  - infra/envs/prod/outputs.tf
  - infra/envs/prod/terraform.tfvars
  - infra/envs/prod/variables.tf
  - infra/envs/prod/versions.tf
  - infra/modules/knowledge_base/iam.tf
  - infra/modules/knowledge_base/main.tf
  - infra/modules/knowledge_base/outputs.tf
  - infra/modules/knowledge_base/variables.tf
  - infra/modules/knowledge_base/versions.tf
findings:
  critical: 2
  warning: 7
  info: 6
  total: 15
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-05-05
**Depth:** standard
**Files Reviewed:** 18
**Status:** issues_found

## Summary

Phase 1 ships a clean, narrowly-scoped Terraform module for an S3-Vectors-backed Bedrock Knowledge Base plus a verify shell script and four catalog markdown documents. The IAM is well thought out: trust principal is correct (`bedrock.amazonaws.com`, not `bedrockagent.amazonaws.com`), confused-deputy conditions are present, and the inline policy contains zero wildcards in `Action` or `Resource` per D-13. Resource naming is consistent with D-12, `force_destroy = true` is set on both buckets, and the depends_on chain correctly serializes IAM-policy-then-KB.

Two BLOCKER-class defects were found: (1) `bin/verify-kb.sh` resolves the KB ID from the prod terraform state even when invoked with `--region us-east-1`, so dev verifies will hit the wrong KB ID and report bogus AccessDenied / NotFound; (2) the polling loop in `bin/verify-kb.sh` will spin until timeout when an ingestion job enters `STOPPING` (a documented terminal-bound status missing from the case statement) — but more critically the `AccessDeniedException` surfacing branch is *inside* the non-invert path only and only runs *after* the success check has been skipped, never short-circuiting the loop and burning the entire 5-minute polling budget on every misconfigured run.

The remaining warnings cluster around defensive operability: the `AWS:SourceArn` condition key has inconsistent capitalization, the S3 source bucket lacks ownership-controls / default-encryption resources (Terraform AWS provider 6.x no longer infers them), the `infra/envs/prod/terraform.tfvars` file is not in `.gitignore` (low risk because contents are non-secret today, but a foot-gun for next phases that may add secrets), and the RUNBOOK polling loop has the same `STOPPING` gap as the script. The catalog content is clean — no PII, no secrets, no emojis, ingestion-friendly markdown.

## Critical Issues

### CR-01: `bin/verify-kb.sh` reads `kb_id` from prod state regardless of `--region`

**File:** `bin/verify-kb.sh:59-66`
**Issue:** When `--region us-east-1` is passed (the dev override path documented in RUNBOOK "First deploy" line 61), the script still falls back to `terraform -chdir=infra/envs/prod output -raw kb_id`. The prod state was last applied against `ap-northeast-1`, so the resolved `KB_ID` belongs to the *prod* KB while the `aws bedrock-agent-runtime retrieve` call is made against `us-east-1`. Result: a guaranteed `ResourceNotFoundException` from the dev region, which the script will misinterpret as either propagation lag (default mode — wastes 5 minutes) or successful cleanup (`--invert` mode — false-positive OK). The same bug fires whenever the operator has applied with `-var=region=us-east-1` because there is only one `infra/envs/prod/` directory holding both regions' state.

**Fix:** Either (a) require `--kb-id` explicitly when `--region` is non-default, or (b) add a region-consistency assertion. Minimal version:

```bash
# After resolving KB_ID from terraform state, sanity-check the region matches:
if [[ -z "${KB_ID_OVERRIDE:-}" ]]; then
  STATE_REGION=$(terraform -chdir=infra/envs/prod output -raw region 2>/dev/null \
    || awk -F'"' '/^region/ {print $2}' infra/envs/prod/terraform.tfvars)
  if [[ -n "${STATE_REGION}" && "${STATE_REGION}" != "${REGION}" ]]; then
    echo "ERROR: --region=${REGION} but terraform state was applied with region=${STATE_REGION}." >&2
    echo "Pass --kb-id explicitly to verify a different region." >&2
    exit 2
  fi
fi
```

(Also requires adding a `region` output to `infra/envs/prod/outputs.tf`, or parsing tfvars as a fallback.)

---

### CR-02: `bin/verify-kb.sh` poll loop ignores `STOPPING` status and the AccessDenied short-circuit is dead-after-first-attempt

**File:** `bin/verify-kb.sh:85-108`
**Issue:** Two compounding bugs in the poll body:

1. **`STOPPING` is unhandled.** The Bedrock ingestion job status enum is `STARTING | IN_PROGRESS | COMPLETE | FAILED | STOPPING | STOPPED`. The RUNBOOK's poll loop (line 102-104) checks only `COMPLETE|FAILED|STOPPED`, so a job that gets manually stopped will spin in `STOPPING` indefinitely until the user kills the process. (This is the RUNBOOK loop, not the verify-kb.sh loop, but both ship in this phase.)

2. **`AccessDeniedException` short-circuit lives below the success check.** At line 98 the script tests `[[ "${HITS}" -gt 0 ]]` first. When the API call returns the AccessDenied error response body, `RESP` is *not* JSON; `jq -r '.retrievalResults | length'` emits `null` (or aborts), and `HITS` becomes the literal string `null`. The next conditional `[[ "${HITS}" -gt 0 ]]` then fails with `integer expression expected` under `set -euo pipefail` — but because the test is on the *left* of `&&`, bash treats the whole compound as false and continues without erroring. The script falls through to the AccessDenied check at line 104 — but only on the *first* attempt; on attempts 2..20 the AccessDenied message is still printed but `exit 1` is never reached because `RESP` may be cached differently after the second loop iteration's failure. Even in the best case, the script burns one full 15-second sleep before surfacing the error rather than aborting on attempt 1.

   Worse: with `--query 'malformed'` (any non-JSON), the same path fires: `aws` returns a parse error, `jq` fails, the integer test fails silently, and the script polls for the full 5 minutes before reporting "no qualifying results."

**Fix:**

```bash
# (a) Detect non-JSON / error responses BEFORE jq parsing:
if ! echo "${RESP}" | jq -e . >/dev/null 2>&1; then
  if echo "${RESP}" | grep -qi 'AccessDeniedException'; then
    echo "ERROR: AccessDeniedException - check Bedrock model access and KB role" >&2
    echo "${RESP}" | head -5 >&2
    exit 1
  fi
  if echo "${RESP}" | grep -qiE 'ResourceNotFound|NotFound'; then
    if [[ "${INVERT}" == "1" ]]; then
      echo "OK (cleanup): KB no longer accessible"
      exit 0
    fi
    echo "ERROR: KB ${KB_ID} not found in ${REGION}" >&2
    exit 1
  fi
  echo "WARN: non-JSON response on attempt ${i}: $(echo "${RESP}" | head -1)" >&2
  sleep "${SLEEP_SECONDS}"
  continue
fi

HITS=$(echo "${RESP}" | jq -r '.retrievalResults | length')
TOP=$(echo "${RESP}" | jq -r '.retrievalResults[0].score // 0')
```

For the RUNBOOK ingestion-status loop (lines 102-104), add `STOPPING`:

```bash
case "${STATUS}" in
  COMPLETE|FAILED|STOPPED|STOPPING) break ;;
esac
```

## Warnings

### WR-01: `aws:SourceArn` condition key uses inconsistent capitalization (`AWS:SourceArn`)

**File:** `infra/modules/knowledge_base/iam.tf:25`
**Issue:** The trust policy uses `variable = "AWS:SourceArn"` (uppercase `AWS`), while the line above uses `variable = "aws:SourceAccount"` (lowercase `aws`). IAM condition keys are case-insensitive on the prefix today, but the canonical AWS documentation uses `aws:SourceArn`. Mixing capitalizations within the same trust policy is a code smell; future static-analysis tools (tfsec, checkov, AWS Access Analyzer policy validation) may flag the uppercase variant as non-canonical.

**Fix:**

```hcl
condition {
  test     = "ArnLike"
  variable = "aws:SourceArn"   # lowercase 'aws' to match line 19
  values   = ["arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"]
}
```

---

### WR-02: S3 source bucket has no default encryption / no ownership-controls / no versioning

**File:** `infra/modules/knowledge_base/main.tf:5-19`
**Issue:** The bucket relies entirely on AWS-account-level S3 defaults. Since April 2023 SSE-S3 (AES256) is the default for new buckets, so encryption-at-rest is OK *today*, but two gaps remain:

1. `aws_s3_bucket_ownership_controls` is not set. Provider 6.x defaults to `BucketOwnerEnforced` (ACLs disabled) for new buckets, but this is account/provider-version dependent. An explicit declaration locks the contract and prevents a future provider upgrade or AWS default change from silently re-enabling ACLs (which would in turn make the `block_public_acls = true` setting load-bearing in a way it isn't today).

2. No `aws_s3_bucket_versioning`. The catalog is small and re-uploadable from `git`, so this is intentional per RUNBOOK ("Recovery from accidental destroy is git checkout + re-upload"). But for ingestion debugging — when a syntactically valid markdown file gets re-embedded with bad chunks — a version history would be a 5-minute fix vs a `git log + blame` exercise. Worth adding for $0.001/month at workshop scale.

**Fix (ownership controls — required-quality fix):**

```hcl
resource "aws_s3_bucket_ownership_controls" "source" {
  bucket = aws_s3_bucket.source.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
```

Versioning is optional; if added, scope the lifecycle rule too so old versions aren't billed forever.

---

### WR-03: S3 Vectors bucket has no equivalent of `aws_s3_bucket_public_access_block`

**File:** `infra/modules/knowledge_base/main.tf:26-30`
**Issue:** The S3 *source* bucket gets a full public-access-block resource (lines 12-19). The S3 *Vectors* bucket — which holds the actual embedding vectors — does not. S3 Vectors is a separate service (`s3vectors`) and currently does not expose a public-access-block resource (`aws_s3vectors_*` doesn't have one yet), so this is a service-limitation gap rather than an oversight, and the inline IAM policy already constrains access to a single principal. Worth a one-line comment in `main.tf` documenting the asymmetry so a future reviewer doesn't "fix" it by adding an erroneous public-access-block.

**Fix:**

```hcl
resource "aws_s3vectors_vector_bucket" "this" {
  vector_bucket_name = "${var.name_prefix}-kb-vectors-${var.env}"
  force_destroy      = true
  # NOTE: no public_access_block equivalent exists for s3vectors today.
  # Access is gated entirely by IAM (see iam.tf S3VectorsReadWrite statement).
}
```

---

### WR-04: `infra/envs/prod/terraform.tfvars` is committed and not listed in `.gitignore`

**File:** `.gitignore:5-17`, `infra/envs/prod/terraform.tfvars`
**Issue:** `.gitignore` includes `*.tfstate*`, `.terraform/`, `override.tf`, but does NOT include `*.tfvars`. The current `terraform.tfvars` contents (`region`, `env`, `name_prefix`) are entirely non-secret — the comment at line 1-3 even says all three have defaults and the file is "explicit for the workshop reader." That's fine *today*. But Phase 2 / Phase 3 will introduce additional vars (likely API endpoints, possibly tokens for Pipecat / Twilio bootstrap) and the path-of-least-resistance habit of putting them in `terraform.tfvars` will accidentally commit secrets.

**Fix:** Add to `.gitignore` now, and split the workshop-visible values into a tracked `terraform.tfvars.example`:

```
# .gitignore additions
*.tfvars
!*.tfvars.example
```

Then `git mv infra/envs/prod/terraform.tfvars infra/envs/prod/terraform.tfvars.example` and update RUNBOOK "First deploy" to add a `cp terraform.tfvars.example terraform.tfvars` step.

---

### WR-05: `aws_bedrockagent_knowledge_base.this` has no explicit `depends_on` for the S3 vectors index

**File:** `infra/modules/knowledge_base/main.tf:57-85`
**Issue:** The KB references `aws_s3vectors_index.this.index_arn` at line 80, so Terraform infers the dependency. But the comment at line 55 emphasizes that `depends_on = [aws_iam_role_policy.kb_inline]` is required for permission validation — implying the author thought about explicit ordering. The KB's `CreateKnowledgeBase` call validates the index exists *and* validates the role can write to it. If the inline policy somehow attaches before the vector index is reachable from the AWS control plane (it shouldn't, but propagation), the KB create can return `ValidationException`. Adding the index to `depends_on` is belt-and-braces and matches the intent of the existing comment.

**Fix:**

```hcl
depends_on = [
  aws_iam_role_policy.kb_inline,
  aws_s3vectors_index.this,
]
```

This is low-priority because the implicit dependency through `index_arn` interpolation already handles 99% of cases. The remaining 1% is provider-side eventual consistency on the s3vectors index ARN materialization.

---

### WR-06: `bin/verify-kb.sh` `--query` passes user input directly into `aws` without JSON validation

**File:** `bin/verify-kb.sh:51, 81`
**Issue:** When the operator passes `--query '{"text":"..."}'` the value is forwarded as `--retrieval-query "${QUERY}"`. The AWS CLI parses this as JSON. If the operator forgets the outer quotes — e.g., `bin/verify-kb.sh --query '{"text":"What\'s in stock?"}'` — bash will mis-tokenize and pass a malformed string. The script doesn't validate `QUERY` is JSON before the loop, so it burns one 15-second sleep on each malformed-input invocation before falling through. (The CR-02 fix above handles this once added; flagged separately because it's an independent UX issue.)

**Fix:** After arg parse, before the loop:

```bash
echo "${QUERY}" | jq -e . >/dev/null 2>&1 \
  || { echo "ERROR: --query must be valid JSON, got: ${QUERY}" >&2; exit 2; }
```

---

### WR-07: RUNBOOK polling loop in "First sync" matches CR-02 — STOPPING status not handled

**File:** `RUNBOOK.md:102-104`
**Issue:** The same `STOPPING` gap as in CR-02 sub-bullet 1. RUNBOOK shows operators an ingestion-status poll loop that can hang on a manually-stopped job. Operators following this runbook in a workshop setting may see "status: STOPPING" repeated for hours.

**Fix:**

```bash
case "${STATUS}" in
  COMPLETE|FAILED|STOPPED|STOPPING) break ;;
esac
```

## Info

### IN-01: Provider version pin uses `~> 6.27` which only floors at 6.27.0 within the 6.x line

**File:** `infra/envs/prod/versions.tf:7`, `infra/modules/knowledge_base/versions.tf:7`
**Issue:** `~> 6.27` resolves to `>= 6.27, < 7.0`. This is fine for the pessimistic-constraint model, but a fresh `terraform init` next month may pick up `6.30+` with an `aws_bedrockagent_knowledge_base` schema change. The provider has been churning S3 Vectors APIs heavily; consider pinning to the exact tested minor (`~> 6.27.0` for `>= 6.27.0, < 6.28.0`) until Phase 2 ships and the stack is stable.

**Fix (optional, judgment call):**

```hcl
version = "~> 6.27.0"
```

---

### IN-02: `data.aws_caller_identity.current` declared in `iam.tf` but referenced from `main.tf` would also work

**File:** `infra/modules/knowledge_base/iam.tf:1`
**Issue:** Stylistic — the data source is in `iam.tf` but conceptually module-scoped. Most house styles place shared data sources in `data.tf` or `main.tf` so the IAM file contains only IAM resources. Trivial; no behavior change.

**Fix:** Move `data "aws_caller_identity" "current" {}` to `main.tf` line 1 (above the S3 source bucket), keeping `iam.tf` purely for IAM.

---

### IN-03: `force_destroy = true` on the source bucket has no companion warning in tfvars

**File:** `infra/envs/prod/terraform.tfvars:1-3`
**Issue:** A workshop attendee who copies `terraform.tfvars` for a non-workshop deploy will inherit `force_destroy = true` on a bucket that may end up holding production catalog data. The comment in `main.tf:2` explains why (workshop teardown), but a `terraform.tfvars.example` (see WR-04) should warn that this is workshop-mode.

**Fix:** Comment block in tfvars (or .example) that explicitly says "workshop mode: buckets force-destroyable, not production-grade."

---

### IN-04: Catalog stock counts are embedded in prose rather than a structured block

**File:** `catalog/iphone-13-pro-max.md:23`, `catalog/macbook-pro-m4.md:26`, `catalog/apple-watch-s11.md:28`
**Issue:** Stock & Availability sections use prose ("12 units of 128 GB Sierra Blue, 8 units of 256 GB Graphite"). Phase 2 retrieval is keyword-based via Titan v2 embeddings, so prose is fine for v1. But a future "show me only in-stock SKUs" requirement will need parsing — at which point a bulleted list with consistent SKU strings would re-embed cleanly without a content rewrite. Not a defect; a forward-compatibility note.

**Fix:** Optional. Restructure as bulleted list per SKU in v2 if filterable retrieval becomes a requirement.

---

### IN-05: Catalog files do not include a "last updated" or "source of truth" line

**File:** `catalog/*.md` (all four)
**Issue:** When the verify script returns top score 0.86 for "iPhone 13 Pro Max stock" (per project context note), the operator can't tell from the markdown when the stock count was last verified. Workshops inevitably go stale; an explicit `Last verified: 2026-MM-DD` line makes the data lineage obvious. Has zero impact on Phase 1 verification but reduces "wait, is this still accurate?" friction in Phase 2 demos.

**Fix:** Add to each catalog file:

```markdown
## Stock & Availability
*Last verified: 2026-05-05*

iPhone 13 Pro Max current stock at the store: 12 units of 128 GB Sierra Blue...
```

---

### IN-06: `RUNBOOK.md` "Pre-flight" check uses bash heredoc but the project supports PowerShell operators

**File:** `RUNBOOK.md:11-21, 25-32, 44-50, 73-107`
**Issue:** Per `<env>` and CLAUDE.md, the project's primary operator works on Windows (`PowerShell` shell). All runbook code blocks are bash-only — they assume `$(...)` command substitution, `case ... esac`, and `while true; do` semantics. A Windows operator copy-pasting the "First sync" loop will fail on the `$(aws ...)` substitution in PowerShell syntax. RUNBOOK should either (a) declare bash-only at the top with a note about WSL / Git Bash, or (b) add a parallel PowerShell snippet for each command.

**Fix:** Add a one-liner at the top of "Pre-flight":

```markdown
> **Shell:** All commands in this runbook assume bash (Linux/macOS/WSL/Git Bash). PowerShell operators should run these in a `bash` shell — `wsl bash` or `bash.exe` from Git for Windows both work.
```

---

_Reviewed: 2026-05-05_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
