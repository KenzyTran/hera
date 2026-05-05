---
phase: 01-knowledge-base-foundation
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - catalog/apple-watch-s11.md
  - catalog/iphone-13-pro-max.md
  - catalog/macbook-pro-m4.md
  - catalog/store-policy.md
  - RUNBOOK.md
  - .gitignore
autonomous: true
requirements:
  - KB-01
user_setup: []

must_haves:
  truths:
    - "Four English-only catalog markdown files exist at repo root under catalog/, each following the D-02 schema."
    - "Per-SKU files have an inline ## Stock & Availability section that contains the SKU name in the same chunk window (D-03)."
    - "RUNBOOK.md exists at repo root as a stub with the operational outline; full sync/recovery/cleanup sections are completed in Plan 03."
    - ".gitignore preserves the existing 3 Hugo entries and appends Terraform-related ignores; .terraform.lock.hcl is NOT ignored (will be committed in Plan 02)."
    - "No emojis appear anywhere in catalog/, RUNBOOK.md, or .gitignore (CLAUDE.md mandate)."
    - "Hugo build still succeeds — none of the new top-level entries enter the Hugo build path."
  artifacts:
    - path: "catalog/apple-watch-s11.md"
      provides: "Apple Watch Series 11 spec/price/stock catalog (KB-01)"
      contains: "# Apple Watch Series 11"
    - path: "catalog/iphone-13-pro-max.md"
      provides: "iPhone 13 Pro Max spec/price/stock catalog — drives KB-04 verification query"
      contains: "# iPhone 13 Pro Max"
    - path: "catalog/macbook-pro-m4.md"
      provides: "MacBook Pro M4 spec/price/stock catalog (KB-01)"
      contains: "# MacBook Pro M4"
    - path: "catalog/store-policy.md"
      provides: "Apple Store policies sidecar (return policy, store hours, warranty) — D-01"
      contains: "# Store Policy"
    - path: "RUNBOOK.md"
      provides: "Operational runbook stub at repo root (full content in Plan 03)"
      contains: "# Hera Knowledge Base Runbook"
    - path: ".gitignore"
      provides: "Terraform artifacts ignored; Hugo entries preserved"
      contains: ".terraform/"
  key_links:
    - from: "catalog/*.md"
      to: "S3 source bucket (Plan 02)"
      via: "manual aws s3 cp catalog/*.md s3://<source-bucket>/catalog/ documented in Plan 03 RUNBOOK"
      pattern: "(documented in RUNBOOK; no code link in Plan 01)"
    - from: ".gitignore"
      to: "Terraform working dirs (.terraform/, *.tfstate*) created in Plan 02"
      via: "ignore patterns prevent state/lock leaks"
      pattern: "\\*\\.tfstate"
---

<objective>
Lay the repo skeleton for the Knowledge Base Foundation phase: four English catalog markdown files (3 SKUs + 1 store-policy sidecar) following the D-02 schema, a `RUNBOOK.md` stub at repo root, and `.gitignore` updates that preserve the existing Hugo entries while adding Terraform artifacts.

This plan does NOT touch AWS, does NOT write Terraform, and does NOT call any CLI. It is pure file authoring. Plan 02 builds the Terraform module that consumes these files; Plan 03 fills out RUNBOOK.md and runs the live verification.

Purpose: Get the human-authored content (catalog + ignore baseline) in place first so the Terraform module in Plan 02 has a real `catalog/` directory to reference and so the workshop's source-of-truth content lives in version control before any AWS resource exists. This also establishes that new top-level paths (`catalog/`, `RUNBOOK.md`) coexist with the Hugo build (PATTERNS.md §"Hugo Coexistence Confirmation").

Output: Four `catalog/*.md` files, a stub `RUNBOOK.md`, and a modified `.gitignore`.
</objective>

