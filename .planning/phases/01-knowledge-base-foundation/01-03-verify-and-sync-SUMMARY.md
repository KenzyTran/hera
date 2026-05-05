---
phase: 01-knowledge-base-foundation
plan: 03
subsystem: infra
tags: [bedrock, knowledge-base, s3-vectors, ingestion, runbook, verify-script, titan-v2, live-aws]

# Dependency graph
requires:
  - phase: 01-knowledge-base-foundation
    provides: "catalog/*.md source content (Plan 01-01) and the Terraform knowledge_base module + envs/prod root (Plan 01-02)"
provides:
  - "bin/verify-kb.sh — KB-04 verification script (polls bedrock-agent-runtime retrieve every 15s for up to 5 minutes; --invert flag reserved for Phase 4 cleanup per D-16)"
  - "RUNBOOK.md fully populated — all seven TODO(plan-03) markers replaced with concrete aws/terraform commands across Pre-flight, First deploy, First sync, Verify, Re-index, Recovery, Cleanup"
  - "Live AWS state in account 851725411875 / ap-northeast-1: Bedrock KB BKXE19AH89 (kb_arn arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89), data source V9KJOLJTZC, source bucket hera-kb-source-prod, S3 Vectors bucket hera-kb-vectors-prod with index hera-kb-index, KB service role hera-kb-service-role — all four catalog/*.md indexed and queryable"
