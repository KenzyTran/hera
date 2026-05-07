---
phase: 05-workshop-documentation-vi-en
plan: 05
subsystem: workshop-content
tags: [docs, hugo, gap-closure, submodule, redaction, i18n]
dependency_graph:
  requires:
    - .planning/phases/05-workshop-documentation-vi-en/05-VERIFICATION.md (gaps_found, 2026-05-07T12:30:00Z)
    - .planning/phases/05-workshop-documentation-vi-en/05-REVIEW.md (CR-01 + CR-02 + WR-02 confirmed)
    - .planning/phases/05-workshop-documentation-vi-en/05-04-SUMMARY.md (template shape)
  provides:
    - themes/hugo-theme-learn (registered submodule, gitlink 160000 -> upstream sha 3202533a)
    - .github/workflows/deploy.yml (branch trigger aligned to master)
    - content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md (KB id redacted to <your-kb-id>)
    - content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md (KB id redacted)
    - content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md (account + runtime + CloudFront redacted)
    - content/{vi,en}/3-hands-on/3.5-observability/_index.md (runtime + account redacted; bash block placeholder + dashboard URL self-resolved)
    - content/en/**/*.md (30 'Phần' tokens replaced with Chapter X / Section X.Y across 7 files)
  affects:
    - .planning/STATE.md (Phase 5 status flips from gaps_found to verified-pending-organic-CI)
    - .planning/REQUIREMENTS.md (no DOC-IDs flip; SC#1 + SC#2 unblock noted)
    - .planning/ROADMAP.md (Phase 5 row: all closable gaps closed; v1 milestone reachable)
tech-stack:
  added: []
  patterns:
    - "Placeholder + resolution-command pattern for instructor data redaction: replace concrete values with <your-*> placeholders + cite the resolution CLI command on the same line, so a learner copy-pasting the snippet immediately sees how to discover their own value (not the instructor's). Mirrors AWS Well-Architected guidance + AWS docs convention (e.g. <region>, <bucket-name>)."
    - "en-only commit as the explicit D-49 byte-parity exception: when the change is a Vietnamese-vocabulary leak in en files only (vi readers see the word correctly), commit en-only. The DOC-12 file-count + slug-tree parity invariant is preserved because no _index.md is added/deleted/renamed; only body prose changes."
    - "sed substitution order discipline: longer patterns BEFORE shorter (Phần 3.X to Section 3.X before Phần N to Chapter N) to prevent corruption — reversing the order would turn 'Phần 3.1' into 'Chapter 3.1' instead of 'Section 3.1'."
key-files:
  created:
    - .planning/phases/05-workshop-documentation-vi-en/05-05-SUMMARY.md
  modified:
    - .gitmodules (idempotent — entry already present; no actual diff)
    - themes/hugo-theme-learn (NEW gitlink 160000 -> 3202533a746f91c67de1a8fa373c0328ec1b403d)
    - .github/workflows/deploy.yml (line 5: ["main"] -> ["master"])
    - content/vi/3-hands-on/3.1-knowledge-base/_index.md (line 99 KB id redacted)
    - content/en/3-hands-on/3.1-knowledge-base/_index.md (line 99 KB id redacted)
    - content/vi/3-hands-on/3.2-pipecat-local/_index.md (line 297 KB id redacted)
    - content/en/3-hands-on/3.2-pipecat-local/_index.md (line 297 KB id redacted + Section 3.3 prebake)
    - content/vi/3-hands-on/3.3-deploy-agentcore/_index.md (lines 159-164 heading + 3 instructor literals)
    - content/en/3-hands-on/3.3-deploy-agentcore/_index.md (lines 159-164 heading + 3 instructor literals)
    - content/vi/3-hands-on/3.5-observability/_index.md (line 98 bash block + line 112 dashboard URL)
    - content/en/3-hands-on/3.5-observability/_index.md (line 98 bash block + line 112 dashboard URL)
    - content/en/_index.md (1 Phần)
    - content/en/1-introduction/_index.md (4 Phần)
    - content/en/2-preparation/_index.md (13 Phần)
    - content/en/4-cleanup/_index.md (1 Phần)
    - content/en/5-summary/_index.md (2 Phần)
decisions:
  - "Submodule registered as a single atomic commit per Task 1; .gitmodules content unchanged (entry was already declared, only the gitlink in HEAD was missing). The 160000 gitlink entry pinned to upstream commit 3202533a746f91c67de1a8fa373c0328ec1b403d (matcornic/hugo-theme-learn 2.5.0-27-g3202533) is the load-bearing artifact."
  - "deploy.yml branch trigger changed to single-value list ['master'] (not ['main', 'master']) so a future branch rename mistake is surfaced explicitly, not masked by a fall-through trigger list."
  - "vi+en redaction commits land per chapter-pair (4 commits total: 3.1, 3.2, 3.3, 3.5) honoring D-49 vi+en atomic-commit invariant. Each commit redacts a single chapter's instructor literal(s) + cites resolution command(s) on the same line."
  - "Phần-rename is en-only (single atomic commit covering 7 en files) — explicit D-49 byte-parity exception case because vi readers see Phần correctly. The DOC-12 file-count + slug-tree parity invariant is unchanged (no _index.md added/deleted/renamed) so bin/check-i18n-parity.sh continues to exit 0."
  - "Task 4's en-side change to 3.2 line 297 pre-applied 'Section 3.3' to avoid creating an artificial 'Phần 3.3' regression; vi-side line 297 keeps 'Phần 3.3' (Vietnamese reading is correct). The Phần count for 3.2 dropped from 6 to 5 before Task 7's bulk sed."
  - "WR-01 (3.4-web-widget code-block byte-parity drift) explicitly out of scope per project memory 'no scope creep in discuss-phase questions' — surfaced as human_verification in 05-VERIFICATION.md, not as a closable gap. Operator decides separately whether to extend bin/check-i18n-parity.sh with a third byte-parity assertion or accept the drift."
  - "DOC-11 PNG screenshot sweep stays Pending — operator-deferred per REQUIREMENTS.md; tracked in 04-HUMAN-UAT.md item #3."
  - "Demo budget honored — zero new AWS deploys; submodule fetch is from upstream public repo (free); content edits are local (free); branch-trigger fix is one YAML line (free)."
metrics:
  duration: ~7 min
  tasks_completed: 8
  files_created: 1
  files_modified: 17
  commits: 7 (functional) + 1 (this SUMMARY) = 8 atomic
  completed: 2026-05-07
---

# Phase 5 Plan 05: Gap Closure (CR-01 + CR-02 + WR-02) Summary

Closes the 3 verification gaps from 05-VERIFICATION.md (gaps_found, 2026-05-07T12:30:00Z) so Phase 5's literal phase goal is reachable. CR-01 registers the missing Hugo theme submodule (Phase 5 SC#1 unblock — published GitHub Pages site can now build); CR-02 redacts 14 instructor literals (account 851725411875, runtime hera_agent-GIsf2P4ImD, KB BKXE19AH89, CloudFront dg0w939ktclw6) across 4 chapter-pairs (3.1, 3.2, 3.3, 3.5) with placeholder + resolution-command pattern; WR-02 renames 30 leftover Vietnamese 'Phần' tokens across 7 en chapter files to Chapter X / Section X.Y so the English-track readability is restored. Adjacent fix: deploy.yml branch trigger aligned from `main` to `master` so the workflow can fire organically once a remote is configured.

## What was built

### Gap 1 (CR-01): Hugo theme submodule registration + branch trigger alignment

**Task 1 (commit 0ca6c7e — `fix(05-05): register themes/hugo-theme-learn submodule (CR-01)`)**

The pre-existing repo state had `.gitmodules` declaring `themes/hugo-theme-learn` pointing at `https://github.com/matcornic/hugo-theme-learn.git`, but no gitlink (160000 entry) was ever committed to HEAD. `git ls-tree HEAD themes/` was empty, `git submodule status` was empty, and `themes/hugo-theme-learn/` was an empty directory. CI Hugo build would have failed at theme resolution the first time the workflow ran. Pre-existing state predating Phase 5, but Phase 5 wired the parity gate ahead of this broken build path so the broken state was actively gating publication.

Sequence:

```bash
rm -rf themes/hugo-theme-learn
git submodule add https://github.com/matcornic/hugo-theme-learn.git themes/hugo-theme-learn
git submodule update --init --recursive
```

Pinned upstream commit: **3202533a746f91c67de1a8fa373c0328ec1b403d** (matcornic/hugo-theme-learn 2.5.0-27-g3202533). The submodule's contents (layouts, i18n, archetypes, exampleSite, static, theme.toml, etc.) were NOT modified — only the gitlink registration. `themes/hugo-theme-learn/layouts/partials/`, `themes/hugo-theme-learn/i18n/`, and the rest of the theme directory tree are present.

`.gitmodules` was unchanged (the entry was already declared with the matching URL/path; git reused the existing declaration and only added the gitlink to the index).

**Task 2 (commit b0e3ea8 — `fix(05-05): align deploy.yml trigger to active branch master`)**

Single-line change to `.github/workflows/deploy.yml` line 5: `branches: ["main"]` -> `branches: ["master"]`. The active branch is `master` (verified by `git branch --show-current`); without this fix the workflow would never fire even after CR-01 was closed. Single-value list per project convention so a future branch rename mistake is surfaced explicitly.

YAML still parses cleanly via `python -c "import yaml; yaml.safe_load(open('.github/workflows/deploy.yml'))"`.

### Gap 2 (CR-02): Instructor data redaction across 4 chapter-pairs

Each commit lands vi+en together per D-49.

**Task 3 (commit 73a0f28 — Phần 3.1 KB id):**

Line 99 of both `content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md`. Replaced literal `BKXE19AH89` with `<your-kb-id>` placeholder + cited resolution command `terraform -chdir=infra/envs/prod output -raw kb_id` on the same line. Also reframed the literal `0.86` top-score number as instructor-measured + clarified that learner score is environment-dependent (typical range `0.80-0.90`) because embedding seed and Bedrock model version snapshot vary.

**Task 4 (commit 9df0a6b — Phần 3.2 KB id):**

Line 297 of both `content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md`. Replaced `BKXE19AH89` with `<your-kb-id>` + resolution command. Reframed `LATENCY_MS=0` as instructor-measured + added the AGT-04 3000ms gate threshold so learners know any value below 3000 passes. en-side line pre-applied the `Section 3.3` rename for the WR-02 cleanup; vi-side keeps `Phần 3.3` (Vietnamese reading is correct).

**Task 5 (commit 2c0634f — Phần 3.3 account/runtime/CloudFront):**

Lines 159-164 of both `content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md`. The heaviest-leakage chapter — 3 instructor literals in one block. Replacements:

- `851725411875` -> `<your-account-id>` + `aws sts get-caller-identity --query Account --output text`
- `hera_agent-GIsf2P4ImD` -> `<your-runtime-id>` + `jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json`
- `https://dg0w939ktclw6.cloudfront.net/` -> `https://<your-distribution>.cloudfront.net/` + `terraform -chdir=infra/envs/prod output -raw widget_cloudfront_url`

Section heading also changed from `## Live state (instructor reference)` (vi: same English heading) to `## Reference values (resolve from your own deploy)` (vi: `## Giá trị tham chiếu (resolve từ deploy của bạn)`) so the heading matches the redacted intent.

**Task 6 (commit d2d7446 — Phần 3.5 runtime + account):**

Two leaks in 3.5: line 98 inside a copy-paste `aws bedrock-agentcore-control update-agent-runtime --agent-runtime-id <id>` bash block (the most dangerous because copy-paste targets the instructor's resource and authorization fails silently) and line 112 (instructor account ID inside a dashboard URL resolution sentence).

- Line 98 fix: replaced `hera_agent-GIsf2P4ImD` with `<your-runtime-id>` inside the bash block + added 3-line bash comment immediately preceding the command showing the resolution path (`jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json`).
- Line 112 fix: replaced the instructor-account dashboard sentence with a self-contained resolution path: `terraform -chdir=infra/envs/prod output -raw observability_dashboard_url` OR `aws cloudwatch get-dashboard --dashboard-name hera-prod ...` + literal console URL template — the learner does not need any instructor state to find their own dashboard.

After Task 6: zero hits across `content/` for `851725411875|hera_agent-GIsf2P4ImD|BKXE19AH89|dg0w939ktclw6` (closing CR-02 audit confirmed).

### Gap 3 (WR-02): Phần rename across content/en/

**Task 7 (commit fd121af — `fix(05-05): rename Phần to Chapter/Section across content/en (WR-02, en-only D-49 exception)`)**

Single en-only atomic commit covering 7 files. Canonical sed sequence (longer patterns BEFORE shorter to prevent `Phần 3.X` corruption):

```bash
sed -i \
  -e 's/Phần 3\.1/Section 3.1/g' \
  -e 's/Phần 3\.2/Section 3.2/g' \
  -e 's/Phần 3\.3/Section 3.3/g' \
  -e 's/Phần 3\.4/Section 3.4/g' \
  -e 's/Phần 3\.5/Section 3.5/g' \
  -e 's/Phần 1/Chapter 1/g' \
  -e 's/Phần 2/Chapter 2/g' \
  -e 's/Phần 3/Chapter 3/g' \
  -e 's/Phần 4/Chapter 4/g' \
  -e 's/Phần 5/Chapter 5/g' \
  "$f"
```

Per-file Phần count (before Task 7 -> after Task 7):

| File | Before | After |
|------|--------|-------|
| content/en/_index.md | 1 | 0 |
| content/en/1-introduction/_index.md | 4 | 0 |
| content/en/2-preparation/_index.md | 13 | 0 |
| content/en/3-hands-on/3.1-knowledge-base/_index.md | 3 | 0 |
| content/en/3-hands-on/3.2-pipecat-local/_index.md | 5 (was 6, Task 4 prebaked 1) | 0 |
| content/en/4-cleanup/_index.md | 1 | 0 |
| content/en/5-summary/_index.md | 2 | 0 |
| **Total** | **29** | **0** |

(Pre-Phase-5-VERIFICATION baseline was 30; Task 4 dropped 1 in 3.2.)

vi-side files NOT modified. Verified by `git diff --stat content/vi/` showing zero changes from the Task 7 commit.

D-49 byte-parity exception explicitly documented: this commit is en-only because vi readers see `Phần` correctly. The DOC-12 file-count + slug-tree parity invariant is unchanged because no `_index.md` is added, deleted, renamed, or restructured — only body prose changes.

## Closing acceptance gate output

The 5-gate script from Task 8 ran inline before this SUMMARY was written:

```
ALL GATES PASSED — Phase 5 SC#1 + SC#2 unblocked, gaps closed.
```

Gate breakdown:

- **Gate 1 (SC#1 unblock):** `git ls-tree HEAD themes/` lists `hugo-theme-learn` 160000 entry; `themes/hugo-theme-learn/layouts/` exists; `branches: ["master"]` present in deploy.yml; no `branches: ["main"]` remnant.
- **Gate 2 (SC#2 unblock — instructor literals):** zero hits across `content/` for `851725411875|hera_agent-GIsf2P4ImD|BKXE19AH89|dg0w939ktclw6`.
- **Gate 2b (SC#2 unblock — Phần in en):** zero `Phần` tokens across `content/en/`.
- **Gate 3 (Parity invariant):** `bash bin/check-i18n-parity.sh` exits 0 (`vi=11, en=11; slug tree parity OK`).
- **Gate 4 (file-count parity):** `find content/vi -name _index.md | wc -l` = 11; `find content/en -name _index.md | wc -l` = 11.
- **Gate 5 (no emojis):** `grep -rP '[\x{1F300}-\x{1F9FF}]' content/` returns nothing.

## File-count parity (DOC-12)

This plan modifies existing chapter bodies and registers a submodule + edits a workflow line. No new content files. Final tree:

```
content/vi/_index.md
content/vi/1-introduction/_index.md
content/vi/2-preparation/_index.md
content/vi/3-hands-on/_index.md
content/vi/3-hands-on/3.1-knowledge-base/_index.md           <- modified (Task 3)
content/vi/3-hands-on/3.2-pipecat-local/_index.md            <- modified (Task 4)
content/vi/3-hands-on/3.3-deploy-agentcore/_index.md         <- modified (Task 5)
content/vi/3-hands-on/3.4-web-widget/_index.md
content/vi/3-hands-on/3.5-observability/_index.md            <- modified (Task 6)
content/vi/4-cleanup/_index.md
content/vi/5-summary/_index.md
                                                              (vi=11)
content/en/_index.md                                          <- modified (Task 7)
content/en/1-introduction/_index.md                           <- modified (Task 7)
content/en/2-preparation/_index.md                            <- modified (Task 7)
content/en/3-hands-on/_index.md
content/en/3-hands-on/3.1-knowledge-base/_index.md            <- modified (Tasks 3 + 7)
content/en/3-hands-on/3.2-pipecat-local/_index.md             <- modified (Tasks 4 + 7)
content/en/3-hands-on/3.3-deploy-agentcore/_index.md          <- modified (Task 5)
content/en/3-hands-on/3.4-web-widget/_index.md
content/en/3-hands-on/3.5-observability/_index.md             <- modified (Task 6)
content/en/4-cleanup/_index.md                                <- modified (Task 7)
content/en/5-summary/_index.md                                <- modified (Task 7)
                                                              (en=11)
```

`bash bin/check-i18n-parity.sh` exits 0:

```
OK: file count parity (vi=11, en=11)
OK: vi/en slug tree parity
check-i18n-parity: 2/2 parity assertions passed
OK: vi/en _index.md tree parity (DOC-12)
```

## Per-chapter redaction inventory

| Chapter | Placeholder(s) | Resolution command(s) cited |
|---------|----------------|------------------------------|
| 3.1 (Task 3) | `<your-kb-id>` | `terraform -chdir=infra/envs/prod output -raw kb_id` |
| 3.2 (Task 4) | `<your-kb-id>` | `terraform -chdir=infra/envs/prod output -raw kb_id` |
| 3.3 (Task 5) | `<your-account-id>`, `<your-runtime-id>`, `<your-distribution>` | `aws sts get-caller-identity --query Account --output text`; `jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json`; `terraform -chdir=infra/envs/prod output -raw widget_cloudfront_url` |
| 3.5 (Task 6) | `<your-runtime-id>` (inside bash block) | `jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json`; `terraform -chdir=infra/envs/prod output -raw observability_dashboard_url`; `aws cloudwatch get-dashboard --dashboard-name hera-prod --query DashboardArn --output text` |

## 05-01..05-04 plans untouched

`git log --oneline -- .planning/phases/05-workshop-documentation-vi-en/05-0[1-4]-PLAN.md` returns one commit (`8bd556d docs(05): create phase 5 plan (4 plans across 4 waves)`). No new commits touched the 4 prior plan files since 05-05 started.

## Deferred items carried forward

| Item | Reason | Tracked in |
|------|--------|------------|
| WR-01 — code-block byte-parity drift in 3.4-web-widget lines 117-118 (vi has Vietnamese bash comments vs en's English equivalents) | Surfaced as human_verification in 05-VERIFICATION.md, not as a closable gap. Decision required from operator (extend bin/check-i18n-parity.sh with a third byte-parity assertion OR accept the drift as low-impact prose). | 05-VERIFICATION.md human_verification item #4 |
| DOC-11 — operator screenshot sweep (6 PNGs across 5 chapters) | Already deferred per REQUIREMENTS.md DOC-11 Pending status; .gitkeep placeholders + image markdown references already in place. PNG capture requires live AWS console + manual annotation. | 04-HUMAN-UAT.md item #3 |
| First organic CI build of GitHub Pages workflow | Requires GitHub remote + Pages enabled + first push to triggering branch. Cannot be codified in a plan; only verified by human. | 05-VERIFICATION.md human_verification item #1 |
| First learner walkthrough end-to-end on the published Pages site | Requires real AWS account, real human reading workshop content, real microphone hardware, real Cost Explorer 24h propagation. Pure-code verification cannot test this. | 05-VERIFICATION.md human_verification item #2 |

## Threat surface scan

The plan introduces zero new IAM, zero AWS deploys, zero new network endpoints. The 6 STRIDE threats from the plan's `<threat_model>` carry the dispositions documented there:

- **T-05-05-01 Information Disclosure (mitigate):** the 14 instructor literals were the entire reason for this plan; closing audit confirms zero remain in `content/`. Tasks 3-6 implemented the mitigation.
- **T-05-05-02..T-05-05-06 (accept):** all inherent to the file-edit + git-submodule-add nature of the work; documented in plan, no new mitigations needed.

No new threat surface introduced beyond the redaction mitigation.

## Deviations from Plan

None - plan executed exactly as written. The 8 tasks landed in their specified order with no Rule 1/2/3 auto-fixes and no Rule 4 architectural decisions surfaced.

Notes:

- Task 1's `.gitmodules` was unchanged (already declared the entry); only the 160000 gitlink in HEAD was new. The plan explicitly anticipated this ("`.gitmodules` may be unchanged OR `git submodule add` may rewrite it with the same content; either outcome is fine").
- Task 4's en-side change to 3.2 line 297 pre-applied the `Section 3.3` rename per the plan's recommended choice; the per-file Phần count for that file dropped from 6 to 5 before Task 7's bulk sed. The plan explicitly anticipated and welcomed this idempotent overlap.

## Self-Check: PASSED

**File existence checks:**
- FOUND: themes/hugo-theme-learn/ (registered, 160000 gitlink to 3202533a)
- FOUND: themes/hugo-theme-learn/layouts/
- FOUND: themes/hugo-theme-learn/i18n/
- FOUND: .planning/phases/05-workshop-documentation-vi-en/05-05-SUMMARY.md (this file)

**Commit existence checks:**
- FOUND: 0ca6c7e (fix(05-05): register themes/hugo-theme-learn submodule (CR-01))
- FOUND: b0e3ea8 (fix(05-05): align deploy.yml trigger to active branch master)
- FOUND: 73a0f28 (fix(05-05): redact instructor KB id in Phần 3.1 vi+en (CR-02, D-49))
- FOUND: 9df0a6b (fix(05-05): redact instructor KB id in Phần 3.2 vi+en (CR-02, D-49))
- FOUND: 2c0634f (fix(05-05): redact instructor account/runtime/cloudfront in Phần 3.3 vi+en (CR-02, D-49))
- FOUND: d2d7446 (fix(05-05): redact instructor runtime+account in Phần 3.5 vi+en (CR-02, D-49))
- FOUND: fd121af (fix(05-05): rename Phần to Chapter/Section across content/en (WR-02, en-only D-49 exception))

**Gate checks (closing acceptance):**
- ALL GATES PASSED — Phase 5 SC#1 + SC#2 unblocked, gaps closed.
- bin/check-i18n-parity.sh exits 0 (vi=11, en=11; slug-tree parity OK)
- 0 instructor literals across content/
- 0 Phần tokens across content/en/
- vi=11, en=11 file-count parity unchanged
- 0 emojis across content/

**05-01..05-04 untouched:**
- `git log --oneline -- .planning/phases/05-workshop-documentation-vi-en/05-0[1-4]-PLAN.md` shows only the original 8bd556d commit — no new touches.
