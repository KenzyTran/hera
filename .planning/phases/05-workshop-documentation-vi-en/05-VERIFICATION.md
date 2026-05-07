---
phase: 05-workshop-documentation-vi-en
verified: 2026-05-07T06:25:53Z
status: human_needed
score: 3/5 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 2/5
  gaps_closed:
    - "CR-01: themes/hugo-theme-learn submodule unregistered — CLOSED (commit 0ca6c7e; gitlink 160000 -> 3202533a now in HEAD)"
    - "CR-02: 14 instructor literals in copy-paste blocks — CLOSED (commits 73a0f28/9df0a6b/2c0634f/d2d7446; zero grep hits for 851725411875|hera_agent-GIsf2P4ImD|BKXE19AH89|dg0w939ktclw6 across content/)"
    - "WR-02: 30 Phần tokens in content/en/ — CLOSED (commit fd121af; zero Phần hits across all 11 en _index.md files)"
  gaps_remaining: []
  regressions:
    - "WR-01 (WARNING, pre-existing): inconsistent placeholder name `<your-account>` vs `<your-account-id>` on 3.3 line 134 in both vi+en — introduced by CR-02 redaction, not by prior content. Learner doing copy-paste search for resolution instructions won't find a match. One-line fix in vi+en per REVIEW.md WR-01. Classified as WARNING; does not block the phase goal because the reference-values block 27 lines below cites the correct `<your-account-id>` placeholder name."
    - "WR-02 (WARNING, pre-existing from REVIEW.md): `<your-fn-url>` placeholder in 3.3 smoke-output block has no resolution command in the Reference values list. REVIEW.md recommends adding a sixth bullet citing `terraform -chdir=infra/envs/prod output -raw presign_url`. Classified as WARNING; does not block phase goal (the `presign_url` output is described elsewhere in the same chapter and in 3.4)."
deferred:
  - truth: "DOC-11 — copy-paste code snippets + annotated AWS console screenshots present in every chapter"
    addressed_in: "Phase 5 follow-up operator sweep"
    evidence: "REQUIREMENTS.md DOC-11 row: 'Pending (operator PNG capture sweep deferred — chapter markdown image refs in place)'. Five image markdown refs inserted at correct locations; .gitkeep placeholders track directories. Hugo renders alt-text-only fallback until PNGs land. Explicitly tracked in 04-HUMAN-UAT.md item #3 and ROADMAP Phase 5 row."
human_verification:
  - test: "First organic CI build of the GitHub Pages workflow"
    expected: "Workflow fires on push to master: Install Hugo CLI -> Checkout (submodules: recursive fetches themes/hugo-theme-learn at sha 3202533a) -> Check vi/en parity (DOC-12, exits 0) -> Setup Pages -> Build with Hugo (theme resolves; all 22 bilingual _index.md rendered) -> Upload artifact -> Deploy. Final Pages URL serves all 11 chapters in both Vietnamese and English with language switcher navigating between /vi/ and /en/ trees."
    why_human: "CI build runs on GitHub-hosted infrastructure, requires push to a configured remote, and requires GitHub Pages enabled on the repository. No remote is currently configured (git remote -v is empty). This cannot be verified by static codebase inspection alone. The codebase artifacts — submodule gitlink, deploy.yml trigger on master, parity gate wired before Hugo build — are all correct; the first organic build is the only remaining blocker for SC#1 to be fully observable."
  - test: "First learner walkthrough end-to-end from a fresh AWS account on the published Pages site"
    expected: "A Cloud Clubs member with no prior knowledge of this repo lands on the published Pages URL, follows Chapter 1 -> Chapter 2 -> Section 3.1-3.5 -> Chapter 4 -> Chapter 5 in either Vietnamese or English. Copy-pastes snippets (all instructor literals now replaced with `<your-*>` placeholders + resolution commands), captures screenshots where prompted, deploys their own KB + AgentCore + widget, talks to the agent through HTTPS browser, tears down to verified $0 ongoing cost (via Cost Explorer 24h post-destroy + bin/cleanup-verify.sh all-green)."
    why_human: "Requires real AWS account, real human reading workshop content, real microphone hardware, real Cost Explorer 24h propagation. Pure-code verification cannot test 'a fresh learner reaches the working voice loop end-to-end'. SC#2 and SC#3 are inherently human-verifiable; the static content that gates them (instructor data redacted, Phần tokens gone) is now confirmed clean."
  - test: "Operator screenshot sweep to close DOC-11 (6 PNGs across 5 chapters)"
    expected: "Operator captures and annotates per D-44 (red box + arrow + label): (a) static/images/2-preparation/console-bedrock-model-access.png, (b) static/images/3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png, (c) static/images/3.4-web-widget/widget-idle-state.png, (d) static/images/3.5-observability/billing-alerts-toggle.png, (e) static/images/3.5-observability/cloudwatch-dashboard-hera-prod.png, (f) static/images/4-cleanup/cleanup-verify-output.png. Hugo renders proper image elements after PNGs land; DOC-11 flips to Complete in REQUIREMENTS.md."
    why_human: "AWS Console UI screenshots cannot be auto-generated; require live AWS login + manual capture + annotation. Already tracked in 04-HUMAN-UAT.md item #3 and REQUIREMENTS.md DOC-11 Pending."
  - test: "Code-block byte-parity drift in 3.4-web-widget (WR-01 from prior REVIEW — operator decision required)"
    expected: "Operator decides between (a) reverting vi bash comments at content/vi/3-hands-on/3.4-web-widget/_index.md lines 117-118 to English and optionally extending bin/check-i18n-parity.sh with a third fenced-block parity assertion, OR (b) accepting the drift as low-impact prose comment translation (D-50 minimal-parity-only stance retained)."
    why_human: "Extends a judgment call that predates 05-05. D-50 explicitly rejected per-section heading parity to avoid false positives; code-block byte parity is the same class of judgment call. Operator must decide whether the D-49 byte-parity invariant is enforced strictly for bash comments inside fences, or treated as a soft convention for prose-only drift. Neither path blocks the phase goal; this is a quality/convention decision."