affects: [01-phase-verification, 02-pipecat-voice-agent, 04-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fail-fast preflight in operator scripts: command -v aws / jq before any work, no silent 2>/dev/null fallbacks (verify-kb.sh fix f78a39a; aligns with AGENTS.md no-defensive-programming directive)"
    - "S3 Vectors metadata configuration: AMAZON_BEDROCK_TEXT and AMAZON_BEDROCK_METADATA marked non-filterable (the 2 KB filterable cap collides with FIXED_SIZE 300-token chunks — both fields are retrieve-only)"
    - "Terraform lifecycle replace_triggered_by from data source to its parent KB — works around AWS provider gap where KB replacement does not propagate to the data source"
    - "Live-run continuation: tasks 3-5 ran interactively under user AWS credentials; deviations were committed under the Plan 01-02 module (root-cause was there, not in 01-03's deliverables) — fix(01-02) labels are correct"

key-files:
  created:
    - "bin/verify-kb.sh"
  modified:
    - "RUNBOOK.md"
    - "infra/modules/knowledge_base/main.tf (deviation fixes 9006d48, 28bbcee — see Deviations section)"

key-decisions:
  - "S3 Vectors metadata_configuration block in aws_s3vectors_index marks AMAZON_BEDROCK_TEXT + AMAZON_BEDROCK_METADATA as non_filterable_metadata_keys. Root cause: S3 Vectors caps filterable metadata at 2048 bytes per record; Bedrock-written chunk text overflows this for FIXED_SIZE 300-token chunks. Discovered live: 2/4 catalog docs failed first ingestion (job SNO941TQVJ) with 'Filterable metadata must have at most 2048 bytes'. Fix lands in plan 01-02 module (commit 9006d48) because that is where the index is defined. RESEARCH.md L16 noted the 2 KB cap but did not surface it into the module shape."
  - "aws_bedrockagent_data_source.catalog has lifecycle.replace_triggered_by = [aws_bedrockagent_knowledge_base.this]. Root cause: AWS provider does not mark the data source for replacement when its parent KB is replaced; UpdateDataSource then 404s with the stale data source id and corrupts terraform state mid-apply. Forces correct lockstep replacement. Commit 28bbcee."
  - "bin/verify-kb.sh enforces aws and jq presence at startup with command -v and exits 2 on miss. The original silent '|| echo 0' jq fallback masked a missing-jq install as 'hits=0 top_score=0' for the full 5-minute poll, then misreported as propagation timeout. Per AGENTS.md ('don't program defensively, identify root cause first'), the bare jq invocation now lets set -euo pipefail surface real errors. Commit f78a39a."

patterns-established:
  - "Pattern: operator scripts assert their dependencies up front (command -v aws + command -v jq) instead of guarding individual calls with silent fallbacks — preserves the diagnostic signal when set -euo pipefail fires"
  - "Pattern: when AWS provider replacement semantics drop a child resource on the floor, document the gap with a lifecycle.replace_triggered_by and a comment naming the corrupted-state failure mode — this is a known-bad provider behavior, not user error"
  - "Pattern: live-run deviations that root-cause to a previous plan are committed under that plan's scope (fix(01-02): ...), not the current one — keeps blame trail honest and lets each plan's verifier see its own gap surface"

requirements-completed: [KB-04, KB-06]

# Metrics
duration: ~50min
completed: 2026-05-05
---

# Phase 1 Plan 3: Verify and Sync Summary

**Shipped `bin/verify-kb.sh`, filled RUNBOOK.md with concrete operational commands, and ran a live `terraform apply` -> `aws s3 cp` -> `start-ingestion-job` -> `verify-kb.sh` cycle in `ap-northeast-1` against the user's AWS account (851725411875) — KB-04 verified end-to-end (top score 0.8598 for "iPhone 13 Pro Max stock"), KB-06 re-index path verified (single-file edit + re-sync round-trip, then reverted to keep KB byte-identical to repo state).**

## Performance

- **Duration:** ~50 min wall-clock end-to-end (Tasks 1-2 autonomous + Tasks 3-5 interactive live-AWS + three deviation-fix iterations)
- **Started:** 2026-05-05 (commit `7ec0b2e` author time)
- **Completed:** 2026-05-05 (final live verify-kb.sh PASS)
- **Tasks:** 5 (Tasks 1-2 autonomous; Tasks 3-5 user-driven live AWS)
- **Files modified:** 2 plan deliverables (`bin/verify-kb.sh`, `RUNBOOK.md`) + 1 module file touched by deviation fixes (`infra/modules/knowledge_base/main.tf`)

## Accomplishments

- **KB-04 verified for-real (Phase 1 Success Criterion #2 closed).** `aws bedrock-agent-runtime retrieve --knowledge-base-id BKXE19AH89 --retrieval-query '{"text":"iPhone 13 Pro Max stock"}'` returns the matching catalog document with top score `0.8598317801952362` (>> the 0.4 threshold). `bin/verify-kb.sh` PASSes at attempt 1 against the live KB.
- **KB-06 verified for-real (Phase 1 Success Criterion #5 closed).** Edited `catalog/iphone-13-pro-max.md` Stock & Availability (12 -> 11 units), `aws s3 cp` re-uploaded, `start-ingestion-job KKLS6LQP9A` completed (1 modified / 0 failed), `verify-kb.sh` PASSed at attempt 1 with top score `0.8601263761520386`. Catalog file then reverted via `git checkout --` and a final sync job `AWI4TJPQN9` re-indexed the original 12-units content so the KB is byte-identical to repo state.
- **Live AWS infrastructure populated and stable.** Final outputs (still live in user's account — DO NOT destroy):

  | Output | Value |
  |--------|-------|
  | `kb_id` | `BKXE19AH89` |
  | `kb_arn` | `arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89` |
  | `data_source_id` | `V9KJOLJTZC` |
  | `source_bucket_name` | `hera-kb-source-prod` |
  | region | `ap-northeast-1` |
  | account | `851725411875` |

- **Three deviation fixes hardened the IaC and the operator script** before the final green: S3 Vectors metadata configuration (`9006d48`), Terraform data-source replace lifecycle (`28bbcee`), verify-kb.sh fail-fast preflight (`f78a39a`). All three are documented in detail under "Deviations from Plan" below.
- **RUNBOOK.md fully populated.** Zero `TODO(plan-03):` markers remain; all eight sections (Pre-flight, First deploy, First sync, Verify, Re-index, Recovery, Cleanup, Next steps deferred) carry concrete commands. Pitfalls A (Titan v2 model access) and J (build-time vs runtime CLI surfaces) are explicit.

## Task Commits

Each task was committed atomically (live-run tasks 3-5 produced no new repo commits — the artifacts are AWS resources, not files):

1. **Task 1: Author bin/verify-kb.sh from the verified D-15 skeleton** — `7ec0b2e` (feat). Subsequently fixed by `f78a39a` (deviation 3).
2. **Task 2: Fill in the seven RUNBOOK.md TODO(plan-03) markers with actual commands** — `dad8e67` (docs).
3. **Task 3: terraform apply (live AWS deploy)** — no repo commit; produced live KB `BKXE19AH89`, data source `V9KJOLJTZC`, source bucket `hera-kb-source-prod`, S3 Vectors index `hera-kb-index`, IAM role `hera-kb-service-role` in account 851725411875 / ap-northeast-1. Initial apply succeeded with KB id `DWQQ6HXRQW`; that KB was replaced when the metadata-configuration fix (`9006d48`) and lifecycle fix (`28bbcee`) landed and re-applied — final live KB id is `BKXE19AH89`.
4. **Task 4: Upload catalog/*.md, trigger ingestion, wait for COMPLETE** — no repo commit. `aws s3 cp catalog/ s3://hera-kb-source-prod/catalog/ --recursive --exclude "*" --include "*.md"` succeeded (4 files). First ingestion job `SNO941TQVJ` failed 2/4 docs with the 2 KB filterable-metadata cap (triggered deviation `9006d48`). Second ingestion job `231ZT93KYF` (after the metadata fix and KB replacement) returned `numberOfDocumentsScanned: 4, numberOfNewDocumentsIndexed: 4, numberOfDocumentsFailed: 0, status: COMPLETE`.
5. **Task 5: Run bin/verify-kb.sh — final KB-04 verification** — no repo commit. After `f78a39a` (verify-kb.sh fail-fast fix) and a `winget install jqlang.jq`, `bin/verify-kb.sh --kb-id BKXE19AH89 --region ap-northeast-1` PASSed at attempt 1: `hits=3 top_score=0.8598317801952362 >= threshold 0.4`. KB-06 re-index walkthrough also PASSed at attempt 1: ingestion job `KKLS6LQP9A` completed (1 modified / 0 failed), top score `0.8601263761520386`. Catalog reverted; final sync job `AWI4TJPQN9` re-indexed original content; KB now matches repo state.

**Deviation-fix commits (all already on master):**

- `9006d48` — `fix(01-02): mark AMAZON_BEDROCK_* metadata as non-filterable in S3 Vectors index`
- `28bbcee` — `fix(01-02): force data_source replacement when KB is replaced`
- `f78a39a` — `fix(01-03): verify-kb.sh fails fast on missing jq instead of silent zero-fallback`

**Plan metadata commit:** appended after this summary is written (covers SUMMARY.md, STATE.md, ROADMAP.md, REQUIREMENTS.md).

## Files Created/Modified

- `bin/verify-kb.sh` (created in `7ec0b2e`, hardened in `f78a39a`) — KB-04 verification script. Polls `aws bedrock-agent-runtime retrieve` every 15s for up to 5 minutes (covers Pitfall C post-sync propagation), defaults to query `{"text":"iPhone 13 Pro Max stock"}` and threshold 0.4, supports `--kb-id`, `--region`, `--query`, `--threshold`, `--invert` (Phase 4 cleanup reuse per D-16), and `--help`. Now asserts `aws` and `jq` are on PATH at startup and exits 2 on miss with platform install hints.
- `RUNBOOK.md` (modified in `dad8e67`) — All seven `TODO(plan-03):` sentinel markers replaced. Pre-flight enumerates the four blocking deps + Titan v2 model-access enable (Pitfall A). First deploy uses `cd infra/envs/prod && terraform init && terraform apply` and documents the `-var=region=us-east-1` override (DEP-06). First sync uses build-time `aws bedrock-agent start-ingestion-job` + `get-ingestion-job` poll loop and explicitly distinguishes from the runtime `bedrock-agent-runtime` (Pitfall J). Verify invokes `bin/verify-kb.sh`. Re-index reuses the same sync command incrementally. Recovery uses destroy + re-apply (D-12). Cleanup uses `bin/verify-kb.sh --invert` (D-16). The Plan 01 "Next steps (deferred)" section is preserved verbatim.
- `infra/modules/knowledge_base/main.tf` (modified in `9006d48` and `28bbcee` — deviation fixes; see below) — added `metadata_configuration { non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"] }` to `aws_s3vectors_index.this` and `lifecycle { replace_triggered_by = [aws_bedrockagent_knowledge_base.this] }` to `aws_bedrockagent_data_source.catalog`. Both fixes root-cause to plan 01-02 module shape, not 01-03 deliverables; commit prefixes are `fix(01-02):` accordingly.

## Decisions Made

All three live-run decisions are recorded in the frontmatter `key-decisions` and were forced by AWS-side reality discovered during the live apply:

1. **S3 Vectors metadata is split into filterable vs non-filterable buckets.** Bedrock writes chunk text into `AMAZON_BEDROCK_TEXT`; if that key is filterable (the default), the 2 KB cap is breached the moment a chunk approaches 300 tokens. Both `AMAZON_BEDROCK_TEXT` and `AMAZON_BEDROCK_METADATA` are retrieve-only — there is no Bedrock retrieve API surface that filters on them — so marking them non-filterable is the correct shape, not a workaround. This is now baked into the module.
2. **Terraform replace_triggered_by from data source to KB is mandatory** for any project that may replace the KB (which happens whenever the index dimension or metadata configuration changes). This is a known AWS-provider gap; without the lifecycle block, terraform state corruption is guaranteed on the next apply that forces KB replacement.
3. **Operator scripts must fail loudly on missing dependencies, not coast through with placeholder zeroes.** This aligns with AGENTS.md ("don't program defensively"). The original `2>/dev/null || echo 0` pattern in verify-kb.sh was a textbook diagnostic-killing fallback.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AMAZON_BEDROCK_TEXT filterable-metadata 2 KB cap silently broke ingestion**
- **Found during:** Task 4 (first ingestion job `SNO941TQVJ`).
- **Issue:** First `aws bedrock-agent start-ingestion-job` returned `numberOfDocumentsFailed: 2` with the failure reason `Filterable metadata must have at most 2048 bytes (Service: S3Vectors, Status Code: 400)` for the two largest catalog files. Root cause: the Plan 01-02 `aws_s3vectors_index` resource did not declare a `metadata_configuration` block, so all metadata keys defaulted to filterable. Bedrock writes the 300-token chunk text into `AMAZON_BEDROCK_TEXT`, which routinely exceeds 2 KB.
- **Fix:** Added a `metadata_configuration { non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"] }` block to `aws_s3vectors_index.this`. Re-applied; KB and index were replaced (forcing the next deviation, see #2 below). Re-ran ingestion (`231ZT93KYF`) — `numberOfNewDocumentsIndexed: 4, numberOfDocumentsFailed: 0`.
- **Files modified:** `infra/modules/knowledge_base/main.tf`.
- **Verification:** Re-ran ingestion to COMPLETE with 4/4 indexed; subsequently `bin/verify-kb.sh` PASSed at attempt 1 against the new KB.
- **Committed in:** `9006d48` (`fix(01-02): mark AMAZON_BEDROCK_* metadata as non-filterable in S3 Vectors index`).
- **Commit prefix scope:** `fix(01-02)` rather than `fix(01-03)` because the gap is in the Plan 01-02 module's index resource shape, not in any 01-03 deliverable. RESEARCH.md line 16 noted the 2 KB filterable cap but did not surface it into the module — the planner-side gap is honest to acknowledge in 01-02's blame trail.

**2. [Rule 1 - Bug] Terraform provider does not propagate KB replacement to its data source**
- **Found during:** Task 3 second `terraform apply` (the one that landed deviation #1's index/KB replacement).
- **Issue:** When `aws_s3vectors_index.this` and `aws_bedrockagent_knowledge_base.this` were marked for replacement (forced by the metadata_configuration change), the AWS provider did NOT mark `aws_bedrockagent_data_source.catalog` for replacement. The provider then attempted `UpdateDataSource` against the new KB id with the stale data source id, returning `ResourceNotFoundException: DataSource with id <old_ds> in knowledgeBase with id <new_kb> is not found.` This corrupted terraform state mid-apply (the new KB existed; the old data source did not). Recovery required `terraform state rm module.knowledge_base.aws_bedrockagent_data_source.catalog` followed by another `terraform apply` to re-create.
- **Fix:** Added `lifecycle { replace_triggered_by = [aws_bedrockagent_knowledge_base.this] }` to `aws_bedrockagent_data_source.catalog`. With this in place, KB replacement now triggers data source replacement in the same plan and the API call is `CreateDataSource` against the new KB id, which succeeds.
- **Files modified:** `infra/modules/knowledge_base/main.tf`.
- **Verification:** Subsequent applies that touched the KB (during the ingestion debug loop) replaced the data source cleanly with no state-rm needed.
- **Committed in:** `28bbcee` (`fix(01-02): force data_source replacement when KB is replaced`).
- **Commit prefix scope:** `fix(01-02)` — the missing lifecycle block belongs to the module that owns both resources.

**3. [Rule 1 - Bug] verify-kb.sh masked a missing-jq install as a propagation timeout**
- **Found during:** Task 5 first invocation. Direct `aws bedrock-agent-runtime retrieve` succeeded at the CLI with top score 0.86; `bin/verify-kb.sh` reported `hits=0 top_score=0` for all 20 polling attempts and exited with `FAIL: no qualifying results after 300s`. Wasted 5 minutes per run before the failure mode pointed to the wrong root cause ("post-sync propagation lag exceeded 5min").
- **Issue:** The original script wrapped both jq invocations with `2>/dev/null || echo 0`. With `jq` not on the operator's PATH (Windows, jq not yet installed), every poll attempt printed `hits=0 top_score=0`. RUNBOOK Pre-flight already listed jq as a required dependency, but the script did not enforce it.
- **Fix:** Added a preflight block at script startup: `command -v aws` and `command -v jq` checks, exit 2 with platform install hints (`winget install jqlang.jq`, `brew install jq`, `apt-get install jq`). Removed the silent `2>/dev/null || echo 0` fallback so jq errors surface via `set -euo pipefail`. Aligns with AGENTS.md "Don't program defensively. Use exception managers only when needed."
- **Files modified:** `bin/verify-kb.sh`.
- **Verification:** After `winget install jqlang.jq` (a one-time operator step that the preflight error message now spells out), `bin/verify-kb.sh --kb-id BKXE19AH89 --region ap-northeast-1` PASSed at attempt 1 with `hits=3 top_score=0.8598317801952362`.
- **Committed in:** `f78a39a` (`fix(01-03): verify-kb.sh fails fast on missing jq instead of silent zero-fallback`).

---

**Total deviations:** 3 auto-fixed (3 Rule-1 bugs — all surfaced by live AWS / live operator-PATH reality that no offline check could catch).
**Impact on plan:** All three deviations were necessary for correctness — without them, ingestion fails 50% of documents (#1), terraform apply is non-idempotent across KB replacements (#2), and the verification script delivers false-negative timeouts (#3). No scope creep. Two of the three commits are correctly attributed to plan 01-02 because their root cause is in the module shape from that plan; this preserves an honest blame trail for plan-01-02's verifier.

## Issues Encountered

- **First terraform apply succeeded but produced a KB (`DWQQ6HXRQW`) that was subsequently replaced.** This is expected after the metadata_configuration deviation fix; the original KB id no longer exists. The current live KB is `BKXE19AH89` and is the one all infrastructure references (including any Phase 2 consumer) must use.
- **Mid-apply state corruption recovery.** When deviation #2 manifested (data source 404), recovery required `terraform state rm module.knowledge_base.aws_bedrockagent_data_source.catalog` followed by `terraform apply`. After deviation fix `28bbcee` landed, this recovery is no longer needed for future replacements.
- **jq install on Windows.** The operator's machine lacked jq on PATH. Resolved with `winget install jqlang.jq`. The verify-kb.sh preflight now spells this out explicitly so a future operator hits the right install command in one round-trip.

## User Setup Required

The user has already completed the live-run user setup for this plan. For a fresh operator going through this plan from scratch:

1. AWS credentials configured for the target account (`aws sts get-caller-identity` succeeds).
2. Amazon Titan Text Embeddings V2 model access enabled in the deploy region (Bedrock console -> Model access -> Modify -> Save changes -> wait ~1 minute). RUNBOOK Pre-flight section walks this through.
3. `jq` installed and on PATH (`winget install jqlang.jq` on Windows; `brew install jq` on macOS; `apt-get install jq` on Debian/Ubuntu). The verify-kb.sh preflight now refuses to run without it.
4. Acceptance of ~$0.05 cost for one apply + sync + verify cycle, recoverable via `cd infra/envs/prod && terraform destroy`.

## Threat Flags

None new. All threats enumerated in plan 01-03's `<threat_model>` (T-03-01 through T-03-08) hold as documented:

- **T-03-01 (script argument injection):** Verified. The preflight addition does not alter the existing double-quoted variable-expansion pattern; AWS CLI still receives each arg as a separate token.
- **T-03-04 (wrong AWS account):** Verified during Task 3 user checkpoint — operator confirmed `aws sts get-caller-identity` showed account 851725411875 before approving the apply.
- All other threats remain at their planned dispositions.

The deviation-fix #1 (S3 Vectors metadata_configuration) does not introduce new threat surface — it only changes how an existing field (chunk text) is indexed inside the same already-private S3 Vectors bucket. Public-access-block still applies.

## Next Phase Readiness

**Phase 1 success criteria — final tally:**

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Apple catalog (3 SKUs) lives in source S3 as English markdown, ingested into Bedrock KB on S3 Vectors with Titan v2 (1024-dim float32 cosine) | DONE — 4/4 catalog files indexed in `BKXE19AH89` (3 SKUs + store-policy sidecar) |
| 2 | `aws bedrock-agent-runtime retrieve` for "iPhone 13 Pro Max stock" returns the matching document with non-zero score after the documented post-sync wait | DONE — top score `0.8598317801952362`, verify-kb.sh PASSes at attempt 1 |
| 3 | `modules/knowledge_base` deploys cleanly into a fresh AWS account in `ap-northeast-1` with `terraform init && apply` and no manual console clicks (model access assumed already enabled) | DONE for replays after deviation fixes — first-time apply on a fresh account now needs only the four blocking deps + Titan v2 model access from RUNBOOK Pre-flight |
| 4 | Least-privilege IAM role exposes only `bedrock:Retrieve` scoped to KB ARN, no wildcards | Phase-1 KB service role is least-privilege with zero wildcards (verified Plan 01-02). Per D-10, the Phase-2 consumer `bedrock:Retrieve` role is built in Phase 2, scoped to `kb_arn = arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89` |
| 5 | Re-indexing after editing a product markdown is a single documented CLI command, queryable within the documented sync window | DONE — RUNBOOK "Re-index after editing a product file" section walks through the exact `aws s3 cp` + `aws bedrock-agent start-ingestion-job` pair; live-verified end-to-end via job `KKLS6LQP9A` (1 modified, 0 failed) |

Phase 1 is complete pending phase-verifier sign-off (which closes the phase checkbox in ROADMAP.md).

**Hand-off to Phase 2 (Pipecat Voice Agent — Local):**

- Phase 2 consumer role must be scoped to **`kb_arn = arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89`** (the new KB id, not the original `DWQQ6HXRQW`).
- Per D-10, the consumer `bedrock:Retrieve` role is created in Phase 2's IaC, not Phase 1. Phase 1 only exports `kb_arn`; Phase 2 attaches its own least-privilege policy with `Action = ["bedrock:Retrieve"]` and `Resource = [<kb_arn>]`.
- Phase 2's `lookup_product()` Pipecat tool can call `aws bedrock-agent-runtime retrieve --knowledge-base-id BKXE19AH89 --region ap-northeast-1` and expect the same shape verified by `bin/verify-kb.sh`.
- The KB resources are LIVE in the user's account — Phase 2 development should NOT run `terraform destroy` in `infra/envs/prod`.
- `bin/verify-kb.sh --invert` is reserved for Phase 4 cleanup verification (D-16) — it intentionally inverts the success contract so a destroy run can prove the KB is gone.

**No blockers for Phase 2.** All four module outputs (`kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`) are populated and consumable.

## Self-Check: PASSED

**Plan 01-03 must_haves (truths) — all verified:**

| Truth | Verified |
|-------|----------|
| `bin/verify-kb.sh` exists, executable, no emojis, verbatim D-15 + RESEARCH.md skeleton (15s polling for max 5 min; jq path `.retrievalResults[0].score`; `--invert` for Phase 4) | YES — `7ec0b2e` baseline + `f78a39a` hardening. `MAX_ATTEMPTS=20`, `SLEEP_SECONDS=15`, jq path matches, `--invert` flag present. |
| RUNBOOK.md has all eight sections fully written — seven `TODO(plan-03)` markers replaced | YES — `dad8e67`. Zero `TODO(plan-03):` markers remain. |
| RUNBOOK.md First sync uses `aws bedrock-agent start-ingestion-job` (build-time API, NOT `bedrock-agent-runtime` — Pitfall J) | YES — explicit Pitfall J distinction in the section. |
| RUNBOOK.md Recovery uses `terraform destroy && terraform apply` per D-12 (no random suffix, no terraform import) | YES. |
| RUNBOOK.md Pre-flight enumerates the four blocking deps (Terraform >= 1.9, AWS CLI v2, jq, AWS credentials) AND documents the Titan v2 model-access enable step in `ap-northeast-1` (Pitfall A) | YES. |
| End-to-end live verification passes: `terraform apply` succeeds, `aws s3 cp` uploads four catalog files, `start-ingestion-job` completes, `bin/verify-kb.sh` prints OK with `hits >= 1` and top score `>= 0.4`, exits 0 — KB-04 verified | YES — final apply produced KB `BKXE19AH89`; ingestion job `231ZT93KYF` returned `numberOfNewDocumentsIndexed: 4`; `bin/verify-kb.sh` PASSed at attempt 1 with `hits=3 top_score=0.8598317801952362`. |
| Re-index path verified: editing one catalog file, re-running `aws s3 cp` + `start-ingestion-job`, `bin/verify-kb.sh` still passes — KB-06 verified | YES — `catalog/iphone-13-pro-max.md` edited (12->11 units), re-uploaded, ingestion job `KKLS6LQP9A` completed (1 modified / 0 failed), `bin/verify-kb.sh` PASSed at attempt 1 with top score `0.8601263761520386`. Catalog reverted; final sync `AWI4TJPQN9` re-indexed original; KB matches repo state. |

**Files exist on disk:**
- `bin/verify-kb.sh` — FOUND
- `RUNBOOK.md` — FOUND
- `infra/modules/knowledge_base/main.tf` (modified by deviation fixes) — FOUND

**Commits exist in git log:**
- `7ec0b2e` (Task 1 baseline) — FOUND
- `dad8e67` (Task 2) — FOUND
- `9006d48` (deviation #1) — FOUND
- `28bbcee` (deviation #2) — FOUND
- `f78a39a` (deviation #3) — FOUND

**Live AWS state verified:**
- KB `BKXE19AH89` returns score `0.8598317801952362` for the verification query.
- Ingestion job `AWI4TJPQN9` (the final post-revert sync) completed with 4 docs indexed against the unmodified catalog.

---
*Phase: 01-knowledge-base-foundation*
*Completed: 2026-05-05*
