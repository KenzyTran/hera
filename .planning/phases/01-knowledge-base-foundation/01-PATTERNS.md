# Phase 1: Knowledge Base Foundation - Pattern Map

**Mapped:** 2026-05-05
**Files analyzed:** 12 (11 new, 1 modified)
**Analogs found:** 3 / 12 (greenfield phase — most files have no analog by design)

## Greenfield State (Evidence)

Verified `2026-05-05` against the working tree at `C:/Users/trant/projects/hera/`:

| Search | Result |
|--------|--------|
| `Glob **/*.tf` | No files found |
| `Glob **/*.py` | No files found |
| `Glob **/*.sh` | Only `.claude/hooks/*.sh` (GSD tooling, not project source) |
| `bin/`, `infra/`, `terraform/`, `catalog/` directories | None exist |
| Top-level `.md` files | Only `CLAUDE.md`, `README.md` — no `RUNBOOK.md` |

Repo root contents (definitive list): `.claude/`, `.git/`, `.github/`, `.gitignore`, `.gitmodules`, `.planning/`, `.vscode/`, `CLAUDE.md`, `README.md`, `config.toml`, `content/`, `i18n/`, `layouts/`, `raw_content.txt`, `static/`, `themes/`.

**Confirmation:** Phase 1 is the first phase to introduce Terraform, AWS resource code, bash project scripts, and a top-level operational runbook. Greenfield is expected and correct.

## Hugo Coexistence Confirmation

Hugo's build (`.github/workflows/deploy.yml`, line 47-51) runs `hugo --gc --minify --baseURL ...` from the repo root. Hugo consumes ONLY:

- `config.toml` (root config — single file at root)
- `content/` (markdown sources, per `[languages.*].contentDir`)
- `layouts/` (templates)
- `themes/` (theme submodule)
- `static/` (static assets)
- `i18n/` (translation strings)

**New top-level entries added by Phase 1 are invisible to Hugo:**

| New path | Why Hugo ignores it |
|----------|---------------------|
| `infra/` | Not in Hugo's default lookup paths; not referenced by `config.toml` |
| `bin/` | Same |
| `catalog/` | Same. Hugo only reads `content/vi/` and `content/en/` per `config.toml` `contentDir` settings — `catalog/` at repo root is never scanned |
| `RUNBOOK.md` | Hugo only consumes `*.md` under `content/`; root-level markdown (like the existing `README.md` and `CLAUDE.md`) is ignored |

The Hugo deploy workflow only triggers on `push` to `main` (line 4-5) without path filters, so it WILL run when Terraform files change — but it will produce identical output because Hugo never reads the new directories. No workflow change needed in Phase 1.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `infra/modules/knowledge_base/main.tf` | iac-resources | declarative | NONE | greenfield |
| `infra/modules/knowledge_base/iam.tf` | iac-iam | declarative | NONE | greenfield |
| `infra/modules/knowledge_base/variables.tf` | iac-inputs | declarative | NONE | greenfield |
| `infra/modules/knowledge_base/outputs.tf` | iac-outputs | declarative | NONE | greenfield |
| `infra/modules/knowledge_base/versions.tf` | iac-config | declarative | NONE | greenfield |
| `infra/envs/prod/main.tf` (root) | iac-root | declarative | NONE | greenfield |
| `infra/envs/prod/variables.tf` | iac-inputs | declarative | NONE | greenfield |
| `infra/envs/prod/outputs.tf` | iac-outputs | declarative | NONE | greenfield |
| `infra/envs/prod/versions.tf` | iac-config | declarative | NONE | greenfield |
| `catalog/*.md` (4 files) | data-source | static | NONE for shape; existing `content/en/_index.md` for markdown style only | partial |
| `bin/verify-kb.sh` | script | request-response | `.claude/hooks/gsd-validate-commit.sh` (script header convention only) | partial |
| `RUNBOOK.md` | docs | static | `README.md` (root-level markdown tone/structure) | partial |
| `.gitignore` (modify) | config | static | `.gitignore` (existing 3-line file) | exact |

