---
phase: 01-knowledge-base-foundation
plan: 03
type: execute
wave: 1
depends_on:
  - "01-01"
  - "01-02"
files_modified:
  - bin/verify-kb.sh
  - RUNBOOK.md
autonomous: false
requirements:
  - KB-04
  - KB-06

must_haves:
  truths:
    - "bin/verify-kb.sh exists, is executable, has no emojis, and uses the verbatim D-15 + RESEARCH.md skeleton (15s polling for max 5 minutes; jq path .retrievalResults[0].score; --invert flag for Phase 4 reuse per D-16)."
    - "RUNBOOK.md has all eight sections fully written — the seven TODO(plan-03) markers from Plan 01 are replaced with actual aws/terraform commands."
    - "RUNBOOK.md First sync section uses 'aws bedrock-agent start-ingestion-job' (NOT 'aws bedrock-agent-runtime start-ingestion-job' — Pitfall J distinguishes the two CLI surfaces)."
    - "RUNBOOK.md Recovery section documents 'terraform destroy && terraform apply' per D-12 — no random suffix, no terraform import recipes."
    - "RUNBOOK.md Pre-flight section enumerates the four blocking deps (Terraform >= 1.9, AWS CLI v2, jq, AWS credentials) AND documents the Bedrock Titan v2 model-access enable step in ap-northeast-1 (Pitfall A)."
    - "End-to-end live verification passes: terraform apply succeeds in ap-northeast-1, aws s3 cp uploads four catalog files, start-ingestion-job completes, bin/verify-kb.sh prints OK with hits >= 1 and top score >= 0.4, exits 0. KB-04 success criterion is verified."
    - "Re-index path verified: editing one catalog file, re-running aws s3 cp + start-ingestion-job, bin/verify-kb.sh still passes — KB-06 success criterion verified."
  artifacts:
    - path: "bin/verify-kb.sh"
      provides: "KB-04 verification script — polls bedrock-agent-runtime retrieve until results appear with score above threshold (D-15). Reusable in Phase 4 cleanup with --invert (D-16)."
      contains: "bedrock-agent-runtime retrieve"
    - path: "RUNBOOK.md"
      provides: "Operational runbook — pre-flight, deploy, sync, verify, re-index, recovery, cleanup (D-06, D-11, D-12)"
      contains: "start-ingestion-job"
  key_links:
    - from: "bin/verify-kb.sh"
      to: "infra/envs/prod terraform output -raw kb_id"
      via: "terraform -chdir=infra/envs/prod output -raw kb_id (when --kb-id flag absent)"
      pattern: "terraform -chdir=infra/envs/prod output -raw kb_id"
    - from: "bin/verify-kb.sh"
      to: "AWS Bedrock KB Retrieve API"
      via: "aws bedrock-agent-runtime retrieve --knowledge-base-id $KB_ID --retrieval-query"
      pattern: "aws bedrock-agent-runtime retrieve"
    - from: "RUNBOOK.md First sync"
      to: "infra/envs/prod outputs (source_bucket_name, kb_id, data_source_id)"
      via: "documented bash one-liners using terraform -chdir=infra/envs/prod output -raw"
      pattern: "terraform -chdir=infra/envs/prod output -raw source_bucket_name"
---

<objective>
Ship the KB-04 verification artifact (`bin/verify-kb.sh`), fill in the seven Plan-01 TODO markers in `RUNBOOK.md` with the real sync/verify/recovery commands, then run the end-to-end live workflow on the user's AWS account: `terraform apply` -> upload `catalog/*.md` -> trigger ingestion job -> wait for propagation -> run `verify-kb.sh` -> see PASS.

This is the only plan in Phase 1 that calls AWS. It is `autonomous: false` because three tasks (`terraform apply`, `start-ingestion-job`, `verify-kb.sh` execution) require the user's AWS credentials. The script-write task and the RUNBOOK-fill task are autonomous.

Purpose: Phase 1 success criterion #2 ("Running `aws bedrock-agent-runtime retrieve` for the query 'iPhone 13 Pro Max stock' returns the matching catalog document with non-zero score, after the documented post-sync wait") is verified for-real in this plan. Phase 1 success criterion #5 ("Re-indexing after editing a product markdown is a single documented CLI command, and the new content is queryable within the documented sync window") is verified in Task 5's re-index walkthrough. The script is also designed for D-16 reuse — Phase 4 cleanup will run `bin/verify-kb.sh --invert` to confirm the KB is gone post-`terraform destroy`.

Output: One bash script (`bin/verify-kb.sh`), one fully-completed runbook (`RUNBOOK.md` with no remaining TODO(plan-03) markers), and live AWS resources (KB, S3 buckets, S3 Vectors index, ingested vectors) that survive past the plan boundary for Phase 2 to consume.
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
@C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-01-repo-skeleton-and-catalog-PLAN.md
@C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-02-terraform-kb-module-PLAN.md
@C:/Users/trant/projects/hera/CLAUDE.md

<interfaces>
<!-- Outputs from Plan 02's terraform module that this plan consumes: -->
<!--   terraform -chdir=infra/envs/prod output -raw kb_id              -> string  (used by verify-kb.sh and start-ingestion-job) -->
<!--   terraform -chdir=infra/envs/prod output -raw kb_arn             -> string  (informational only this plan; consumed by Phase 2) -->
<!--   terraform -chdir=infra/envs/prod output -raw source_bucket_name -> string  (used by aws s3 cp) -->
<!--   terraform -chdir=infra/envs/prod output -raw data_source_id     -> string  (used by start-ingestion-job) -->

<!-- Catalog files from Plan 01 that this plan uploads: -->
<!--   catalog/apple-watch-s11.md -->
<!--   catalog/iphone-13-pro-max.md   <- KB-04 verify query targets this -->
<!--   catalog/macbook-pro-m4.md -->
<!--   catalog/store-policy.md -->

