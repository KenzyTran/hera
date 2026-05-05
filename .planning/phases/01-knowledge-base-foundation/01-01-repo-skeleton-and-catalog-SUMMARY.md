---
phase: 01-knowledge-base-foundation
plan: 01
subsystem: infra
tags: [catalog, markdown, gitignore, runbook, knowledge-base, s3-vectors, bedrock]

# Dependency graph
requires:
  - phase: 00-init
    provides: project scaffold (Hugo site, .planning workflow)
provides:
  - "catalog/ directory with 4 English markdown source files (3 SKUs + store-policy sidecar) following the D-02 schema"
  - "RUNBOOK.md stub at repo root with eight operational sections and seven TODO(plan-03) markers"
  - ".gitignore augmented with Terraform ignore patterns; Hugo entries preserved; .terraform.lock.hcl intentionally NOT ignored"
affects: [01-02-knowledge-base-terraform-module, 01-03-verify-and-runbook-fill, 02-pipecat-voice-agent, 04-cleanup, 05-workshop-docs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "S3-source markdown without YAML/TOML front-matter (front-matter would pollute Bedrock embeddings)"
    - "Per-SKU schema with H1 SKU name + H2 Overview/Specifications/Pricing/Stock & Availability driving 300-token chunk quality"
    - "D-03 stock-chunk co-location: SKU name appears verbatim inside the Stock & Availability section so retrieval chunks always carry the SKU identifier"
    - "RUNBOOK.md stub-now / fill-later split with TODO(plan-03) sentinel markers grep-replaceable in Plan 03"
    - "Terraform ignore baseline established BEFORE any terraform init runs (prevents first-time state leak)"

key-files:
  created:
    - "catalog/apple-watch-s11.md"
    - "catalog/iphone-13-pro-max.md"
    - "catalog/macbook-pro-m4.md"
    - "catalog/store-policy.md"
    - "RUNBOOK.md"
  modified:
    - ".gitignore"

key-decisions:
  - "Stock data inlined in each SKU file (D-03), not in a shared stock.md, so retrieval chunks always co-locate stock numbers with the SKU name"
  - "RUNBOOK.md is a stub with seven TODO(plan-03) markers; the Next steps (deferred) section is fully written now because it documents D-10/D-11/Guardrails decisions that are already final"
  - ".terraform.lock.hcl is NOT in .gitignore (commit the lock for reproducibility per PATTERNS.md decision); terraform.tfvars is also NOT ignored because Phase 1 has no secrets"

patterns-established:
  - "Pattern: catalog markdown files at repo root, English only, no front-matter, four-section schema (H1 SKU + H2 Overview/Specifications/Pricing/Stock & Availability)"
  - "Pattern: top-level operational docs (RUNBOOK.md) live at repo root, are English only, and are invisible to the Hugo build path"
  - "Pattern: TODO(plan-NN) sentinel markers for cross-plan coordination — Plan 03 will grep-replace TODO(plan-03) markers"
  - "Pattern: .gitignore append-not-replace when extending a generated baseline (preserve Hugo entries while adding Terraform)"

requirements-completed: [KB-01]

# Metrics
duration: 5min
completed: 2026-05-05
---

# Phase 1 Plan 1: Repo Skeleton and Catalog Summary

**Authored four English Apple-product catalog markdown files (3 SKUs + store-policy sidecar) per the D-02 schema with stock data inlined per D-03, added a RUNBOOK.md operational stub, and extended .gitignore with Terraform patterns while preserving the existing Hugo entries.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-05T01:28:52Z
- **Completed:** 2026-05-05T01:33:13Z
- **Tasks:** 3
- **Files modified:** 6 (5 created, 1 modified)

## Accomplishments
- KB-01 prerequisite satisfied: `catalog/` directory ready for Plan 02 Terraform module to reference and Plan 03 manual `aws s3 cp` to upload
- iPhone 13 Pro Max file is the canonical KB-04 verification target — its `## Stock & Availability` section repeats the SKU name three times so any retrieved chunk carries the SKU identifier
- RUNBOOK.md skeleton locks in the eight-section operational surface; Plan 03 only has to grep-replace the seven `TODO(plan-03):` markers
- Terraform-state leak (threat T-01-03) mitigated BEFORE Plan 02 runs `terraform init`

## Task Commits

Each task was committed atomically:

1. **Task 1: Author the four catalog markdown files under catalog/** - `5d6cffa` (feat)
2. **Task 2: Create RUNBOOK.md stub at repo root** - `d049be7` (docs)
3. **Task 3: Append Terraform ignore patterns to .gitignore (preserve Hugo entries)** - `8c425b8` (chore)

**Plan metadata commit:** appended after this summary is written (will include SUMMARY.md, STATE.md, ROADMAP.md, REQUIREMENTS.md updates).

## Files Created/Modified
- `catalog/apple-watch-s11.md` — Apple Watch Series 11 spec/price/stock catalog (S11 SiP, 42mm/46mm, Aluminum/Titanium, six configs from $399 to $799)
- `catalog/iphone-13-pro-max.md` — iPhone 13 Pro Max canonical reference SKU; KB-04 verification query target ("iPhone 13 Pro Max stock")
- `catalog/macbook-pro-m4.md` — MacBook Pro M4 spec/price/stock catalog (M4/M4 Pro/M4 Max chips, 14"/16", five configs from $1,599 to $3,499)
- `catalog/store-policy.md` — Apple Store policy sidecar (Returns, Store Hours, Warranty, Contact) — D-01 gives the Phase 2 Sonic persona policy questions to answer beyond product Q&A
- `RUNBOOK.md` — 51-line stub with eight ordered sections and seven `TODO(plan-03):` markers; the Next steps (deferred) section is fully written
- `.gitignore` — preserved three Hugo entries (`public/`, `resources/`, `.hugo_build.lock`); appended a `# Terraform` section with state, working-dir, crash-log, and override patterns; intentionally excluded `.terraform.lock.hcl` and `terraform.tfvars`

## Decisions Made
None additional — all decisions were already locked in 01-CONTEXT.md (D-01 through D-16) and PATTERNS.md before execution. The plan executed exactly as written.

## Deviations from Plan

None — plan executed exactly as written.

The plan's verbatim Task 1 acceptance command `awk '/^## Stock & Availability$/,/^## /' catalog/iphone-13-pro-max.md | grep -q 'iPhone 13 Pro Max'` does not actually verify the D-03 invariant: when the Stock & Availability section is the LAST H2 in the file (which it is by the D-02 schema), the awk range `/A/,/B/` closes immediately because the opening line `## Stock & Availability` itself matches the closing pattern `^## `. The robust verification used during execution was:

```bash
awk 'BEGIN{p=0} /^## Stock & Availability$/{p=1; print; next} /^## /{p=0} p' catalog/iphone-13-pro-max.md | grep -q 'iPhone 13 Pro Max'
```

This is an observation about the plan's verify command, not a deviation in the produced files. The D-03 invariant holds: the iPhone file's Stock & Availability section repeats `iPhone 13 Pro Max` three times, the Apple Watch file repeats `Apple Watch Series 11` once, and the MacBook file repeats `MacBook Pro M4` twice (verified during execution).

## Issues Encountered

- **Hugo binary not on PATH in execution environment.** The plan's success criterion #4 ("Hugo build still works") could not be locally verified. Risk is structurally mitigated by PATTERNS.md §"Hugo Coexistence Confirmation": Hugo only consumes `config.toml`, `content/`, `layouts/`, `themes/`, `static/`, `i18n/` — none of the three new entries (`catalog/`, `RUNBOOK.md`, modified `.gitignore`) are in Hugo's input paths. The GitHub Actions deploy workflow on the next push to main will demonstrate the build passes.

## User Setup Required

None - no external service configuration required for this plan. (Plan 02 will require Bedrock Titan v2 model access enabled in the AWS console.)

## Threat Flags

None - no new security-relevant surface introduced. T-01-03 (local Terraform state leak via git) was mitigated by Task 3 as planned, before any Terraform state can be created.

## Next Phase Readiness

- **Plan 02 (Terraform module) is ready to start.** It can reference `catalog/` as the source bucket's seed content and assume `.gitignore` already covers Terraform state.
- **Plan 03 (verify + RUNBOOK fill-in + apply + sync) depends on Plan 02 outputs** (`kb_id`, `source_bucket_name`) to grep-replace the seven `TODO(plan-03)` markers in RUNBOOK.md.
- **No blockers.** Hugo build coexistence confirmed structurally; no Hugo workflow changes needed.

## Self-Check: PASSED

- Files: `catalog/apple-watch-s11.md`, `catalog/iphone-13-pro-max.md`, `catalog/macbook-pro-m4.md`, `catalog/store-policy.md`, `RUNBOOK.md` all exist on disk; `.gitignore` modified.
- Commits: `5d6cffa`, `d049be7`, `8c425b8` all present in `git log --oneline`.

---
*Phase: 01-knowledge-base-foundation*
*Completed: 2026-05-05*