## Pattern Assignments

### Terraform files (all `.tf` files in `infra/`)

**Analog: NONE.** No prior Terraform exists in the repo. Planner should derive all patterns directly from `01-RESEARCH.md`:

- Provider pin: `01-RESEARCH.md` §"Standard Stack" → `hashicorp/aws ~> 6.27`, Terraform `>= 1.9`
- Module shape: `01-RESEARCH.md` §"Recommended Project Structure" → `infra/modules/knowledge_base/{main,iam,variables,outputs,versions}.tf` + `infra/envs/prod/{main,variables,outputs,versions}.tf`
- Resource argument shapes: `01-RESEARCH.md` §"Pattern 1" through §"Pattern N" (lines 262+) — copy-ready HCL excerpts
- Naming: `01-CONTEXT.md` D-12 → fixed names `hera-kb-prod`, `hera-kb-source-prod`, `hera-kb-vectors-prod`; no random suffix

**Constraints carried from CLAUDE.md / AGENTS.md:**
- No emojis in any HCL value, comment, or `description` field
- Concise comments — only where the "why" is non-obvious
- Use latest provider features (the `~> 6.27` floor is set precisely because that is the first version with native S3 Vectors KB support)

---

### `catalog/*.md` (4 product/policy markdown files)

**Analog: PARTIAL — `content/en/_index.md` for markdown convention only**

Existing Hugo content uses TOML front-matter (`title`, `date`, `weight`):

```markdown
---
title: "Workshop Title"
date: 2025-01-01
weight: 0
---
```

**DO NOT MIRROR the front-matter.** `catalog/` files are NOT Hugo content — they live at repo root, are not under `content/`, are not consumed by Hugo, and are uploaded as-is to S3 for Bedrock KB ingestion. Front-matter would only pollute the embeddings.

**Pattern to follow instead** (from `01-CONTEXT.md` D-02):

```markdown
# <SKU full name>

## Overview
<1-2 sentences of prose>

## Specifications
- chip: ...
- RAM: ...
- storage: ...
- display: ...
- battery: ...
- color options: ...
- weight: ...
- dimensions: ...

## Pricing
- <config>: $<USD>
- <config>: $<USD>

## Stock & Availability
- units in stock: <N>
- ETA if zero: <date or "in stock">
```

**Constraints:**
- English only (per CLAUDE.md "Chatbot language: English only")
- No emojis
- Short prose so Sonic TTS fits within the 8-min stream cap (per `01-CONTEXT.md` §specifics)
- `store-policy.md` follows similar structure but with policy headers instead of SKU schema (return policy, store hours, warranty)

---

### `bin/verify-kb.sh`

**Analog: PARTIAL — `.claude/hooks/gsd-validate-commit.sh`**

The only pre-existing bash files in the repo are GSD hooks (`.claude/hooks/*.sh`). They are tooling, not project source, but their style is the closest convention to mirror:

**Header pattern** (from `gsd-validate-commit.sh` lines 1-7):
```bash
#!/bin/bash
# <script-name>.sh — <one-line purpose>
# <one or two lines explaining behavior, exit codes, and any preconditions>
```

**Style observations from existing hooks:**
- `#!/bin/bash` shebang (not `#!/usr/bin/env bash`) — but `verify-kb.sh` may prefer `#!/usr/bin/env bash` for portability across dev machines (workshop learners on macOS); planner's call
- No emojis anywhere in stdout, stderr, or comments (CLAUDE.md mandate)
- Plain English error messages with no decoration
- Explicit exit codes (the hook uses `exit 0` / `exit 2`)
- Commented behavior at top, no usage block — `verify-kb.sh` should add a `--help` block per `01-CONTEXT.md` D-15 (`--kb-id` flag)