<!-- RUNBOOK.md TODO markers from Plan 01 to be replaced (one per section, total 7): -->
<!--   ## Pre-flight                          - TODO(plan-03): pre-flight commands and Bedrock model-access screenshot path. -->
<!--   ## First deploy                        - TODO(plan-03): exact terraform commands and expected output. -->
<!--   ## First sync                          - TODO(plan-03): start-ingestion-job + get-ingestion-job poll loop. -->
<!--   ## Verify                              - TODO(plan-03): verify-kb.sh invocation and pass/fail interpretation. -->
<!--   ## Re-index after editing a product    - TODO(plan-03): re-index workflow. -->
<!--   ## Recovery from a half-failed apply   - TODO(plan-03): destroy-then-reapply walkthrough. -->
<!--   ## Cleanup                             - TODO(plan-03): destroy + invert-verify. -->
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Author bin/verify-kb.sh from the verified D-15 skeleton</name>
  <files>bin/verify-kb.sh</files>
  <read_first>
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"verify-kb.sh skeleton (D-15)" (lines 762-849) — VERBATIM bash skeleton; copy this into the file with minor adjustments noted below
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md D-15 (behavior: --kb-id flag, polling 15s/5min, score-threshold check, clear human-readable failure messages) and D-16 (Phase 4 reuse via --invert)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-PATTERNS.md §"bin/verify-kb.sh" — script style conventions (#!/usr/bin/env bash for portability; no emojis; explicit exit codes; --help flag)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Retrieve API call" (lines 725-760) — verified jq path is .retrievalResults[0].score (flat double, not nested)
    - C:/Users/trant/projects/hera/CLAUDE.md (no emojis in print statements; bash, not Python — D-15)
  </read_first>
  <action>
Create `bin/verify-kb.sh`. Use the RESEARCH.md skeleton verbatim with the following minor additions (each justified by D-15 or PATTERNS.md):

1. **Shebang** — use `#!/usr/bin/env bash` for portability across dev machines (PATTERNS.md "may prefer #!/usr/bin/env bash for portability across dev machines"). The RESEARCH.md skeleton uses this shebang already.
2. **Header block** — single-line purpose + behavior summary (PATTERNS.md "Header pattern" from `.claude/hooks/gsd-validate-commit.sh`).
3. **--help flag** — D-15 mentions a `--kb-id` flag; PATTERNS.md mentions a `--help` block. Add a small usage block printed when `--help` is passed.
4. **Region default** — `${HERA_REGION:-ap-northeast-1}` so the script defaults to the same region as the Terraform module (D-14).

Final script contents (this is the verbatim RESEARCH.md skeleton with the four additions above):

```bash
#!/usr/bin/env bash
# bin/verify-kb.sh - Phase 1 KB-04 verification script.
# Polls the Bedrock KB Retrieve API every 15s for up to 5 minutes until results appear with a score above threshold.
# Exits 0 on success (default) or when KB is unreachable (--invert mode for Phase 4 cleanup, D-16).
# Exits non-zero with a human-readable message on timeout, empty results, or access denied.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --kb-id ID          Knowledge Base ID. If omitted, read from terraform output.
  --region REGION     AWS region. Default: ap-northeast-1 (or HERA_REGION env var).
  --query JSON        Retrieval query as JSON. Default: {"text":"iPhone 13 Pro Max stock"}.
  --threshold N       Minimum top score for success. Default: 0.4 (or HERA_KB_SCORE_THRESHOLD env var).
  --invert            Phase 4 cleanup mode: success when KB is unreachable.
  --help              Show this message and exit.

Exit codes:
  0   Verification passed (results found above threshold, or in --invert mode KB is unreachable).
  1   Verification failed (timeout, empty results, or in --invert mode KB still responds).
  2   Argument error.

Examples:
  $(basename "$0")
  $(basename "$0") --kb-id ABCD1234EFGH
  $(basename "$0") --invert
EOF
}

# --- defaults / args ---
REGION="${HERA_REGION:-ap-northeast-1}"
QUERY='{"text":"iPhone 13 Pro Max stock"}'
THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"
MAX_ATTEMPTS=20
SLEEP_SECONDS=15
KB_ID=""
INVERT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kb-id)     KB_ID="$2"; shift 2 ;;
    --region)    REGION="$2"; shift 2 ;;
    --query)     QUERY="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --invert)    INVERT=1; shift ;;
    --help|-h)   usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- resolve KB id from terraform if not supplied ---
if [[ -z "$KB_ID" ]]; then
  KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id 2>/dev/null || true)
  if [[ -z "$KB_ID" ]]; then
    echo "ERROR: --kb-id not provided and 'terraform -chdir=infra/envs/prod output -raw kb_id' failed" >&2
    echo "Run from the repo root, or pass --kb-id explicitly." >&2
    exit 2
  fi
fi

echo "verifying KB ${KB_ID} in ${REGION}"
echo "query: ${QUERY}"
echo "score threshold: ${THRESHOLD}"
echo "polling every ${SLEEP_SECONDS}s for up to $((MAX_ATTEMPTS * SLEEP_SECONDS))s"
if [[ "${INVERT}" == "1" ]]; then
  echo "mode: INVERT (cleanup verification - success when KB is unreachable)"
fi

# --- poll loop ---
for i in $(seq 1 "${MAX_ATTEMPTS}"); do
  RESP=$(aws bedrock-agent-runtime retrieve \
    --region "${REGION}" \
    --knowledge-base-id "${KB_ID}" \
    --retrieval-query "${QUERY}" \
    --retrieval-configuration '{"vectorSearchConfiguration":{"numberOfResults":3}}' \
    --output json 2>&1) || true

  if [[ "${INVERT}" == "1" ]]; then
    # cleanup-mode: any AccessDenied / NotFound means KB is gone (success)
    if echo "${RESP}" | grep -qiE 'AccessDenied|ResourceNotFound'; then
      echo "OK (cleanup): KB no longer accessible"
      echo "${RESP}" | head -3
      exit 0
    fi
    echo "attempt ${i}/${MAX_ATTEMPTS}: KB still responding; expected to be gone"
  else
    HITS=$(echo "${RESP}" | jq -r '.retrievalResults | length' 2>/dev/null || echo 0)
    TOP=$(echo "${RESP}" | jq -r '.retrievalResults[0].score // 0' 2>/dev/null || echo 0)
    echo "attempt ${i}/${MAX_ATTEMPTS}: hits=${HITS} top_score=${TOP}"

    if [[ "${HITS}" -gt 0 ]] && awk "BEGIN{exit !(${TOP} >= ${THRESHOLD})}"; then
      echo "OK: ${HITS} results returned, top score ${TOP} >= threshold ${THRESHOLD}"
      exit 0
    fi

    # Surface AccessDenied immediately (model access not enabled, or IAM mismatch)
    if echo "${RESP}" | grep -qi 'AccessDeniedException'; then
      echo "ERROR: AccessDeniedException - check Bedrock model access for amazon.titan-embed-text-v2:0 in ${REGION}, and the KB service role inline policy" >&2
      echo "${RESP}" | head -5 >&2
      exit 1
    fi
  fi

  sleep "${SLEEP_SECONDS}"
done

if [[ "${INVERT}" == "1" ]]; then
  echo "FAIL (cleanup): KB still responding after $((MAX_ATTEMPTS * SLEEP_SECONDS))s - destroy did not complete" >&2
else
  echo "FAIL: no qualifying results after $((MAX_ATTEMPTS * SLEEP_SECONDS))s" >&2
  echo "Possible causes: ingestion job not run, post-sync propagation lag exceeded 5min, model access not enabled, IAM misconfigured." >&2
fi
exit 1
```

After writing the file, mark it executable: `chmod +x bin/verify-kb.sh`.

**Constraints (CLAUDE.md / D-15):**
- No emojis ANYWHERE in the script (comments, echo, error messages).
- Plain English error messages with no decoration.
- `set -euo pipefail` for fail-fast.
- Polling loop uses `awk` for floating-point comparison (bash `[[ ]]` doesn't do floats).
- `--invert` mode looks for `AccessDenied|ResourceNotFound` in the raw response (Phase 4 reuse per D-16).

**Why the small additions to RESEARCH.md skeleton are safe:**
- The `usage()` function and `--help` flag don't change behavior; they make the script self-documenting (PATTERNS.md called this out as a planner choice).
- Surfacing `AccessDeniedException` as a fast-fail (instead of waiting through the full poll loop) directly serves Pitfall A — model access not enabled is the #1 reason for early failures.
- The RESEARCH.md skeleton's `RC=$? || true` chain was a typo (`|| RC=$?` is unusual); replaced with the simpler `|| true` since RC is never inspected.
  </action>
  <acceptance_criteria>
    - File exists: `test -f bin/verify-kb.sh`.
    - File is executable: `test -x bin/verify-kb.sh`.
    - Shebang is `#!/usr/bin/env bash`: `head -1 bin/verify-kb.sh | grep -q '^#!/usr/bin/env bash$'`.
    - Uses `set -euo pipefail`: `grep -q '^set -euo pipefail$' bin/verify-kb.sh`.
    - Calls the runtime API (NOT the build-time API — Pitfall J): `grep -q 'aws bedrock-agent-runtime retrieve' bin/verify-kb.sh` AND `! grep -q 'aws bedrock-agent-runtime start-ingestion-job' bin/verify-kb.sh`.
    - Uses the verified jq path (`retrievalResults[0].score`): `grep -q "jq -r '.retrievalResults | length'" bin/verify-kb.sh` AND `grep -q "jq -r '.retrievalResults\[0\]\.score" bin/verify-kb.sh`.
    - Polls 15s × 20 = 5min (D-15): `grep -q 'MAX_ATTEMPTS=20' bin/verify-kb.sh` AND `grep -q 'SLEEP_SECONDS=15' bin/verify-kb.sh`.
    - Falls back to terraform output for KB id: `grep -q 'terraform -chdir=infra/envs/prod output -raw kb_id' bin/verify-kb.sh`.
    - Defaults region to `ap-northeast-1` (D-14): `grep -q 'REGION="${HERA_REGION:-ap-northeast-1}"' bin/verify-kb.sh`.
    - Default query is the KB-04 verification target: `grep -q "QUERY='{\"text\":\"iPhone 13 Pro Max stock\"}'" bin/verify-kb.sh`.
    - Default threshold is 0.4 (CONTEXT.md discretion area): `grep -q 'THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"' bin/verify-kb.sh`.
    - `--invert` flag for D-16 Phase 4 reuse: `grep -q -- '--invert' bin/verify-kb.sh`.
    - `--help` flag and usage block: `grep -q -- '--help' bin/verify-kb.sh` AND `grep -q 'usage()' bin/verify-kb.sh`.
    - Surfaces `AccessDeniedException` as fast-fail (Pitfall A): `grep -q 'AccessDeniedException' bin/verify-kb.sh`.
    - No emojis: `python3 -c "import sys, re, pathlib; sys.exit(1 if re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', pathlib.Path('bin/verify-kb.sh').read_text(encoding='utf-8')) else 0)"` exits 0.
    - Help text renders without error: `bin/verify-kb.sh --help` exits 0 and includes the substring `Usage:`.
    - Argument-error path works: `bin/verify-kb.sh --bogus 2>&1 | grep -q 'unknown arg'` AND `bin/verify-kb.sh --bogus; test $? -eq 2`.
    - shellcheck has no errors (warnings OK): `command -v shellcheck && shellcheck -S error bin/verify-kb.sh; test $? -eq 0` (skip silently if shellcheck not installed — this is a workshop dev-machine check).
  </acceptance_criteria>
  <verify>
    <automated>test -x bin/verify-kb.sh && head -1 bin/verify-kb.sh | grep -q '^#!/usr/bin/env bash$' && grep -q 'aws bedrock-agent-runtime retrieve' bin/verify-kb.sh && grep -q 'MAX_ATTEMPTS=20' bin/verify-kb.sh && grep -q 'SLEEP_SECONDS=15' bin/verify-kb.sh && grep -q -- '--invert' bin/verify-kb.sh && grep -q -- '--help' bin/verify-kb.sh && grep -q 'AccessDeniedException' bin/verify-kb.sh && bin/verify-kb.sh --help | grep -q '^Usage:'</automated>
  </verify>
  <done>
    bin/verify-kb.sh exists, is executable, follows the verbatim D-15 skeleton from RESEARCH.md with the four documented additions, has no emojis, polls 15s/5min, defaults to the KB-04 query, supports --invert for Phase 4 reuse (D-16), and renders --help cleanly.
  </done>
</task>

<task type="auto">
  <name>Task 2: Fill in the seven RUNBOOK.md TODO(plan-03) markers with actual commands</name>
  <files>RUNBOOK.md</files>
  <read_first>
    - C:/Users/trant/projects/hera/RUNBOOK.md (current state from Plan 01 — eight sections, seven TODO markers)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Manual ingestion sync" (lines 682-723) — VERBATIM bash for start-ingestion-job + get-ingestion-job poll loop
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pitfall A" (lines 582-601) — Bedrock model access enable command and console step
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pitfall D" (lines 628-638) — Recovery from half-applied
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Pitfall J" (lines 666-676) — distinguish bedrock-agent vs bedrock-agent-runtime CLI surfaces
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Environment Availability" (lines 938-951) — the four blocking deps for Pre-flight
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md D-05, D-06 (manual sync workflow), D-12 (recovery path)
    - C:/Users/trant/projects/hera/bin/verify-kb.sh (Task 1 output) — flag list and exit codes for the Verify and Cleanup sections
  </read_first>
  <action>
Edit `RUNBOOK.md` in place. Replace each `TODO(plan-03):` marker with the corresponding content below. The eight section headings already exist from Plan 01 — do NOT re-create them. The "Next steps (deferred)" section is already complete from Plan 01 — do NOT modify it.

**Section "## Pre-flight" — replace the TODO with:**

```markdown
This runbook assumes you have the four blocking dependencies installed and AWS credentials configured for the target account. Run these checks before the first deploy:

```bash
# 1. AWS CLI v2 and credentials
aws --version                # expect aws-cli/2.x
aws sts get-caller-identity  # confirms credentials and prints the account ID you will deploy into

# 2. Terraform >= 1.9
terraform -version           # expect 1.9 or newer

# 3. jq (used by bin/verify-kb.sh)
jq --version                 # any 1.6+ release
```

You also need to enable Amazon Titan Text Embeddings V2 model access in the deploy region. AWS gates Bedrock models per-account-per-region; this is separate from IAM. The default deploy region is `ap-northeast-1`.

```bash
# Confirm Titan v2 is available in ap-northeast-1 (after enabling in the console)
aws bedrock list-foundation-models --region ap-northeast-1 \
  --query 'modelSummaries[?modelId==`amazon.titan-embed-text-v2:0`].modelLifecycle.status' \
  --output text
# Expect: ACTIVE
# Empty output means model access is not enabled.
```

To enable: AWS Console -> Bedrock -> Model access -> Modify -> check "Amazon Titan Text Embeddings V2" -> Save changes -> wait ~1 minute. Repeat once per region you deploy into.

If `terraform apply` succeeds but `aws bedrock-agent start-ingestion-job` fails with `AccessDeniedException` mentioning the model ARN, re-check this step. IAM may be correct but model access still gated.
```

**Section "## First deploy" — replace the TODO with:**

```markdown
Provision the Bedrock KB, source S3 bucket, S3 Vectors bucket and index, KB data source, and KB service IAM role:

```bash
cd infra/envs/prod
terraform init
terraform apply
# Review the plan (about 9 resources). Type 'yes' to apply.
cd ../../..
```

Expected outcome:
- `terraform apply` completes in ~30-60 seconds.
- Outputs: `kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`.
- The S3 source bucket and S3 Vectors bucket are now empty; you upload catalog content next.

Region override (use `us-east-1` for dev per DEP-06):

```bash
cd infra/envs/prod
terraform apply -var=region=us-east-1
```

Note: changing the region after a successful apply requires `terraform destroy` first (provider-level state is per-region). For day-to-day workshop use, stay on the default `ap-northeast-1`.
```

**Section "## First sync" — replace the TODO with:**

```markdown
The catalog content is uploaded to S3 manually, then a Bedrock ingestion job is triggered explicitly. There is no `null_resource` automation in Terraform - the AWS CLI is the teaching surface (D-05, D-07).

```bash
# 1. Resolve outputs from terraform state
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
SRC_BUCKET=$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)
REGION=ap-northeast-1

# 2. Upload all catalog markdown to the catalog/ prefix
aws s3 cp catalog/ "s3://${SRC_BUCKET}/catalog/" --recursive --exclude "*" --include "*.md"

# 3. Trigger the ingestion job (build-time API: aws bedrock-agent, NOT bedrock-agent-runtime - see Pitfall J below)
JOB_ID=$(aws bedrock-agent start-ingestion-job \
  --region "${REGION}" \
  --knowledge-base-id "${KB_ID}" \
  --data-source-id "${DS_ID}" \
  --description "first sync" \
  --query 'ingestionJob.ingestionJobId' \
  --output text)
echo "started ingestion job: ${JOB_ID}"

# 4. Poll until COMPLETE (or FAILED / STOPPED)
while true; do
  STATUS=$(aws bedrock-agent get-ingestion-job \
    --region "${REGION}" \
    --knowledge-base-id "${KB_ID}" \
    --data-source-id "${DS_ID}" \
    --ingestion-job-id "${JOB_ID}" \
    --query 'ingestionJob.status' \
    --output text)
  echo "status: ${STATUS}"
  case "${STATUS}" in
    COMPLETE|FAILED|STOPPED) break ;;
  esac
  sleep 5