<execution_context>
@C:/Users/trant/projects/hera/.claude/get-shit-done/workflows/execute-plan.md
@C:/Users/trant/projects/hera/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@C:/Users/trant/projects/hera/.planning/PROJECT.md
@C:/Users/trant/projects/hera/.planning/ROADMAP.md
@C:/Users/trant/projects/hera/.planning/STATE.md
@C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md
@C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md
@C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-PATTERNS.md
@C:/Users/trant/projects/hera/CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Author the four catalog markdown files under catalog/</name>
  <files>catalog/apple-watch-s11.md, catalog/iphone-13-pro-max.md, catalog/macbook-pro-m4.md, catalog/store-policy.md</files>
  <read_first>
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md §"Catalog content shape" (D-01, D-02, D-03)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Catalog Markdown Authoring" (verbatim iPhone 13 Pro Max example to mirror schema and prose length for the other two SKUs)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-PATTERNS.md §"catalog/*.md (4 product/policy markdown files)" — DO NOT add Hugo TOML front-matter; these are S3 source files, not Hugo content
    - C:/Users/trant/projects/hera/CLAUDE.md (no emojis, English only for chatbot content)
  </read_first>
  <action>
Create four markdown files under a new top-level `catalog/` directory. None of these files have YAML or TOML front-matter — they are uploaded as-is to S3 for Bedrock KB ingestion (front-matter would pollute embeddings, per PATTERNS.md). All content is English only (CLAUDE.md "Chatbot language: English only"). NO emojis anywhere. Plausible 2026 figures for stock and pricing per D-02 discretion area.

Per D-02, every SKU file uses this exact section structure (verbatim H1 + H2 ordering — drives chunking quality with the FIXED_SIZE 300-token / 20%-overlap configuration locked in D-04):

```
# <SKU full name>

## Overview
<1-2 sentences of prose>

## Specifications
- <bullet list: chip, RAM/memory, storage, display, battery, color options, weight, dimensions, water resistance>

## Pricing
- <config>: $<USD>

## Stock & Availability
<inline stock counts per config + ETA if zero — D-03 keeps stock in same chunk window as SKU name>
```

Per D-03, the `## Stock & Availability` section MUST be inside the same SKU file (NOT a separate `stock.md`) AND the section's prose MUST contain the SKU name or model identifier so any retrieved chunk that includes a stock number also includes the SKU name. This is what makes the KB-04 verification query "iPhone 13 Pro Max stock" return the iPhone file with high score.

Per D-04, the chunking is FIXED_SIZE 300 tokens / 20% overlap (set in Plan 02 Terraform). Keep each SKU file short enough that the H1, Overview, Specifications, Pricing, and Stock sections together can fit in a small number of chunks (~600-900 tokens of prose total per file).

**File 1: `catalog/apple-watch-s11.md`** — Apple Watch Series 11. Use plausible 2026 figures:
- Chip: S11 SiP (next-gen after the real Series 10's S10)
- Display: Always-On Retina LTPO3 OLED, ~1.92" / ~2.05" depending on case
- Case sizes: 42mm, 46mm
- Battery: up to 36 hours typical, 72 hours in low-power mode
- Connectivity: GPS, GPS+Cellular variants
- Materials: Aluminum (Jet Black, Rose Gold, Silver) and Titanium (Natural, Gold, Slate)
- Pricing: GPS 42mm Aluminum $399, GPS 46mm Aluminum $429, Cellular 42mm Aluminum $499, Cellular 46mm Aluminum $529, Cellular 42mm Titanium $749, Cellular 46mm Titanium $799
- Stock: e.g. "Currently in stock: 18 units (GPS 42mm Aluminum Jet Black), 11 units (GPS 46mm Aluminum Silver), 5 units (Cellular 46mm Titanium Natural). Other configurations on order, ETA 5-7 business days. Apple Watch Series 11 typically ships within 24 hours."
- Water resistance: WR50 + IP6X
- Weight: ~30 g (42mm Aluminum), ~40 g (46mm Titanium)
- Dimensions: case-size-dependent (give two)

**File 2: `catalog/iphone-13-pro-max.md`** — Use the verbatim example from RESEARCH.md §"Catalog Markdown Authoring" lines 855-879. This is the canonical reference SKU and the KB-04 verification query targets it. Copy the file content as written in RESEARCH.md — it already meets D-02 and D-03.

**File 3: `catalog/macbook-pro-m4.md`** — MacBook Pro M4 (2026 figures, plausible):
- Chip options: M4, M4 Pro (12-core CPU/16-core GPU), M4 Max (16-core CPU/40-core GPU)
- Display: 14.2-inch or 16.2-inch Liquid Retina XDR with ProMotion (120 Hz)
- Memory: 16 GB unified default; up to 64 GB on M4 Pro, 128 GB on M4 Max
- Storage: 512 GB, 1 TB, 2 TB, 4 TB, 8 TB
- Battery: up to 24 hours video playback (16-inch), 22 hours (14-inch)
- Colors: Space Black, Silver
- Weight: 1.55 kg (14"), 2.15 kg (16")
- Ports: 3 x Thunderbolt 5, MagSafe 3, HDMI, SDXC, headphone
- Pricing: 14" M4 16GB/512GB $1,599, 14" M4 Pro 24GB/1TB $1,999, 14" M4 Max 36GB/1TB $3,199, 16" M4 Pro 24GB/512GB $2,499, 16" M4 Max 48GB/1TB $3,499
- Stock: "Currently in stock: 7 units (14-inch M4 16GB/512GB Space Black), 4 units (16-inch M4 Pro 24GB/1TB Silver), 2 units (14-inch M4 Max 36GB/1TB Space Black). 16-inch M4 Max configurations on order, ETA 10-14 business days. MacBook Pro M4 base models ship within 48 hours."
- Dimensions: case-size-dependent

**File 4: `catalog/store-policy.md`** — Apple Store policies sidecar (D-01 — gives the Phase 2 Sonic persona more than just product Q&A; nods to the raw_content.txt Apple Store assistant tutorial). Use the same `# H1 / ## H2` structure but with policy headers instead of SKU schema:

```
# Store Policy

## Returns
<text describing 14-day return window for opened items, restocking-fee terms, accessory-only return rules>

## Store Hours
<text describing weekday hours, weekend hours, holiday closures>

## Warranty
<text describing 1-year limited warranty, AppleCare+ optional 2-year extension, what is covered (manufacturing defects), what is not (accidental damage without AppleCare+)>

## Contact
<text describing phone, email, in-store pickup options>
```

Use plausible Apple Store 2026 policy text. English only, no emojis, ~300-500 words total. Keep prose tight so any single chunk that includes "return" or "warranty" also includes the policy context.

**Hugo coexistence:** `catalog/` at repo root is invisible to Hugo (PATTERNS.md verified Hugo only reads `content/`, `layouts/`, `themes/`, `static/`, `i18n/`). No `config.toml` change needed; no Hugo workflow change needed.
  </action>
  <acceptance_criteria>
    - File `catalog/apple-watch-s11.md` exists.
    - `cat catalog/apple-watch-s11.md` contains the literal string `# Apple Watch Series 11` (exact H1 per D-02).
    - `cat catalog/apple-watch-s11.md` contains the literal string `## Overview`.
    - `cat catalog/apple-watch-s11.md` contains the literal string `## Specifications`.
    - `cat catalog/apple-watch-s11.md` contains the literal string `## Pricing`.
    - `cat catalog/apple-watch-s11.md` contains the literal string `## Stock & Availability`.
    - `cat catalog/apple-watch-s11.md` contains the substring `Apple Watch Series 11` somewhere INSIDE the `## Stock & Availability` section (D-03 — stock chunk co-locates with SKU name). Verify with: `awk '/^## Stock & Availability$/,/^## /' catalog/apple-watch-s11.md | grep -q 'Apple Watch Series 11'`.
    - File `catalog/iphone-13-pro-max.md` exists.
    - `cat catalog/iphone-13-pro-max.md` contains `# iPhone 13 Pro Max`, `## Overview`, `## Specifications`, `## Pricing`, `## Stock & Availability`.
    - `awk '/^## Stock & Availability$/,/^## /' catalog/iphone-13-pro-max.md | grep -q 'iPhone 13 Pro Max'` exits 0 (D-03; this file is also the KB-04 verification target).
    - File `catalog/macbook-pro-m4.md` exists.
    - `cat catalog/macbook-pro-m4.md` contains `# MacBook Pro M4`, `## Overview`, `## Specifications`, `## Pricing`, `## Stock & Availability`.
    - `awk '/^## Stock & Availability$/,/^## /' catalog/macbook-pro-m4.md | grep -q 'MacBook Pro M4'` exits 0 (D-03).
    - File `catalog/store-policy.md` exists.
    - `cat catalog/store-policy.md` contains `# Store Policy`, `## Returns`, `## Store Hours`, `## Warranty` (D-01 sidecar).
    - None of the four files contain a YAML front-matter delimiter `---` at line 1 (PATTERNS.md: not Hugo content). Verify: `for f in catalog/*.md; do head -1 "$f" | grep -q '^---$' && { echo "FAIL: $f has front-matter"; exit 1; }; done`.
    - No emojis (Unicode code points in U+1F300-U+1FAFF, U+2600-U+26FF, U+2700-U+27BF) anywhere in `catalog/*.md`. Verify: `python3 -c "import sys, re, pathlib; bad=[(p,line) for p in pathlib.Path('catalog').glob('*.md') for line in p.read_text(encoding='utf-8').splitlines() if re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', line)]; sys.exit(0 if not bad else (print(bad) or 1))"` exits 0. Intentional non-ASCII like accented characters in prose is allowed; emoji code points are forbidden.
    - All four files are English only (no Vietnamese characters in prose) — visual inspection by reviewer. (CLAUDE.md mandate: chatbot language English only.)
  </acceptance_criteria>
  <verify>
    <automated>test -f catalog/apple-watch-s11.md && test -f catalog/iphone-13-pro-max.md && test -f catalog/macbook-pro-m4.md && test -f catalog/store-policy.md && grep -q '^# Apple Watch Series 11$' catalog/apple-watch-s11.md && grep -q '^# iPhone 13 Pro Max$' catalog/iphone-13-pro-max.md && grep -q '^# MacBook Pro M4$' catalog/macbook-pro-m4.md && grep -q '^# Store Policy$' catalog/store-policy.md && grep -q '^## Stock & Availability$' catalog/apple-watch-s11.md && grep -q '^## Stock & Availability$' catalog/iphone-13-pro-max.md && grep -q '^## Stock & Availability$' catalog/macbook-pro-m4.md && awk '/^## Stock & Availability$/,/^## /' catalog/iphone-13-pro-max.md | grep -q 'iPhone 13 Pro Max'</automated>
  </verify>
  <done>
    Four files exist at the listed paths. Each SKU file has the exact D-02 H1/H2 ordering. Each SKU file places the SKU name inside its `## Stock & Availability` section (D-03). store-policy.md uses policy headers (Returns, Store Hours, Warranty, Contact). No front-matter, no emojis, English only.
  </done>
</task>

<task type="auto">
  <name>Task 2: Create RUNBOOK.md stub at repo root</name>
  <files>RUNBOOK.md</files>
  <read_first>
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md §"Sync trigger / re-index UX (KB-06)" (D-05, D-06, D-07) and §"Terraform module + IAM shape" (D-11, D-12)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"RUNBOOK.md outline" (lines 883-895) — the eight required sections
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-PATTERNS.md §"RUNBOOK.md (top-level)" — tone/structure mirror existing README.md, English-only operational doc
    - C:/Users/trant/projects/hera/README.md (existing top-level markdown for tone reference; do NOT mirror its Vietnamese — RUNBOOK is English)
    - C:/Users/trant/projects/hera/CLAUDE.md (no emojis)
  </read_first>
  <action>
Create `RUNBOOK.md` at the **repo root** (not under `content/`, not under `infra/`). This task creates a STUB with the section skeleton; Plan 03 fills in the actual sync and recovery commands once the Terraform module exists and outputs are known. The stub-now / fill-later split exists because the sync commands reference Terraform outputs (`terraform output -raw kb_id`, `terraform output -raw source_bucket_name`) that do not exist until Plan 02.

Per RESEARCH.md §"RUNBOOK.md outline" the runbook MUST have these eight sections in order:

```markdown
# Hera Knowledge Base Runbook

Operational runbook for the Hera Bedrock Knowledge Base on S3 Vectors. Covers first deploy, manual catalog sync, verification, recovery from a half-failed apply, cleanup, and forward-looking next steps. English only — workshop content lives under `content/{vi,en}/`; this runbook is for operators.

## Pre-flight

(Filled in Plan 03. Will document: AWS CLI v2 install + `aws sts get-caller-identity`, Terraform >= 1.9 install, `jq` install, AWS region default `ap-northeast-1`, and the critical Bedrock console step to enable Amazon Titan Text Embeddings V2 model access — Pitfall A.)

TODO(plan-03): pre-flight commands and Bedrock model-access screenshot path.

## First deploy

(Filled in Plan 03. Will document `cd infra/envs/prod && terraform init && terraform apply`.)

TODO(plan-03): exact terraform commands and expected output.

## First sync

(Filled in Plan 03. Will document `aws s3 cp catalog/*.md s3://$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)/catalog/` then `aws bedrock-agent start-ingestion-job ...` per D-05. Manual ingestion only — no auto-sync per D-07.)

TODO(plan-03): start-ingestion-job + get-ingestion-job poll loop.

## Verify

(Filled in Plan 03. Will document `bin/verify-kb.sh` and expected pass output.)

TODO(plan-03): verify-kb.sh invocation and pass/fail interpretation.

## Re-index after editing a product file

(Filled in Plan 03. Will document the same `aws s3 cp` + `start-ingestion-job` commands; Bedrock detects changed objects and incrementally re-embeds only the diff — D-06.)

TODO(plan-03): re-index workflow.

## Recovery from a half-failed apply

(Filled in Plan 03. Will document `terraform destroy && terraform apply` per D-12. Fixed resource names mean retry-after-partial-failure is destroy + re-apply, not `terraform import`. Cost of full rebuild at workshop scale is < $0.01 plus a few minutes — Pitfall D / Project Pitfall #17.)

TODO(plan-03): destroy-then-reapply walkthrough.

## Cleanup

(Filled in Plan 03 / forward-referenced from Phase 4. Will document `terraform destroy` then `bin/verify-kb.sh --invert` to confirm KB no longer responds.)

TODO(plan-03): destroy + invert-verify.

## Next steps (deferred)

- Remote Terraform backend (S3 versioned + DynamoDB lock) — out of v1 scope per D-11. For v1 the workshop default is local state. When the project grows past one operator, bootstrap a separate state-backend stack first, then migrate this stack with `terraform init -migrate-state`.
- Consumer `bedrock:Retrieve` role for Pipecat — Phase 2 (D-10). Phase 1 only outputs `kb_arn` so Phase 2 can scope its consumer role policy.
- Bedrock Guardrails (PII redaction) — out of v1 per PROJECT.md.
```

**Constraints:**
- English only (operational doc; bilingual is for workshop content under `content/{vi,en}/` only — PATTERNS.md).
- No emojis anywhere.
- Concise prose; aim for under 200 lines total even after Plan 03 fills the TODOs (PATTERNS.md "aim for under 200 lines").
- Preserve the `TODO(plan-03):` markers verbatim so Plan 03 can grep for them and replace.
- Stub sections may be one or two sentences each — the goal of this task is to lock the section ORDER and the TODO markers; content lands in Plan 03.
  </action>
  <acceptance_criteria>
    - File `RUNBOOK.md` exists at repo root: `test -f RUNBOOK.md` exits 0.
    - First line is exactly `# Hera Knowledge Base Runbook`: `head -1 RUNBOOK.md | grep -q '^# Hera Knowledge Base Runbook$'`.
    - All eight required sections exist in order: `grep -nE '^## (Pre-flight|First deploy|First sync|Verify|Re-index after editing a product file|Recovery from a half-failed apply|Cleanup|Next steps \(deferred\))$' RUNBOOK.md` returns at least 8 lines, in the listed order (verify by piping through `awk '{print NR}'` and checking line numbers ascend).
    - Exactly seven `TODO(plan-03):` markers exist (one per section, except "Next steps (deferred)" which is filled in this plan): `grep -c '^TODO(plan-03):' RUNBOOK.md` returns `7`.
    - The "Next steps (deferred)" section mentions remote backend, Phase 2 consumer role, and Guardrails: `grep -A 20 '^## Next steps (deferred)$' RUNBOOK.md | grep -E 'remote.*backend|S3.*DynamoDB'` AND `grep -A 20 '^## Next steps (deferred)$' RUNBOOK.md | grep -E 'Phase 2|consumer.*role|bedrock:Retrieve'` AND `grep -A 20 '^## Next steps (deferred)$' RUNBOOK.md | grep -qi 'guardrail'`.
    - No emojis in RUNBOOK.md: `python3 -c "import sys, re, pathlib; t=pathlib.Path('RUNBOOK.md').read_text(encoding='utf-8'); sys.exit(1 if re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', t) else 0)"` exits 0.
    - File is under 200 lines: `wc -l RUNBOOK.md | awk '{print $1}'` returns a number `<= 200`.
    - English only — no Vietnamese diacritics in section bodies (visual review).
  </acceptance_criteria>
  <verify>
    <automated>test -f RUNBOOK.md && head -1 RUNBOOK.md | grep -q '^# Hera Knowledge Base Runbook$' && grep -q '^## Pre-flight$' RUNBOOK.md && grep -q '^## First deploy$' RUNBOOK.md && grep -q '^## First sync$' RUNBOOK.md && grep -q '^## Verify$' RUNBOOK.md && grep -q '^## Re-index after editing a product file$' RUNBOOK.md && grep -q '^## Recovery from a half-failed apply$' RUNBOOK.md && grep -q '^## Cleanup$' RUNBOOK.md && grep -q '^## Next steps (deferred)$' RUNBOOK.md && [ "$(grep -c '^TODO(plan-03):' RUNBOOK.md)" = "7" ]</automated>
  </verify>
  <done>
    RUNBOOK.md stub exists at repo root with eight sections in the documented order, seven TODO(plan-03) markers (Plan 03 will replace these with real commands), and a fully-written "Next steps (deferred)" section. No emojis, English only, under 200 lines.
  </done>
</task>

<task type="auto">
  <name>Task 3: Append Terraform ignore patterns to .gitignore (preserve Hugo entries)</name>
  <files>.gitignore</files>
  <read_first>
    - C:/Users/trant/projects/hera/.gitignore (current 3-line file: `public/`, `resources/`, `.hugo_build.lock` — these MUST be preserved)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-PATTERNS.md §".gitignore (modify)" — explicit append-pattern guidance and the `.terraform.lock.hcl` decision (commit it, do NOT add to .gitignore)
    - C:/Users/trant/projects/hera/.planning/phases/01-knowledge-base-foundation/01-RESEARCH.md §"Local Terraform State for v1" reasoning (D-11 — local state means `*.tfstate*` MUST be gitignored to avoid leaking ARNs/outputs into git)
  </read_first>
  <action>
**Append** to the existing `.gitignore` — DO NOT replace it. The current file has three lines (`public/`, `resources/`, `.hugo_build.lock`) which are Hugo build artifacts and MUST remain. The append pattern is verbatim from PATTERNS.md §".gitignore (modify)":

```
# Terraform
*.tfstate
*.tfstate.*
*.tfstate.backup
.terraform/
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
```

**Specific exclusions from the standard Terraform ignore template (justification carried from PATTERNS.md):**
- DO NOT ignore `.terraform.lock.hcl`. Standard practice is to commit it; for the v1 workshop it pins provider versions for reproducibility, and `terraform init -upgrade` regenerates it when needed. Plan 02 will commit a `.terraform.lock.hcl` once `terraform init` is run.
- DO NOT ignore `terraform.tfvars`. There are no secrets in Phase 1's variables (region + name_prefix only), so it can be committed for workshop reproducibility.
- DO NOT ignore `*.tf` files of any kind — those are source.

The blank line and `# Terraform` header are intentional separation between Hugo and Terraform sections so the file remains readable. Do not add a trailing newline beyond a single one.

**Hugo coexistence:** This change is invisible to Hugo (Hugo does not read `.gitignore`). The ignore patterns prevent leaking local Terraform state (Plan 02) and crash logs into git.
  </action>
  <acceptance_criteria>
    - `.gitignore` still contains the three original Hugo entries: `grep -q '^public/$' .gitignore` AND `grep -q '^resources/$' .gitignore` AND `grep -q '^\.hugo_build\.lock$' .gitignore` (all three exit 0).
    - `.gitignore` contains all required Terraform entries: `grep -q '^\*\.tfstate$' .gitignore` AND `grep -q '^\*\.tfstate\.\*$' .gitignore` AND `grep -q '^\.terraform/$' .gitignore`.
    - `.gitignore` does NOT contain `.terraform.lock.hcl` (PATTERNS.md decision: commit the lock file): `grep -q '\.terraform\.lock\.hcl' .gitignore` exits NON-zero (i.e. command returns 1; verify via `! grep -q '\.terraform\.lock\.hcl' .gitignore`).
    - `.gitignore` does NOT contain `terraform.tfvars` (no secrets in Phase 1): `! grep -q '^terraform\.tfvars$' .gitignore`.
    - `.gitignore` does NOT contain a wildcard that would ignore `.tf` source files: `! grep -qE '^\*\.tf$' .gitignore`.
    - The file has a `# Terraform` section header: `grep -q '^# Terraform$' .gitignore`.
    - Total line count is reasonable (~16-18 lines): `wc -l .gitignore | awk '{print $1}'` returns a value between 14 and 22.
  </acceptance_criteria>
  <verify>
    <automated>grep -q '^public/$' .gitignore && grep -q '^resources/$' .gitignore && grep -q '^\.hugo_build\.lock$' .gitignore && grep -q '^# Terraform$' .gitignore && grep -q '^\*\.tfstate$' .gitignore && grep -q '^\.terraform/$' .gitignore && ! grep -q '\.terraform\.lock\.hcl' .gitignore && ! grep -q '^terraform\.tfvars$' .gitignore</automated>
  </verify>
  <done>
    `.gitignore` retains its three Hugo entries and adds a `# Terraform` section ignoring state files, terraform working dirs, crash logs, and override files — but NOT `.terraform.lock.hcl` (commit it) and NOT `terraform.tfvars` (no secrets in Phase 1). Hugo build path is unaffected.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| filesystem -> git history | Files written here will be committed; sensitive data must NOT enter the file (no AWS keys, no account IDs). |
| filesystem -> S3 source bucket (in Plan 03) | The `catalog/*.md` files will eventually be uploaded to S3 via the manual sync step documented in Plan 03's RUNBOOK. They become readable by the Bedrock KB service role (least-privilege scoped in Plan 02). |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation |
|-----------|----------|-----------|----------|-------------|------------|
| T-01-01 | Information Disclosure | catalog/*.md content | low | accept | Catalog content is synthetic Apple product specs (not PII, not secrets). The content WILL be uploaded to a private S3 bucket in Plan 03 (the bucket has full public-access-block enabled per Plan 02 Pattern 3). No mitigation required at file-authoring time. |
| T-01-02 | Information Disclosure | RUNBOOK.md TODO(plan-03) markers | low | accept | RUNBOOK is checked into a public-by-default git repo; the TODO markers do not contain secrets, only placeholders. Plan 03 will fill them with `terraform output` invocations, not literal credentials. |
| T-01-03 | Information Disclosure | local Terraform state leakage via git | high | mitigate | Task 3 adds `*.tfstate`, `*.tfstate.*`, `*.tfstate.backup`, `.terraform/` to `.gitignore` BEFORE Plan 02 runs `terraform init`. This means the very first time state is created, git already ignores it. Acceptance criterion: `grep -q '^\*\.tfstate$' .gitignore` exits 0. |
| T-01-04 | Tampering | catalog content edited maliciously between commit and S3 upload | low | accept | Standard git-controlled workflow; reviewer sees diff. Plan 03's RUNBOOK documents `aws s3 cp` from the working tree, so tampering would have to land in a committed PR. |
| T-01-05 | Information Disclosure | embedded emoji or non-printable characters silently entering S3 chunks | low | mitigate | Task 1 acceptance criteria explicitly grep for emoji code-point ranges (U+1F300-U+1FAFF, U+2600-U+26FF, U+2700-U+27BF) and require zero matches. Same for RUNBOOK.md (Task 2). Aligns with CLAUDE.md "no emojis" mandate. |

**No high-severity threats remain unmitigated.** T-01-03 (local Terraform state in git) is the only `high` threat in this plan and is mitigated by the Task 3 acceptance criteria.
</threat_model>

<verification>

After all three tasks complete, the following project-wide checks must pass:

```bash
# 1. Catalog directory exists with exactly 4 files
test "$(ls -1 catalog/*.md 2>/dev/null | wc -l)" -eq 4

# 2. RUNBOOK.md exists at repo root
test -f RUNBOOK.md

# 3. .gitignore preserved Hugo entries and added Terraform entries
grep -q '^public/$' .gitignore && grep -q '^# Terraform$' .gitignore && grep -q '^\*\.tfstate$' .gitignore

# 4. Hugo build still works (most important coexistence check)
hugo --quiet --gc 2>&1 | tail -5
# Expected: "Built in <time>" with no warnings about unknown content/layouts

# 5. No emojis introduced anywhere (CLAUDE.md mandate)
python3 -c "import sys, re, pathlib; bad=[(p,i,line) for p in [pathlib.Path('RUNBOOK.md')] + list(pathlib.Path('catalog').glob('*.md')) for i, line in enumerate(p.read_text(encoding='utf-8').splitlines(), 1) if re.search(r'[\U0001F300-\U0001FAFF☀-⛿✀-➿]', line)]; print(bad if bad else 'OK: no emojis'); sys.exit(0 if not bad else 1)"

# 6. KB-04 retrieval target — iPhone file has SKU name in stock chunk window (D-03)
awk '/^## Stock & Availability$/,/^## /' catalog/iphone-13-pro-max.md | grep -q 'iPhone 13 Pro Max'
```

All six checks must exit 0 / print success.

</verification>

<success_criteria>

Plan 01 succeeds when:

1. **KB-01 prerequisite ready:** Four catalog markdown files exist under `catalog/`, follow the D-02 schema, and have stock data inline in the same chunk window as the SKU name (D-03). Plan 02 can `terraform plan` referencing this directory; Plan 03 can `aws s3 cp catalog/*.md s3://...`.
2. **RUNBOOK skeleton in place:** `RUNBOOK.md` at repo root has eight sections in the documented order with seven `TODO(plan-03):` markers Plan 03 will replace. The "Next steps (deferred)" section is fully written and documents D-10 (Phase 2 consumer role), D-11 (remote backend deferred), and Bedrock Guardrails as out-of-v1.
3. **Terraform-safe `.gitignore`:** `.gitignore` preserves Hugo entries and adds Terraform-state-and-working-dir ignores BEFORE Plan 02 creates any Terraform state. `.terraform.lock.hcl` is intentionally NOT ignored (PATTERNS.md decision: commit it for reproducibility).
4. **Hugo coexistence verified:** `hugo --quiet --gc` from repo root still exits 0. None of the three new top-level entries (`catalog/`, `RUNBOOK.md`, modified `.gitignore`) enter the Hugo build path.
5. **CLAUDE.md mandates honored:** No emojis in any file authored or modified. English only in `catalog/*.md` and `RUNBOOK.md`.

</success_criteria>

<output>
After completion, create `.planning/phases/01-knowledge-base-foundation/01-01-SUMMARY.md` per the standard summary template. Include:
- Files created (4 catalog files + RUNBOOK.md) and modified (1 .gitignore)
- Confirmation that Hugo build still passes
- TODO markers count in RUNBOOK.md (must equal 7)
- Note that Plan 02 (Terraform module) and Plan 03 (verify + RUNBOOK fill-in + apply + sync) are next, in that order.
</output>