**Pattern to derive from `01-RESEARCH.md` instead** (no analog for the actual logic):
- Polling loop: 15s interval, 20 iterations max (5 min) — per D-15
- `aws bedrock-agent-runtime retrieve` invocation: see `01-RESEARCH.md` §"Verification" for the exact CLI shape
- `jq` parse path: `.retrievalResults[0].score` (flat double, not nested) per `01-RESEARCH.md` Summary §3
- Exit codes: `0` = success, non-zero with human-readable message on timeout / empty / access denied (per D-15)

**Constraints:**
- No emojis in any printed output
- `chmod +x` after creation (planner step)
- Reusable in Phase 4 with assertion inverted (per D-16) — design for that without over-engineering: a single `--expect-empty` flag is enough

---

### `RUNBOOK.md` (top-level)

**Analog: PARTIAL — existing `README.md`**

Existing `README.md` (Vietnamese-leaning, sectioned with `##`, code blocks fenced with triple backticks) is the only top-level markdown reference for tone and structure:

```markdown
# Workshop Template

Template Hugo site theo format [First Cloud Journey (FCJ)](...)...

## Cách sử dụng

### 1. <step name>

```bash
<command>
```
```

**What to mirror:**
- Top-level `# Title`, then `## Section`, then `### Numbered subsection` hierarchy
- Fenced code blocks with explicit language (` ```bash `, ` ```hcl `)
- Concise prose — this README is 80 lines total

**What NOT to mirror:**
- Vietnamese language — `RUNBOOK.md` is operational doc, English only (matches the chatbot/infra English-only convention; workshop content is the only thing that mirrors vi/en)
- The "template usage" framing — `RUNBOOK.md` is project-specific operational doc, not a template