done
```

After `STATUS=COMPLETE`, vectors are written but may take 2-3 more minutes to be queryable. This is documented AWS behavior, not a bug. Run `bin/verify-kb.sh` next - it polls for up to 5 minutes to cover this propagation lag.

**Pitfall J - two CLI surfaces:** `aws bedrock-agent` is the build-time control plane (KBs, agents, ingestion jobs). `aws bedrock-agent-runtime` is the runtime data plane (Retrieve, RetrieveAndGenerate). They are NOT interchangeable. Sync uses `bedrock-agent`; verify uses `bedrock-agent-runtime`.
```

**Section "## Verify" — replace the TODO with:**

```markdown
Confirm the KB returns the right document for the verification query:

```bash
bin/verify-kb.sh
```

Expected output (final line on success):

```
OK: 3 results returned, top score 0.78 >= threshold 0.4
```

The script polls every 15s for up to 5 minutes (covers post-sync propagation). It exits 0 on success.

If it fails with `AccessDeniedException`: model access for Titan v2 is not enabled in the deploy region. Re-read the Pre-flight section.

If it times out with `no qualifying results after 300s`: wait another 2 minutes and re-run. Occasional propagation can exceed 5 minutes for fresh KBs. If it still times out, check the ingestion job actually completed (`aws bedrock-agent list-ingestion-jobs --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" --region "${REGION}"`).