---

# Phase 5: Workshop Documentation (vi/en) Verification Report

**Phase Goal:** A Cloud Clubs member who has never seen this repo can land on the GitHub Pages workshop site, follow Phần 1-5 in either Vietnamese or English, and end with their own voice chatbot running in their own AWS account that they can talk to through their own browser — and then tear it back down to zero cost.

**Verified:** 2026-05-07T06:25:53Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure (Plan 05-05 closed CR-01 + CR-02 + WR-02)

## Goal Achievement

All three blockers from the prior `gaps_found` verification are now closed by confirmed codebase evidence. The remaining items routed to human verification are inherent to the nature of the success criteria (live CI build on remote infrastructure, end-to-end learner walkthrough with real AWS resources, operator screenshot capture) — not defects in the shipped content.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | All 5 chapters published in vi+en on the GitHub Pages site, with language switcher and slugs matching across both trees | VERIFIED (code-side) / HUMAN for organic build | **Submodule:** `git ls-tree HEAD themes/` returns `160000 commit 3202533a746f91c67de1a8fa373c0328ec1b403d themes/hugo-theme-learn`. `git submodule status` returns `3202533a...` `(2.5.0-27-g3202533)`. `themes/hugo-theme-learn/layouts/` and `themes/hugo-theme-learn/i18n/` exist on disk — CR-01 CLOSED. **Parity:** `bin/check-i18n-parity.sh` exits 0 — `vi=11, en=11; 2/2 assertions passed`. **Config:** `config.toml` declares `theme = "hugo-theme-learn"`, `[languages.vi]` and `[languages.en]` with matching `contentDir`. **Deploy trigger:** `deploy.yml` line 5 reads `branches: ["master"]` — aligned to active branch. **Organic CI build** must still be confirmed by a human after pushing to a configured remote with GitHub Pages enabled. |
| 2 | A fresh learner who reads only Phần 2 + Phần 3 successfully deploys Phase 1-3 system end-to-end | VERIFIED (content) / HUMAN for walkthrough | Content covers full deployment path. **CR-02 CLOSED:** `grep -rc '851725411875\|hera_agent-GIsf2P4ImD\|BKXE19AH89\|dg0w939ktclw6' content/` returns zero hits across all 22 files. **WR-02 CLOSED:** `grep -rc "Phần" content/en/` returns zero hits across all 11 en files. All 4 instructor-private values replaced with `<your-*>` placeholders + resolution commands cited inline. **WARNING:** REVIEW.md WR-01 notes `<your-account>` on 3.3 line 134 vs `<your-account-id>` in the reference block (same value, inconsistent name). REVIEW.md WR-02 notes `<your-fn-url>` has no resolution command in the Reference values list. Neither blocks the learner from deploying (the value and resolution path exist elsewhere). Real walkthrough is human-only. |
| 3 | After Phần 4 Cleanup, learner verifies via Cost Explorer + verification script that they have $0 ongoing cost | UNCERTAIN (human required) | Chapter 4 Cleanup ships: `cdk destroy hera-agentcore --force` + `terraform destroy` + `bash bin/cleanup-verify.sh` (19 read-only checks) + 24h-deferred Cost Explorer paste-line per D-38 + ECR force-delete fallback + CloudFront 15-30min disable-then-delete warning. Content is correct and unchanged from prior verification pass. Real teardown requires a human running through the actual AWS deployment. |
| 4 | Each chapter contains relevant top-N pitfall callouts at the trigger moment, plus copy-clean code snippets | VERIFIED | 8/8 D-51 pitfall callouts placed across chapters (8 > "top 5-7" target). All 4 instructor literals replaced per CR-02 (zero grep hits). `{{% notice %}}` shortcode pairs are balanced in every reviewed file per REVIEW.md re-check. 19 unique source-footer paths cited via D-42 italic `*Source:*` footer. Note: DOC-11 screenshots remain deferred (operator sweep). |
| 5 | CI enforces vi/en parity on every PR — parity script fails if chapters diverge | VERIFIED | `bin/check-i18n-parity.sh` (66 lines, executable): 2 assertions (file-count parity + bidirectional slug-tree parity). Wired into `.github/workflows/deploy.yml` line 38-39 as `Check vi/en parity (DOC-12)` step between Checkout and Setup Pages. Live run: exits 0 — `OK: file count parity (vi=11, en=11)` + `OK: vi/en slug tree parity`. Prior synthetic mismatch test (Plan 05-01) confirmed exit 1 with diff list on injected mismatch. |