**Required content per `01-CONTEXT.md` D-06, D-11, D-12:**
- Manual sync command: `aws bedrock-agent start-ingestion-job --knowledge-base-id <id> --data-source-id <id> --region ap-northeast-1`
- Re-index workflow (edit catalog → upload to S3 → start ingestion → verify)
- Recovery from half-failed apply: `terraform destroy` + re-apply (D-12)
- Deferred: remote backend (S3 versioned + DynamoDB lock) documented as "next step", NOT bootstrapped (D-11)
- Pre-flight: enable Titan v2 model access in Bedrock console for `ap-northeast-1` (Pitfall #3)

**Constraints:**
- No emojis
- Concise — aim for under 200 lines
- English only

---

### `.gitignore` (modify)

**Analog: EXACT — existing `.gitignore`**

Current `.gitignore` (3 lines, verified):
```
public/
resources/
.hugo_build.lock
```

These three entries are Hugo build artifacts. Phase 1 must PRESERVE them and APPEND Terraform-related ignores.

**Append pattern** (per `01-RESEARCH.md` and standard Terraform conventions):
```
# Terraform
*.tfstate
*.tfstate.*
*.tfstate.backup
.terraform/
.terraform.lock.hcl    # decision: gitignore for v1 local state; revisit when remote backend lands
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
```

**Note on `.terraform.lock.hcl`:** Standard Terraform best practice is to COMMIT the lock file. For Phase 1's local-state v1 workshop, the planner may choose either to commit it (more reproducible) or gitignore it (simpler for learners who run their own `terraform init`). Document the choice in `RUNBOOK.md`. Default recommendation: commit it (do NOT add to `.gitignore`) — it pins provider versions for the workshop and can be regenerated with `terraform init -upgrade` if needed.

**What NOT to add:**
- `terraform.tfvars` — only ignore if it contains secrets. For Phase 1 there are no secrets (region + name_prefix only), so commit it.

## Shared Patterns

### Convention: No emojis
**Source:** `CLAUDE.md` line 26 (`No emojis in code, logs, or print statements`) and `AGENTS.md` line 14 (`Never use emojis in code or in print statements or logging`)
**Apply to:** ALL Phase 1 files — `.tf` files (no emoji in `description` strings), `bin/verify-kb.sh` (no emoji in stdout/stderr/comments), `RUNBOOK.md` (no emoji in prose), `catalog/*.md` (no emoji in product copy).

### Convention: Concise docstrings, sparing comments
**Source:** `CLAUDE.md` line 27, `AGENTS.md` line 13
**Apply to:** `.tf` comments (only where "why" is non-obvious), `verify-kb.sh` (header comment only, plus inline comments at non-obvious branches), `RUNBOOK.md` (no decorative prose).

### Convention: `uv` for Python
**Source:** `CLAUDE.md` line 25, `AGENTS.md` line 16
**Apply to:** N/A in Phase 1 — no Python introduced. Documented here so the planner does NOT introduce a Python helper script "for convenience" — the verify script is bash per D-15, and any future Python lives behind `uv run`.

### Convention: Latest library APIs
**Source:** `CLAUDE.md` (locked stack section), `AGENTS.md` line 6
**Apply to:** Provider pin `~> 6.27` (which is the floor for native S3 Vectors KB support, NOT a ceiling — `~>` allows 6.27.x through 6.x). Terraform `>= 1.9`. Titan v2 model id `amazon.titan-embed-text-v2:0`.

### Convention: Region defaults
**Source:** `CLAUDE.md` (locked stack section)
**Apply to:** Both root variables.tf and module variables.tf set `region` default to `ap-northeast-1`. Override path is `terraform apply -var=region=us-east-1` (per DEP-06).

### Convention: Hugo coexistence
**Source:** This document, §"Hugo Coexistence Confirmation"
**Apply to:** All new top-level entries (`infra/`, `bin/`, `catalog/`, `RUNBOOK.md`). They will not appear in Hugo's build output and do not require Hugo workflow changes.

## No Analog Found

The following files have no codebase analog (greenfield IaC + tooling phase). Planner should derive patterns directly from `01-RESEARCH.md` and `01-CONTEXT.md`:

| File | Role | Reason |
|------|------|--------|
| `infra/modules/knowledge_base/main.tf` | iac-resources | First Terraform in the repo |
| `infra/modules/knowledge_base/iam.tf` | iac-iam | First IAM in the repo |
| `infra/modules/knowledge_base/variables.tf` | iac-inputs | First Terraform module inputs |
| `infra/modules/knowledge_base/outputs.tf` | iac-outputs | First Terraform outputs |
| `infra/modules/knowledge_base/versions.tf` | iac-config | First Terraform version pin |
| `infra/envs/prod/main.tf` | iac-root | First root module |
| `infra/envs/prod/variables.tf` | iac-inputs | First root variables |
| `infra/envs/prod/outputs.tf` | iac-outputs | First root outputs |
| `infra/envs/prod/versions.tf` | iac-config | First root version pin |

For all of the above, the planner should reference:
- `01-RESEARCH.md` §"Standard Stack" for provider/version pins
- `01-RESEARCH.md` §"Recommended Project Structure" for file layout
- `01-RESEARCH.md` §"Pattern 1: KB Service Role Trust Policy" and the patterns that follow for HCL excerpts
- `01-CONTEXT.md` D-08 through D-14 for naming, scoping, IAM no-wildcard, region defaults

## Metadata

**Analog search scope:** entire repo at `C:/Users/trant/projects/hera/` (excluding `.git/`, `themes/hugo-theme-learn/` submodule, `.planning/`)
**Files scanned:** ~30 (Hugo config, content scaffolds, `.github/workflows/deploy.yml`, `.gitignore`, `.gitmodules`, `README.md`, `CLAUDE.md`, `.claude/hooks/*.sh`, sample of `content/{vi,en}/_index.md`)
**Pattern extraction date:** 2026-05-05
**Confidence:** HIGH — greenfield state confirmed by directory listing and glob searches. Three partial analogs identified (`README.md` for runbook tone, `.claude/hooks/gsd-validate-commit.sh` for bash style, existing `.gitignore` for append baseline).

## PATTERN MAPPING COMPLETE