If it returns empty results despite a completed sync: confirm the `inclusion_prefixes = ["catalog/"]` setting in the data source matches where you uploaded the markdown. The `aws s3 cp` command above writes to `s3://<bucket>/catalog/`; the data source only reads under that prefix.

Override the query for ad-hoc checks:

```bash
bin/verify-kb.sh --query '{"text":"What MacBook configurations are in stock?"}'
bin/verify-kb.sh --query '{"text":"What is your return policy?"}'
```
```

**Section "## Re-index after editing a product file" — replace the TODO with:**

```markdown
Bedrock KB ingestion is incremental. After editing a `catalog/*.md` file, re-upload and re-trigger the same ingestion job command - Bedrock processes only the documents that were added, modified, or deleted since the last sync.

```bash
# Edit the file
$EDITOR catalog/iphone-13-pro-max.md

# Re-upload (overwrites the S3 object)
SRC_BUCKET=$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)
aws s3 cp catalog/iphone-13-pro-max.md "s3://${SRC_BUCKET}/catalog/iphone-13-pro-max.md"

# Re-run the ingestion job (same command as First sync)
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
aws bedrock-agent start-ingestion-job \
  --region ap-northeast-1 \
  --knowledge-base-id "${KB_ID}" \
  --data-source-id "${DS_ID}" \
  --description "re-index after editing iphone-13-pro-max.md"

# Wait for status COMPLETE, then run verify (covers propagation)
bin/verify-kb.sh
```

The cost of a single-file re-embed at workshop scale is well under one cent.
```

**Section "## Recovery from a half-failed apply" — replace the TODO with:**

```markdown
Resource names are fixed (per D-12 - no random suffix), so retrying after a partial failure can hit `ResourceAlreadyExistsException`. The recovery path is destroy + re-apply, not `terraform import`.