**Score:** 3/5 truths fully verified in codebase; Truths 1-2 pass the code-level checks but have inherent human-verification tails (organic CI build; real learner walkthrough); Truth 3 is human-only by nature. Truths 4-5 are fully VERIFIED. No remaining FAILED or BLOCKER items.

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | DOC-11 — annotated AWS console screenshots in every chapter | Phase 5 follow-up operator sweep | REQUIREMENTS.md DOC-11: "Pending (operator PNG capture sweep deferred — chapter markdown image refs in place)". Five image markdown refs inserted at correct locations in chapters 2, 3.3, 3.4, 3.5, 4. Five `.gitkeep` placeholders ship. Hugo renders alt-text-only until PNGs land. Tracked in 04-HUMAN-UAT.md item #3. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `themes/hugo-theme-learn` | Registered submodule gitlink in HEAD; layouts + i18n dirs present after checkout | VERIFIED | `git ls-tree HEAD themes/` = `160000 commit 3202533a...`. `themes/hugo-theme-learn/layouts/` exists. `themes/hugo-theme-learn/i18n/` exists. Pinned at upstream sha `3202533a746f91c67de1a8fa373c0328ec1b403d` (matcornic 2.5.0-27-g3202533). CR-01 CLOSED. |
| `.github/workflows/deploy.yml` | Pre-build parity gate wired; branch trigger matches active branch | VERIFIED | Line 5: `branches: ["master"]` (aligned to active branch `master`; no stray `main` anywhere in the file). Line 38-39: `bash bin/check-i18n-parity.sh` between Checkout and Setup Pages. `actions/checkout@v4` with `submodules: recursive` so submodule is fetched automatically on CI. YAML parses cleanly. INFO: no remote configured yet; first organic build requires operator to push. |
| `bin/check-i18n-parity.sh` | DOC-12 file-count + slug-tree parity gate, executable, exits 0 on parity | VERIFIED | 66 lines, executable, syntax clean. Two assertions: file-count + bidirectional slug-tree. Live: exits 0 (`vi=11, en=11; 2/2 assertions passed`). |
| `.gitmodules` | Declares `themes/hugo-theme-learn` path + URL | VERIFIED | Single entry: `path = themes/hugo-theme-learn`, `url = https://github.com/matcornic/hugo-theme-learn.git`. Syntactically valid. |
| `config.toml` | Hugo site config with real Hera values; no FCJ template placeholders | VERIFIED | `baseURL = "https://KenzyTran.github.io/hera/"`, `theme = "hugo-theme-learn"`, `[languages.vi]` + `[languages.en]` both declared. Zero FCJ template placeholders. |
| `content/vi/_index.md` + `content/en/_index.md` | Root overview pages; no Phần in en | VERIFIED | vi=29 lines, en=29 lines. `grep -c "Phần" content/en/_index.md` = 0. |
| `content/{vi,en}/1-introduction/_index.md` | Phần 1 single-page; Mermaid diagrams; bilingual-parity callout | VERIFIED | vi=116, en=117 lines. 4 former Phần tokens renamed to `Chapter N` / `Section N.Y` across en file. Zero Phần hits. |
| `content/{vi,en}/2-preparation/_index.md` | Phần 2 single-page; AWS account checklist; cost estimate | VERIFIED | vi=159, en=159 lines. 13 former Phần tokens renamed. Zero Phần hits. |
| `content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md` | KB deploy; BKXE19AH89 redacted | VERIFIED | `BKXE19AH89` replaced with `<your-kb-id>` + resolution command `terraform -chdir=infra/envs/prod output -raw kb_id` on same line. Zero grep hits for `BKXE19AH89` across content/. |
| `content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md` | Pipecat local; BKXE19AH89 redacted | VERIFIED | `BKXE19AH89` replaced with `<your-kb-id>` + resolution command. 6→0 Phần tokens in en file. Zero grep hits for KB id. |
| `content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md` | AgentCore deploy; account/runtime/CloudFront redacted | VERIFIED with WARNING | `851725411875` → `<your-account-id>`, `hera_agent-GIsf2P4ImD` → `<your-runtime-id>`, `dg0w939ktclw6.cloudfront.net` → `<your-distribution>.cloudfront.net`. Each placeholder has a resolution command on the same line. **WARNING (REVIEW WR-01):** line 134 smoke-output block uses `<your-account>` (short form) vs `<your-account-id>` elsewhere — inconsistent name. **WARNING (REVIEW WR-02):** `<your-fn-url>` placeholder on line 133 has no resolution command in the Reference values list. Neither blocks deployment. |
| `content/{vi,en}/3-hands-on/3.5-observability/_index.md` | Observability; runtime+account redacted | VERIFIED | `hera_agent-GIsf2P4ImD` replaced with `<your-runtime-id>` inside bash block + resolution command comment. `851725411875` replaced with self-contained resolution path. Zero grep hits for both literals. |
| `content/{vi,en}/3-hands-on/3.4-web-widget/_index.md` | Widget; HTTPS-for-mic callout | VERIFIED (WARNING carried) | Content unchanged from prior verified state. D-51 #4 HTTPS-for-mic callout present. **WARNING (carry-forward from WR-01 in prior REVIEW):** vi bash comments on lines 117-118 differ from en equivalents — code-block byte-parity drift; bin/check-i18n-parity.sh does not catch this. Operator decision pending (human_verification item #4). |
| `content/{vi,en}/4-cleanup/_index.md` | Cleanup quy trinh; 1 Phần in en renamed | VERIFIED | 1 former `Phần 4` token in en renamed to `Chapter 4`. Zero Phần hits. |
| `content/{vi,en}/5-summary/_index.md` | Summary; 2 Phần in en renamed | VERIFIED | 2 former Phần tokens renamed. Zero Phần hits. |
| `static/images/*/gitkeep` | Directory placeholders for deferred PNG sweep (DOC-11) | VERIFIED | 5 `.gitkeep` files in static/images/{2-preparation,3.3-deploy-agentcore,3.4-web-widget,3.5-observability,4-cleanup}/. PNGs deferred per DOC-11 Pending status. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `.github/workflows/deploy.yml` | `bin/check-i18n-parity.sh` | `run: bash bin/check-i18n-parity.sh` (line 38-39) | WIRED | Step executes before Hugo build step. Live: exits 0 on current tree. |
| `.github/workflows/deploy.yml` | `themes/hugo-theme-learn` | `actions/checkout@v4` with `submodules: recursive` | WIRED | Checkout step will fetch the registered submodule at sha `3202533a`. Build step downstream passes `theme = "hugo-theme-learn"` from config.toml. |
| `config.toml` | `themes/hugo-theme-learn` | `theme = "hugo-theme-learn"` + registered gitlink | WIRED | config.toml line 3 declares the theme; gitlink `160000 commit 3202533a...` in HEAD ensures `actions/checkout --submodules recursive` fetches it. CR-01 CLOSED. |
| `config.toml [languages.vi/en]` | `content/vi/`, `content/en/` | `contentDir = "content/vi"` / `"content/en"` | WIRED | Both languages declared with correct contentDir; 11 _index.md per side confirmed by `find`. Language switcher will render correctly once the Hugo build succeeds organically. |
| `content/{vi,en}/*/` | `bin/<script>.sh` / RUNBOOK.md sections | D-42 italic `*Source:*` footers in chapter bodies | WIRED | 19 unique repo-relative source paths cited across chapters. Per-chapter footer counts per prior verified state. |
| `content/en/3-hands-on/*/` | English-only prose (no Vietnamese vocabulary) | WR-02 Phần rename (commit fd121af) | WIRED | `grep -rc "Phần" content/en/` returns 0 across all 11 en files. English-track learner reads `Chapter X` / `Section X.Y` consistently. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `bin/check-i18n-parity.sh` | `VI_COUNT`, `EN_COUNT`, `VI_SLUGS`, `EN_SLUGS` | `find content/{vi,en} -name "_index.md" -type f` | Yes — returns 11 per side on disk | FLOWING |
| `.github/workflows/deploy.yml` Build with Hugo | `theme = "hugo-theme-learn"` from config.toml | `actions/checkout@v4 submodules: recursive` fetches `themes/hugo-theme-learn` at sha `3202533a` | Yes — theme files exist (layouts/, i18n/, etc.) | FLOWING (pending organic CI build) |
| Chapter image markdown refs | PNG filenames | `static/images/<chapter>/<filename>.png` | No — only `.gitkeep` placeholders ship; 5 image markdown refs render alt-text-only fallback | STATIC (deferred per DOC-11) |
| `content/*/3.3-deploy-agentcore/_index.md` — `<your-*>` placeholders | Learner's own account/runtime/distribution values | Resolution commands cited inline (`aws sts get-caller-identity`, `jq`, `terraform output`) | Yes — resolution commands produce real values from learner's deploy | FLOWING (resolution path defined; WARNING on `<your-account>` vs `<your-account-id>` naming inconsistency and missing `<your-fn-url>` resolution bullet) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Parity script exits 0 against current tree | `bash bin/check-i18n-parity.sh` | `2/2 parity assertions passed; vi=11 en=11` | PASS |
| Submodule registered in HEAD git tree | `git ls-tree HEAD themes/` | `160000 commit 3202533a746f91c67de1a8fa373c0328ec1b403d themes/hugo-theme-learn` | PASS |
| Submodule status reports sha | `git submodule status` | `3202533a... themes/hugo-theme-learn (2.5.0-27-g3202533)` | PASS |
| Theme directories present on disk | `test -d themes/hugo-theme-learn/layouts && test -d themes/hugo-theme-learn/i18n` | Both exist | PASS |
| Zero instructor literal leakage | `grep -rc '851725411875\|hera_agent-GIsf2P4ImD\|BKXE19AH89\|dg0w939ktclw6' content/` | 0 across all 22 files | PASS |
| Zero Phần tokens in content/en/ | `grep -rc "Phần" content/en/` | 0 across all 11 en files | PASS |
| Deploy.yml branch trigger aligned | `grep 'branches:' .github/workflows/deploy.yml` | `branches: ["master"]` (active branch) | PASS |
| No emojis in content tree | `grep -rP '[\x{1F300}-\x{1F9FF}]' content/` | No output | PASS |
| vi file count | `find content/vi -name _index.md \| wc -l` | 11 | PASS |
| en file count | `find content/en -name _index.md \| wc -l` | 11 | PASS |
| Hugo build (organic CI) | Requires push to GitHub remote with Pages enabled | N/A — no remote configured | SKIP — routed to human verification item #1 |
| Learner walkthrough end-to-end | Requires real AWS account + microphone | N/A | SKIP — inherently human; routed to human verification item #2 |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DOC-01 | 05-01 | Phần 1 Introduction (vi+en) — voice AI, Nova Sonic, why AgentCore, hera high-level diagram | SATISFIED | content/{vi,en}/1-introduction/_index.md (116/117 lines). 2 Mermaid blocks (component flowchart + sequence diagram), bilingual-parity callout (D-51 #7), folded prereqs H2 (D-53 Option A), region note (D-47). 4 Phần tokens renamed to Chapter N / Section N.Y in en file. |
| DOC-02 | 05-02 | Phần 2 Preparation (vi+en) — AWS account checklist + model access + tool installs + credentials + cost | SATISFIED | content/{vi,en}/2-preparation/_index.md (159/159 lines). Bedrock model access steps, tool installs, D-54 `~$2-5 USD/2-hour` cost ballpark, D-51 #3 model-access pitfall callout, D-44 #1 image ref. 13 Phần tokens renamed in en file. Zero Phần hits. |
| DOC-03 | 05-02 | Phần 3.1 Knowledge Base (vi+en) — terraform apply + ingestion + verify + re-index | SATISFIED | content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md (143/143 lines). BKXE19AH89 redacted to `<your-kb-id>` with resolution command. D-51 #8 KB sync delay callout placed. 6 D-42 source footers per language. |
| DOC-04 | 05-02 | Phần 3.2 Pipecat Local (vi+en) — code structure + system prompt + tool definition + run local test | SATISFIED | content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md (321/321 lines). BKXE19AH89 redacted. 3 D-51 callouts (#1/#2/#6). 13 source footers per language. 6 Phần tokens renamed in en file. |
| DOC-05 | 05-03 | Phần 3.3 Deploy AgentCore (vi+en) — build container + push ECR + deploy AgentCore + verify endpoint | SATISFIED with WARNING | content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md (181/181 lines). Account/runtime/CloudFront redacted. Reference values block cites resolution commands. WARNING: `<your-account>` naming inconsistency on line 134 (REVIEW WR-01) + missing `<your-fn-url>` resolution bullet (REVIEW WR-02). Does not block deployment. |
| DOC-06 | 05-03 | Phần 3.4 Web Widget (vi+en) — HTML/JS + browser microphone + AgentCore endpoint + S3+CloudFront deploy | SATISFIED with WARNING | content/{vi,en}/3-hands-on/3.4-web-widget/_index.md (148/148 lines). D-51 #4 HTTPS-for-mic callout placed. WARNING: vi bash comments on lines 117-118 differ from en equivalents (code-block byte-parity drift, D-49; operator decision pending). |
| DOC-07 | 05-03 | Phần 3.5 Observability (vi+en) — CloudWatch dashboard walk-through + alarm setup | SATISFIED | content/{vi,en}/3-hands-on/3.5-observability/_index.md (119/119 lines). Runtime ID + account redacted. D-51 #5 billing 24h propagation callout placed. D-35/D-36 trade-offs documented. |
| DOC-08 | 05-04 | Phần 4 Cleanup (vi+en) — terraform destroy + manual checks + verification script | SATISFIED | content/{vi,en}/4-cleanup/_index.md (147/148 lines). cdk destroy + terraform destroy + bin/cleanup-verify.sh + 24h Cost Explorer paste-line. 1 Phần token renamed in en file. Zero Phần hits. |
| DOC-09 | 05-04 | Phần 5 Summary (vi+en) — cost recap + Twilio/multi-language/multi-agent expansion roadmap | SATISFIED | content/{vi,en}/5-summary/_index.md (82/82 lines). What-you-built recap + cost recap + DOC-09 expansion roadmap. 2 Phần tokens renamed in en file. Zero Phần hits. |
| DOC-10 | 05-01..05-03 | Top 5-7 pitfall callouts at the trigger moment in chapters | SATISFIED | All 8 D-51 callouts placed (8 > "top 5-7" literal target): #1 8-min stream cap (3.2), #2 sample rate (3.2), #3 model access (2), #4 HTTPS-for-mic (3.4), #5 billing 24h (3.5), #6 tool-use schema (3.2), #7 bilingual parity (1), #8 KB sync delay (3.1). 14+14 `{{% notice %}}` shortcodes balanced per REVIEW.md re-check. |
| DOC-11 | (none) | Each chapter has code snippet copy button + screenshot AWS console with annotation | DEFERRED | Chapter image markdown refs in place (5 PNG paths referenced); 5 `.gitkeep` placeholders ship; hugo-theme-learn auto-provides copy-button for fenced code blocks once the theme resolves. PNGs deferred to operator sweep. Tracked Pending in REQUIREMENTS.md DOC-11 row + ROADMAP Phase 5 row + 04-HUMAN-UAT.md item #3. |
| DOC-12 | 05-01 | vi/en parity check runs in CI; fails if chapters diverge | SATISFIED | bin/check-i18n-parity.sh (66 lines, executable) wired into deploy.yml line 38. Live exits 0 (vi=11 en=11). Prior synthetic mismatch confirmed exits 1. |

**Coverage:** 11/12 SATISFIED + 1/12 DEFERRED. No ORPHANED requirements. DOC-05 and DOC-06 carry low-severity warnings from REVIEW.md (placeholder naming inconsistency and code-block byte-parity drift) that do not prevent the goal from being achieved.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md` | 134 | `<your-account>` (short form) vs `<your-account-id>` used 27 lines later in reference values block for same value | WARNING | Learner searching for the resolution command for `<your-account>` will not find a hit — the reference uses `<your-account-id>`. One-line fix per REVIEW.md WR-01. |
| `content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md` | 133 | `<your-fn-url>` placeholder has no resolution command in the Reference values section | WARNING | Learner who did not run `bin/smoke-deploy.sh` directly sees a placeholder with no cited resolution path. Resolution exists elsewhere in the chapter (line 122 + 3.4 chapter) but not in the canonical reference list. REVIEW.md WR-02 provides the exact fix text. |
| `content/{vi,en}/3-hands-on/3.4-web-widget/_index.md` | 117-118 | vi bash comments differ from en (`mở trong browser desktop...` vs English equivalents) — D-49 code-block byte-parity invariant drift | WARNING | `bin/check-i18n-parity.sh` does not assert byte-parity (only file-count + slug-tree); silent drift. Operator decision required: extend script or accept drift. |
| `static/images/*/gitkeep` | N/A | 5 PNG files referenced in markdown but only `.gitkeep` placeholders ship | INFO (deferred per DOC-11) | Hugo renders alt-text-only fallback. Chapters publishable without PNGs. PNG drop tracked in 04-HUMAN-UAT.md. |
| `.github/workflows/deploy.yml` | 5 | `branches: ["master"]` works for current state but will need updating if a GitHub Pages `main` branch convention is adopted later | INFO | No remote configured yet; first publish requires operator action. Per REVIEW.md IN-01, no action required for v1. |

### Human Verification Required

#### 1. First organic CI build of the GitHub Pages workflow

**Test:** Configure a GitHub remote, enable GitHub Pages on the repository, and push the current `master` branch. Wait for the GitHub Actions workflow to run.
**Expected:** Workflow completes all 6 steps in order:
1. Install Hugo CLI (v0.139.4 extended)
2. Checkout with `submodules: recursive` — fetches `themes/hugo-theme-learn` at sha `3202533a`
3. Check vi/en parity (DOC-12) — exits 0 (`vi=11, en=11`)
4. Setup Pages
5. Build with Hugo — theme resolves from `themes/hugo-theme-learn`; all 22 bilingual `_index.md` are rendered; language switcher navigates between `/vi/` and `/en/` trees
6. Upload artifact + Deploy to GitHub Pages URL

**Why human:** CI runs on remote infrastructure; requires a configured remote, branch push, and GitHub Pages enabled. The codebase artifacts are all correct (submodule registered, trigger aligned to `master`, parity gate wired). The first organic build is the only remaining observable step for SC#1.

#### 2. First learner walkthrough end-to-end on the published Pages site

**Test:** A Cloud Clubs member with no prior knowledge of this repo lands on the published GitHub Pages URL and follows the workshop:
- Chapter 1 Introduction (either language)
- Chapter 2 Preparation: enables Bedrock model access, installs tools, configures credentials
- Section 3.1: deploys KB via Terraform, verifies Retrieve API
- Section 3.2: runs Pipecat local test, passes AGT-04 latency gate
- Section 3.3: builds/pushes container to ECR, deploys AgentCore via CDK, runs bin/smoke-deploy.sh
- Section 3.4: deploys web widget to S3+CloudFront, opens browser, talks to voice agent
- Section 3.5: views CloudWatch dashboard, confirms alarms active
- Chapter 4: runs `cdk destroy` + `terraform destroy` + `bin/cleanup-verify.sh` (all-green), waits 24h for Cost Explorer
- Chapter 5: reviews cost recap

**Expected:** Learner successfully deploys their own voice chatbot, hears the Sonic response through their browser, then tears down to verified $0 ongoing cost. All `<your-*>` placeholders resolve correctly from the cited CLI commands.

**Why human:** Requires real AWS account, real microphone hardware, real 24h Cost Explorer propagation. SC#2 and SC#3 are inherently human-verifiable.

#### 3. Operator screenshot sweep to close DOC-11

**Test:** Operator captures and annotates (per D-44: red box + arrow + label) 6 PNGs:
1. `static/images/2-preparation/console-bedrock-model-access.png`
2. `static/images/3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png`
3. `static/images/3.4-web-widget/widget-idle-state.png`
4. `static/images/3.5-observability/billing-alerts-toggle.png`
5. `static/images/3.5-observability/cloudwatch-dashboard-hera-prod.png`
6. `static/images/4-cleanup/cleanup-verify-output.png`

**Expected:** Hugo renders proper image elements after PNGs land; chapters lose alt-text-only fallback. DOC-11 flips to Complete in REQUIREMENTS.md and ROADMAP Phase 5 row.

**Why human:** AWS Console UI screenshots cannot be auto-generated; require live AWS login + manual capture + annotation. Tracked in 04-HUMAN-UAT.md item #3 and REQUIREMENTS.md DOC-11 Pending.

#### 4. Two REVIEW.md warnings in 3.3-deploy-agentcore (WR-01 + WR-02 from code review)

**Test A (WR-01):** On line 134 of both `content/en/3-hands-on/3.3-deploy-agentcore/_index.md` and `content/vi/3-hands-on/3.3-deploy-agentcore/_index.md`, rename `<your-account>` to `<your-account-id>` to match the reference-values block on line 161. Apply identically in vi+en per D-49.

**Test B (WR-02):** In the "Reference values (resolve from your own deploy)" section of both 3.3 files, add a sixth bullet after line 165:
- en: `- Presign URL: \`https://<your-fn-url>.lambda-url.ap-northeast-1.on.aws/\` — resolve via \`terraform -chdir=infra/envs/prod output -raw presign_url\` after Step 3.5 second-pass apply.`
- vi: same with "resolve qua" phrasing

**Expected:** Learner searching for `<your-account>` resolution finds the cited command. Learner seeing `<your-fn-url>` in the smoke output finds the resolution bullet without having to cross-reference.

**Why human:** Two-line editorial fix touching vi+en files; operator should confirm the resolution command (`terraform output -raw presign_url`) matches the actual Terraform output name in `infra/envs/prod/outputs.tf` before committing, and decide whether to bundle with a future commit or add a new atomic commit.

#### 5. Code-block byte-parity drift in 3.4-web-widget (D-49 invariant decision — operator judgment)

**Test:** Inspect `content/vi/3-hands-on/3.4-web-widget/_index.md` lines 117-118 vs the corresponding en file. vi has Vietnamese bash comments (`mở trong browser desktop...`, `cho phép microphone access`); en has English equivalents. `bin/check-i18n-parity.sh` does not catch this (asserts file-count + slug-tree only).

**Expected decision:** Either (a) revert vi bash comments to English so the fenced block is byte-identical between vi+en per the D-49 spirit, and optionally extend bin/check-i18n-parity.sh with a third assertion that diffs fenced-block projections; OR (b) document the operator's decision that prose comments inside bash fences are excluded from the byte-parity invariant and the D-50 minimal-parity-only stance is retained.

**Why human:** This is a convention judgment call. D-50 explicitly rejected per-section heading parity to avoid false positives; code-block comment parity is the same category. The content is publishable either way; the drift is low-impact (bash comment only, not a runnable command). Operator must decide whether the D-49 invariant is enforced strictly for bash comments inside fences, or treated as a soft convention.

### Gaps Summary

There are **no remaining blocking gaps** from the prior `gaps_found` verification. All three blockers are closed by confirmed codebase evidence:

- **CR-01 CLOSED:** `git ls-tree HEAD themes/` returns `160000 commit 3202533a...`. Hugo build will resolve the theme on first organic CI run. Layouts and i18n directories present on disk after submodule initialization.
- **CR-02 CLOSED:** `grep -rc '851725411875|hera_agent-GIsf2P4ImD|BKXE19AH89|dg0w939ktclw6' content/` returns zero hits across all 22 files. All 4 instructor-private values replaced with `<your-*>` placeholders and resolution commands cited inline per the "placeholder + resolution-command" pattern.
- **WR-02 CLOSED:** `grep -rc "Phần" content/en/` returns zero hits across all 11 en `_index.md` files. 29 tokens (30 original minus 1 pre-applied in Task 4) renamed to `Chapter X` or `Section X.Y` across 7 en files in a single atomic en-only commit per D-49 exception.

**Remaining items routed to human verification (not gaps):**
1. First organic CI build (SC#1 observable completion — requires GitHub remote + Pages enabled)
2. First learner walkthrough end-to-end (SC#2 + SC#3 — inherently human-only)
3. Operator screenshot sweep (DOC-11 — operator-deferred per REQUIREMENTS.md)
4. Two editorial improvements in 3.3 chapter per REVIEW.md WR-01 + WR-02 (WARNING severity, not phase-blocking)
5. Code-block byte-parity drift in 3.4-web-widget (WR-01 from prior REVIEW — convention judgment call)

**Status rationale:** `human_needed` (not `passed`) because SC#1 (organic CI build and published site) and SC#2 (fresh learner walkthrough) inherently require human action. These are not defects — the static codebase ships everything needed for those success criteria to be observable. The phase goal is reachable; it cannot be fully declared `passed` until the first organic CI build runs and a learner confirms the walkthrough.

---

_Verified: 2026-05-07T06:25:53Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification: Yes — after gap closure Plan 05-05 (CR-01 submodule + CR-02 instructor data + WR-02 Phần rename)_