```bash
cd infra/envs/prod
terraform destroy   # type 'yes' to confirm
terraform apply
cd ../../..
```

Cost of a full rebuild at workshop scale is under one cent in S3 / S3 Vectors / Bedrock embedding charges plus a few minutes of waiting. After a successful re-apply, repeat the First sync section.

If `terraform destroy` itself fails because the source bucket has objects, that should not happen (the module sets `force_destroy = true` on both buckets). If it does, wipe the bucket manually and retry:

```bash
aws s3 rm "s3://$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)/" --recursive
cd infra/envs/prod && terraform destroy && cd ../../..
```
```

**Section "## Cleanup" — replace the TODO with:**

```markdown
Tear down all Phase 1 AWS resources and confirm the KB is no longer reachable:

```bash
cd infra/envs/prod
terraform destroy   # type 'yes' to confirm
cd ../../..

# Confirm the KB no longer responds to retrieve calls (Phase 4 cleanup verification, D-16).
# In invert mode, success means AccessDenied / ResourceNotFound is returned.
bin/verify-kb.sh --invert
```

Expected `--invert` final line:

```
OK (cleanup): KB no longer accessible
```

After this, no Bedrock KB, no S3 source bucket, no S3 Vectors bucket / index, and no IAM role exist for this stack. Cost Explorer should show $0 for the affected services within 24 hours. Phase 4 builds a more comprehensive cleanup-verify script that checks across all phases.
```

**Verify NO `TODO(plan-03):` markers remain after editing.** This is the single most important post-condition - if any remain, Plan 03 is incomplete.

**Constraints:**
- Do not modify the Plan 01 "Next steps (deferred)" section.
- Do not change any of the eight section headings.
- No emojis.
- Keep total file under 300 lines (loosened from PATTERNS.md's 200-line target since the filled-in commands add ~100 lines of code blocks).
- English only.
  </action>
  <acceptance_criteria>
    - File still exists: `test -f RUNBOOK.md`.
    - All eight section headings still exist (unchanged from Plan 01): `grep -c '^## ' RUNBOOK.md` returns exactly `8`.
    - ZERO `TODO(plan-03):` markers remain: `grep -c '^TODO(plan-03):' RUNBOOK.md` returns `0`. (This is the gate - if any marker remains, the plan is incomplete.)
    - Pre-flight section documents Titan v2 model access (Pitfall A): `grep -q 'amazon\.titan-embed-text-v2:0' RUNBOOK.md` AND `grep -qi 'model access' RUNBOOK.md`.
    - Pre-flight enumerates all four blocking deps: `grep -q 'aws --version' RUNBOOK.md` AND `grep -q 'terraform -version' RUNBOOK.md` AND `grep -q 'jq --version' RUNBOOK.md` AND `grep -q 'aws sts get-caller-identity' RUNBOOK.md`.
    - First deploy section uses the correct working directory: `grep -q 'cd infra/envs/prod' RUNBOOK.md` AND `grep -q 'terraform init' RUNBOOK.md` AND `grep -q 'terraform apply' RUNBOOK.md`.
    - First deploy documents the region override (DEP-06): `grep -q 'terraform apply -var=region=us-east-1' RUNBOOK.md`.
    - First sync uses build-time CLI surface (Pitfall J): `grep -q 'aws bedrock-agent start-ingestion-job' RUNBOOK.md` AND `grep -q 'aws bedrock-agent get-ingestion-job' RUNBOOK.md`.
    - First sync uploads catalog/*.md to s3://.../catalog/ (matches the inclusion_prefixes from Plan 02): `grep -q 's3 cp catalog/' RUNBOOK.md` AND `grep -q 'catalog/' RUNBOOK.md`.
    - First sync explicitly distinguishes the two CLI surfaces (Pitfall J): `grep -q 'Pitfall J' RUNBOOK.md` AND `grep -qi 'bedrock-agent-runtime' RUNBOOK.md`.
    - Verify section invokes the script: `grep -q 'bin/verify-kb.sh' RUNBOOK.md`.
    - Re-index section uses incremental sync: `grep -qi 'incremental' RUNBOOK.md` AND `grep -qi 're-upload' RUNBOOK.md`.
    - Recovery section uses destroy + re-apply (D-12): `grep -q 'terraform destroy' RUNBOOK.md` AND `grep -qi 'recovery' RUNBOOK.md`.
    - Cleanup section uses --invert (D-16): `grep -q 'bin/verify-kb.sh --invert' RUNBOOK.md`.
    - "Next steps (deferred)" section from Plan 01 is unchanged (still mentions remote backend, Phase 2 consumer role): `grep -q 'remote.*backend\|S3.*DynamoDB' RUNBOOK.md` AND `grep -q 'Phase 2\|consumer.*role' RUNBOOK.md`.
    - No emojis: `python3 -c "import sys, re, pathlib; sys.exit(1 if re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', pathlib.Path('RUNBOOK.md').read_text(encoding='utf-8')) else 0)"` exits 0.
    - Total line count under 300: `wc -l RUNBOOK.md | awk '{print $1}'` returns a value <= 300.
  </acceptance_criteria>
  <verify>
    <automated>test -f RUNBOOK.md && [ "$(grep -c '^## ' RUNBOOK.md)" = "8" ] && [ "$(grep -c '^TODO(plan-03):' RUNBOOK.md)" = "0" ] && grep -q 'amazon\.titan-embed-text-v2:0' RUNBOOK.md && grep -q 'aws bedrock-agent start-ingestion-job' RUNBOOK.md && grep -q 'bin/verify-kb.sh' RUNBOOK.md && grep -q 'bin/verify-kb.sh --invert' RUNBOOK.md && grep -q 'terraform destroy' RUNBOOK.md</automated>
  </verify>
  <done>
    All seven Plan-01 TODO(plan-03) markers have been replaced with concrete commands. Pre-flight covers the four deps + Titan v2 model access (Pitfall A). First deploy uses `cd infra/envs/prod && terraform init && terraform apply`. First sync uses the build-time `bedrock-agent start-ingestion-job` API and explicitly distinguishes from runtime (Pitfall J). Verify runs `bin/verify-kb.sh`. Re-index reuses the same sync command. Recovery uses destroy + re-apply (D-12). Cleanup uses `--invert` (D-16). The Plan 01 "Next steps (deferred)" section is preserved unchanged.
  </done>
</task>

<task type="checkpoint:human-action" gate="blocking">
  <name>Task 3: User confirms AWS account is ready and Bedrock Titan v2 model access is enabled in ap-northeast-1</name>
  <what-built>Plan 02 has produced a Terraform module that, on `terraform apply`, will create a Bedrock Knowledge Base, two S3 buckets, an S3 Vectors index, and a KB service IAM role in the user's AWS account. Plan 03 Tasks 1-2 have produced `bin/verify-kb.sh` and a complete RUNBOOK.md.</what-built>
  <how-to-verify>
This checkpoint exists because Tasks 4-6 below will spend real money in the user's AWS account (S3 storage, S3 Vectors storage, Bedrock embedding API calls). At workshop scale this is < $0.05 total for one apply + sync + verify cycle, but it requires:

1. **Active AWS credentials** for the account you want to deploy into.

   ```bash
   aws sts get-caller-identity
   ```

   This must print a JSON object containing `Account`, `Arn`, `UserId`. If it fails with `Unable to locate credentials`, configure your AWS CLI before proceeding (e.g. `aws configure`, `aws sso login`, or set `AWS_PROFILE`).

2. **Bedrock Titan Text Embeddings V2 model access enabled in `ap-northeast-1`** (Pitfall A from RESEARCH.md - this is the #1 reason Phase 1 ingestion jobs fail).

   Check with the command from RUNBOOK.md Pre-flight:

   ```bash
   aws bedrock list-foundation-models --region ap-northeast-1 \
     --query 'modelSummaries[?modelId==`amazon.titan-embed-text-v2:0`].modelLifecycle.status' \
     --output text
   ```

   Expected output: `ACTIVE` (a single line).
   Empty output means model access is not enabled.

   If empty: open AWS Console -> region selector -> Asia Pacific (Tokyo) ap-northeast-1 -> Bedrock -> Model access -> Modify -> check "Amazon Titan Text Embeddings V2" -> Save changes -> wait ~1 minute -> re-run the check.

3. **You accept the cost** of one `terraform apply` + one `start-ingestion-job` + one `verify-kb.sh` invocation. Estimated: under $0.05. The `terraform destroy` command in RUNBOOK Cleanup section will tear it back down once verification passes; ongoing cost after destroy is $0.

4. **You are working in the right AWS account.** `aws sts get-caller-identity` shows the account ID. Confirm this is the account you intended (e.g. your personal sandbox, not a production account).

When all four conditions are true, type "approved" to proceed to Task 4. To abort and stop here (e.g. you want to deploy later), type "skip live". The plan will then complete with verify-kb.sh and RUNBOOK in place but will leave KB-04 unverified for now (which is acceptable for a code-only milestone but DOES NOT close the Phase 1 success criterion #2).
  </how-to-verify>
  <resume-signal>Type "approved" to proceed with live AWS apply + sync + verify. Type "skip live" to stop here with code-only completion (KB-04 unverified). Type "abort" to roll back Plan 03 entirely.</resume-signal>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4: Run terraform apply in infra/envs/prod (live AWS deploy)</name>
  <what-built>This task runs `terraform apply` against the user's AWS account in `ap-northeast-1`. Creates ~9 resources: source S3 bucket + public-access-block, S3 Vectors bucket + index, KB service IAM role + inline policy, Bedrock KB, Bedrock data source.</what-built>
  <how-to-verify>
Run from the repo root:

```bash
cd infra/envs/prod
terraform apply
# Review the plan output. Expect ~9 resources to be created.
# Type 'yes' to confirm.
cd ../../..
```

After `terraform apply` completes successfully (~30-60 seconds), confirm the four outputs are populated:

```bash
terraform -chdir=infra/envs/prod output kb_id              # expect a string like "ABCD1234EFGH"
terraform -chdir=infra/envs/prod output kb_arn             # expect "arn:aws:bedrock:ap-northeast-1:<account>:knowledge-base/<id>"
terraform -chdir=infra/envs/prod output source_bucket_name # expect "hera-kb-source-prod"
terraform -chdir=infra/envs/prod output data_source_id     # expect a UUID
```

Confirm in AWS console:
1. **S3** -> bucket list shows `hera-kb-source-prod` and a vector bucket entry for `hera-kb-vectors-prod`.
2. **Bedrock** -> Knowledge bases -> `hera-kb-prod` exists, status `Active`, embedding model `Titan Text Embeddings V2`, storage `S3 Vectors`.
3. **IAM** -> Roles -> `hera-kb-service-role` exists with one inline policy `hera-kb-inline`.

If `terraform apply` fails:
- `AccessDeniedException` on the Bedrock InvokeModel statement during validation: model access not enabled - go back to Task 3.
- `ResourceAlreadyExistsException`: leftover resources from a previous attempt. Run `terraform destroy` first, then retry (RUNBOOK Recovery section).
- Provider error on argument names (e.g. `Unsupported argument: name`): Plan 02 Task 2 used the wrong argument name. Re-read RESEARCH.md Pattern 4 and fix.

Type "verified" once `terraform apply` exits 0 and the three console checks pass. Type "failed" with the error message if anything went wrong.
  </how-to-verify>
  <resume-signal>Type "verified" to proceed to Task 5 (catalog upload + ingestion job). Type "failed: <error>" to halt for diagnosis.</resume-signal>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 5: Upload catalog/*.md to S3, trigger the ingestion job, wait for COMPLETE</name>
  <what-built>This task uploads the four `catalog/*.md` files from Plan 01 to the S3 source bucket created by Task 4, then triggers and polls the Bedrock ingestion job. After this, the KB has embedded vectors stored in S3 Vectors and is queryable (subject to the documented 2-3 minute propagation lag - Pitfall C).</what-built>
  <how-to-verify>
Run the First sync sequence from RUNBOOK.md (replicated here for convenience):

```bash
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
SRC_BUCKET=$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)
REGION=ap-northeast-1

# 1. Upload all four markdown files
aws s3 cp catalog/ "s3://${SRC_BUCKET}/catalog/" --recursive --exclude "*" --include "*.md"

# Verify upload (expect 4 lines, one per file)
aws s3 ls "s3://${SRC_BUCKET}/catalog/"

# 2. Start ingestion job
JOB_ID=$(aws bedrock-agent start-ingestion-job \
  --region "${REGION}" \
  --knowledge-base-id "${KB_ID}" \
  --data-source-id "${DS_ID}" \
  --description "Plan 03 first sync" \
  --query 'ingestionJob.ingestionJobId' \
  --output text)
echo "started ingestion job: ${JOB_ID}"

# 3. Poll until COMPLETE
while true; do
  STATUS=$(aws bedrock-agent get-ingestion-job \
    --region "${REGION}" \
    --knowledge-base-id "${KB_ID}" \
    --data-source-id "${DS_ID}" \
    --ingestion-job-id "${JOB_ID}" \
    --query 'ingestionJob.status' \
    --output text)
  echo "status: ${STATUS}"
  case "${STATUS}" in
    COMPLETE|FAILED|STOPPED) break ;;
  esac
  sleep 5
done
```

Expected outcome:
- `aws s3 ls` lists 4 files (apple-watch-s11.md, iphone-13-pro-max.md, macbook-pro-m4.md, store-policy.md).
- Ingestion job status transitions IN_PROGRESS -> COMPLETE in roughly 30-90 seconds for 4 small markdown files.
- Final printed status is `COMPLETE`.

If status is `FAILED`:
- Run `aws bedrock-agent get-ingestion-job ... --query 'ingestionJob.failureReasons'` to see the failure reason.
- Most common cause is model access not enabled (Pitfall A) - go back to Task 3.
- Second most common is IAM mismatch - re-read Plan 02 Task 1 acceptance criteria for IAM.

Type "verified" once status is `COMPLETE` and all 4 files are uploaded. Type "failed: <reason>" if not.
  </how-to-verify>
  <resume-signal>Type "verified" to proceed to Task 6 (verify-kb.sh execution). Type "failed: <reason>" to halt for diagnosis.</resume-signal>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 6: Run bin/verify-kb.sh — final KB-04 verification</name>
  <what-built>This task runs `bin/verify-kb.sh` against the deployed KB. The script polls the Retrieve API every 15s for up to 5 minutes (covers the documented post-sync propagation lag - Pitfall C), looking for results above the 0.4 score threshold for the query "iPhone 13 Pro Max stock". Success closes Phase 1 success criterion #2 and KB-04.</what-built>
  <how-to-verify>
From the repo root:

```bash
bin/verify-kb.sh
```

Expected output ends with a line like:

```
OK: 3 results returned, top score 0.78 >= threshold 0.4
```

The script will print one line per polling attempt (`attempt N/20: hits=H top_score=S`). Typical timeline:
- First 1-3 attempts (15-45s): may show `hits=0` while propagation completes.
- Attempts 4-8: `hits=3` with `top_score` between 0.5-0.9 for the iPhone 13 Pro Max content.
- Script exits 0 the moment the threshold is met.

If the script exits with `FAIL: no qualifying results after 300s`:
- The ingestion job COMPLETED but propagation took longer than 5 minutes (rare for small catalogs but possible). Wait 2 minutes and re-run. RUNBOOK Verify section documents this case.
- If still failing after 10 minutes total, check `aws bedrock-agent list-ingestion-jobs --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" --region ap-northeast-1` - confirm the most recent job is `COMPLETE`, not `FAILED`.

If the script exits with `ERROR: AccessDeniedException`:
- IAM is misconfigured OR Titan v2 model access is not enabled. Re-read Task 3 / Pitfall A.

Once `bin/verify-kb.sh` exits 0, also smoke-test two ad-hoc queries to confirm broader catalog coverage:

```bash
bin/verify-kb.sh --query '{"text":"What MacBook configurations are in stock?"}'
bin/verify-kb.sh --query '{"text":"What is your return policy?"}'
```

Both should also return `OK:` with hits >= 1. The first targets `catalog/macbook-pro-m4.md`, the second targets `catalog/store-policy.md`.

Type "verified" if all three runs print `OK:` lines and exit 0. Type "failed: <message>" if any of them fails.
  </how-to-verify>
  <resume-signal>Type "verified" to declare Phase 1 success criterion #2 + KB-04 closed. Type "failed: <message>" to halt for diagnosis. The phase is NOT complete until this task verifies green.</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Operator's machine -> AWS API | The user's AWS credentials are used by terraform apply, aws s3 cp, aws bedrock-agent start-ingestion-job, and aws bedrock-agent-runtime retrieve. Standard sigv4 SDK auth - no special controls in this plan. |
| catalog/*.md (filesystem) -> S3 source bucket | Manual `aws s3 cp` uploads the four catalog files. Bucket is private (Plan 02 mitigation T-02-01). |
| bin/verify-kb.sh shell args -> AWS CLI invocation | The script accepts --kb-id, --query, --region, --threshold flags. Flags are passed to AWS CLI as separate arguments (not concatenated into a shell string), so injection risk is bounded by the AWS CLI's own argument parsing. |
| RUNBOOK.md prose -> learner's clipboard | Workshop Phase 5 will turn RUNBOOK content into copy-paste snippets. Snippets must contain no shell injection sources (no `$(curl ...)`, no piped untrusted input). |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation |
|-----------|----------|-----------|----------|-------------|------------|
| T-03-01 | Tampering | bin/verify-kb.sh shell argument injection | medium | mitigate | All variable expansions are double-quoted (`"${KB_ID}"`, `"${REGION}"`, `"${QUERY}"`). The AWS CLI receives each as a separate argument, so a malicious `--query 'foo; rm -rf /'` is delivered as a single string argument to the CLI, not interpreted by bash. Plan 03 Task 1 acceptance criteria implicitly verify by running `--bogus` and asserting exit code 2 (clean argument-error path). Additionally: `bin/verify-kb.sh --query '$(echo INJECTED)'; ! echo "$RESP" | grep -q INJECTED` (proof of no command substitution from --query payload). |
| T-03-02 | Information Disclosure | bin/verify-kb.sh prints the full AWS error response on failure | low | accept | On AccessDenied / NotFound / generic error, the script prints `head -3` or `head -5` of the response. This may include ARNs and account IDs - already implicitly known to the operator running the script (it is their own account). Not exposed to anyone else. |
| T-03-03 | Denial of Service | Runaway polling loop in bin/verify-kb.sh | low | mitigate | Loop is hard-bounded to MAX_ATTEMPTS=20 iterations of SLEEP_SECONDS=15 = 300s. After that, exit 1 with a clear message. No infinite-loop path. Acceptance criterion in Task 1 grep-asserts both constants. |
| T-03-04 | Elevation of Privilege | Operator running terraform apply on the wrong AWS account | medium | mitigate | Task 3 (human-action checkpoint) requires the user to confirm `aws sts get-caller-identity` shows the intended account before proceeding. This is the standard AWS workshop pattern - cannot be fully automated. |
| T-03-05 | Information Disclosure | catalog/*.md uploaded to S3 contains the only sensitive prose (synthetic stock numbers and pricing) | low | accept | Content is synthetic Apple Store demo data; no PII; no real business secrets. Bucket has full public-access-block from Plan 02 (T-02-01). Not exposed externally. |
| T-03-06 | Denial of Service | start-ingestion-job triggered repeatedly for the same data | low | accept | Bedrock incremental sync is idempotent for unchanged docs; cost of redundant runs at workshop scale is negligible. RUNBOOK does not warn against this because it is harmless. |
| T-03-07 | Tampering | RUNBOOK.md commands copied into a learner's terminal could exfiltrate data if injected | medium | mitigate | All RUNBOOK shell snippets use either literal commands or `$(terraform -chdir=infra/envs/prod output -raw NAME)` substitution where NAME is one of the four documented module outputs (kb_id, kb_arn, source_bucket_name, data_source_id) - none of these contain shell metacharacters. Acceptance criteria explicitly check for the safe forms. |
| T-03-08 | Repudiation | aws bedrock-agent start-ingestion-job has no operator audit beyond CloudTrail | low | accept | CloudTrail captures the call (default in every AWS account). No additional audit needed for workshop scale. |

**No high-severity threats remain unmitigated.** T-03-04 is the operator-account-confirmation risk and is mitigated by the explicit Task 3 human-action checkpoint - the only legitimate `human-action` checkpoint in this phase, used because confirming "this is the right AWS account and you accept the cost" cannot be automated.
</threat_model>

<verification>

After all six tasks complete, the following checks must pass (Tasks 1, 2 verifiable on any machine; Tasks 4-6 verifiable only on a machine with AWS credentials, after the human-action checkpoint at Task 3):

```bash
# 1. bin/verify-kb.sh exists, is executable, follows the contract
test -x bin/verify-kb.sh
head -1 bin/verify-kb.sh | grep -q '^#!/usr/bin/env bash$'
grep -q 'aws bedrock-agent-runtime retrieve' bin/verify-kb.sh
grep -q 'MAX_ATTEMPTS=20' bin/verify-kb.sh
bin/verify-kb.sh --help | grep -q '^Usage:'

# 2. RUNBOOK.md has all eight sections, zero remaining TODO markers
test "$(grep -c '^## ' RUNBOOK.md)" = "8"
test "$(grep -c '^TODO(plan-03):' RUNBOOK.md)" = "0"
grep -q 'amazon\.titan-embed-text-v2:0' RUNBOOK.md          # Pre-flight: Pitfall A
grep -q 'aws bedrock-agent start-ingestion-job' RUNBOOK.md  # First sync: build-time CLI
grep -q 'bin/verify-kb.sh --invert' RUNBOOK.md              # Cleanup: D-16

# 3. Hugo build still works
hugo --quiet --gc

# 4. No emojis in this plan's deliverables
python3 -c "
import sys, re, pathlib
bad = [p for p in [pathlib.Path('bin/verify-kb.sh'), pathlib.Path('RUNBOOK.md')] if re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', p.read_text(encoding='utf-8'))]
sys.exit(0 if not bad else (print(bad) or 1))
"

# 5. After Tasks 4-6 (live AWS), the following must also be true:
# 5a. Terraform state contains the KB resource
terraform -chdir=infra/envs/prod state list | grep -q 'aws_bedrockagent_knowledge_base.this'

# 5b. KB outputs are populated (not empty strings)
test -n "$(terraform -chdir=infra/envs/prod output -raw kb_id)"
test -n "$(terraform -chdir=infra/envs/prod output -raw kb_arn)"
test -n "$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)"
test -n "$(terraform -chdir=infra/envs/prod output -raw data_source_id)"

# 5c. All 4 catalog files are in S3
SRC_BUCKET=$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)
test "$(aws s3 ls s3://${SRC_BUCKET}/catalog/ | wc -l)" -eq 4

# 5d. The most recent ingestion job is COMPLETE
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
aws bedrock-agent list-ingestion-jobs --region ap-northeast-1 --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" --max-results 1 --query 'ingestionJobSummaries[0].status' --output text | grep -q '^COMPLETE$'

# 5e. bin/verify-kb.sh passes (KB-04)
bin/verify-kb.sh
```

All 5a-5e checks gate on Task 3's human-action approval. If the user typed "skip live", checks 5a-5e are skipped and the plan completes in code-only mode (KB-04 marked partial in the SUMMARY).

</verification>

<success_criteria>

Plan 03 succeeds when:

1. **bin/verify-kb.sh ships:** Script exists at `bin/verify-kb.sh`, is executable, follows the verbatim D-15 / RESEARCH.md skeleton with the four documented additions (usage block, fast-fail on AccessDeniedException, region default `ap-northeast-1`, `--help` flag). No emojis; passes shellcheck if installed.
2. **RUNBOOK.md is complete:** Zero `TODO(plan-03):` markers remain. All eight sections (Pre-flight, First deploy, First sync, Verify, Re-index after editing a product file, Recovery from a half-failed apply, Cleanup, Next steps (deferred)) contain concrete commands. Pitfalls A (model access) and J (CLI surface distinction) are explicit. The Plan 01 "Next steps (deferred)" section is unchanged.
3. **KB-04 verified for-real:** `bin/verify-kb.sh` exits 0 against the deployed KB with `hits >= 1` and `top_score >= 0.4` for the query "iPhone 13 Pro Max stock". This closes Phase 1 success criterion #2.
4. **KB-06 verified for-real:** The First sync workflow + Re-index workflow in RUNBOOK both use `aws bedrock-agent start-ingestion-job` and have been exercised at least once on the user's account (Task 5). This closes Phase 1 success criterion #5.
5. **Live AWS state:** Tasks 4-5 leave a working KB, source bucket with 4 markdown files, S3 Vectors bucket with embedded vectors, and a KB service IAM role - all consumable by Phase 2. The four module outputs (`kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`) are populated.
6. **D-15 / D-16 honored:** Verify script supports `--invert` for Phase 4 cleanup reuse. Verified by `bin/verify-kb.sh --help` showing the flag.
7. **Hugo coexistence:** `hugo --quiet --gc` still exits 0 - none of `bin/verify-kb.sh`, `RUNBOOK.md`, or any AWS resource impacts Hugo's build path.

**If the user typed "skip live" at Task 3:** items 1, 2, 6, 7 are met; items 3, 4, 5 are deferred. The SUMMARY records this and recommends running Tasks 4-6 manually before declaring Phase 1 closed.

</success_criteria>

<output>
After completion, create `.planning/phases/01-knowledge-base-foundation/01-03-SUMMARY.md` per the standard summary template. Include:
- Files created/modified (`bin/verify-kb.sh`, `RUNBOOK.md`)
- Whether Tasks 4-6 ran live (or "skipped per user request at Task 3")
- If live: the four module output values (`kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`) - these are NOT secrets but are useful for Phase 2 reference
- If live: the final `bin/verify-kb.sh` output line ("OK: N results returned, top score X >= threshold 0.4")
- Confirmation Hugo build still passes
- Phase 1 closure status: `success_criteria_met: 5/5` if live ran, `4/5` if skipped (criterion #2 needs live verify)
- Note that Phase 2 (Pipecat Voice Agent local) consumes `module.knowledge_base.kb_id` and `kb_arn` from terraform output, and that the consumer `bedrock:Retrieve` role for Pipecat is built in Phase 2 (D-10 deferred from Phase 1)
</output>
