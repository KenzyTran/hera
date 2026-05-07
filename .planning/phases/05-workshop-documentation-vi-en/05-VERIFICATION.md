---
phase: 05-workshop-documentation-vi-en
verified: 2026-05-07T12:30:00Z
status: gaps_found
score: 2/5 must-haves verified
overrides_applied: 0
re_verification:
  is_re_verification: false
gaps:
  - truth: "All five chapters published in both Vietnamese and English on the existing GitHub Pages site"
    status: failed
    reason: "Hugo theme submodule themes/hugo-theme-learn is declared in .gitmodules but is NOT registered in HEAD git tree (no gitlink commit-pointer entry). git ls-tree HEAD returns no themes entry, git submodule status returns empty, and themes/hugo-theme-learn/ is an empty directory. CI Hugo build (.github/workflows/deploy.yml step `Build with Hugo`) will fail with 'theme not found' the first time the workflow runs against branch 'main' — the published GitHub Pages site has therefore never built and the literal phase goal (learner can land on the published site) cannot be met. This is a pre-existing repo state predating Phase 5, but Phase 5 wired the parity gate ahead of this broken build path so the gate now sits in front of a build that cannot succeed."
    artifacts:
      - path: "themes/hugo-theme-learn/"
        issue: "Empty directory; not a real submodule checkout. git ls-tree HEAD themes returns nothing."
      - path: ".gitmodules"
        issue: "Declares submodule path themes/hugo-theme-learn pointing at https://github.com/matcornic/hugo-theme-learn.git but no matching gitlink (160000 entry) ever committed to HEAD."
      - path: ".github/workflows/deploy.yml"
        issue: "Step `actions/checkout@v4` with submodules: recursive cannot fetch a submodule that is not registered in the tree. Build step downstream of parity gate will fail."
    missing:
      - "Properly register themes/hugo-theme-learn as a real submodule: rm -rf themes/hugo-theme-learn && git submodule add https://github.com/matcornic/hugo-theme-learn.git themes/hugo-theme-learn && git commit"
      - "Verify with git ls-tree HEAD themes/ — must list a 160000 commit entry, not empty."
      - "Verify with git submodule status — must list themes/hugo-theme-learn with a sha"
      - "Confirm deploy.yml triggers on the active branch (currently triggers on 'main' but the working branch is 'master' and there is no remote — the workflow will not run until a remote is added and the branch alignment is fixed; surface this for operator decision in the same closure plan if not already in scope)"
  - truth: "Workshop content does not embed live instructor account state that learners would copy-paste verbatim"
    status: failed
    reason: "Workshop chapters publish concrete instructor account state in copy-paste blocks: AWS account ID 851725411875 (5 occurrences across 4 files), AgentCore runtime ID hera_agent-GIsf2P4ImD inside `aws bedrock-agentcore-control update-agent-runtime --agent-runtime-id ...` paste-block (3.5 chapter), KB ID BKXE19AH89 inside literal `Live result measured at ... KB BKXE19AH89` lines (3.1 + 3.2 chapters), CloudFront subdomain dg0w939ktclw6.cloudfront.net (3.3 chapter). These are all instructor-private moving targets; once the instructor re-deploys or runs cleanup (Phần 4), every literal becomes stale. Even with disclaimers, AWS Well-Architected guidance is to redact account IDs from public docs. A copy-paste learner targeting --agent-runtime-id hera_agent-GIsf2P4ImD will silently fail authorization against the instructor's resource."
    artifacts:
      - path: "content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md"
        issue: "Lines 161-164: hard-coded Account 851725411875, Runtime hera_agent-GIsf2P4ImD, Live URL https://dg0w939ktclw6.cloudfront.net/"
      - path: "content/{vi,en}/3-hands-on/3.5-observability/_index.md"
        issue: "Line 98: --agent-runtime-id hera_agent-GIsf2P4ImD inside copy-paste bash block. Line 112: instructor account 851725411875 referenced as resolution path"
      - path: "content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md"
        issue: "Line 99: 'live KB BKXE19AH89' literal embedded in narrative"
      - path: "content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md"
        issue: "Line 297: 'Live result measured at ap-northeast-1 + KB BKXE19AH89' literal embedded in narrative"
    missing:
      - "Replace 851725411875 with `<your-account-id>` placeholder + cite resolution command (aws sts get-caller-identity --query Account --output text)"
      - "Replace hera_agent-GIsf2P4ImD with `<your-runtime-id>` placeholder + cite resolution command (jq -r '.\"hera-agentcore\".AgentCoreRuntimeArn' dist/cdk-outputs.json)"
      - "Replace BKXE19AH89 with `<your-kb-id>` placeholder + note score is environment-dependent"
      - "Replace https://dg0w939ktclw6.cloudfront.net/ with `<your-distribution>.cloudfront.net` placeholder + cite terraform output -raw widget_cloudfront_url"
      - "Apply replacements to vi+en in same atomic commit per D-49"
  - truth: "English chapters use English-only prose (no leftover Vietnamese vocabulary that breaks the English-reader's flow)"
    status: failed
    reason: "30 occurrences of the Vietnamese word 'Phần' remain in English chapter prose across 7 en files: en/1-introduction (4), en/2-preparation (13), en/3-hands-on/3.1-knowledge-base (3), en/3-hands-on/3.2-pipecat-local (6), en/4-cleanup (1), en/5-summary (2), en/_index.md (1). Learners reading 'run Phần 4 Cleanup' or 'Phần 3.3 builds the multi-arch container' in the English track hit a Vietnamese word with no English equivalent. The 3.3, 3.4, 3.5 chapters consistently say 'Section X.Y' — the inconsistency is a copy-paste artifact from the vi-first authoring workflow (D-49). This is not a parity-gate violation (file-counts match) but does break the literal phase goal 'follow Phần 1-5 in either Vietnamese or English' for the English track."
    artifacts:
      - path: "content/en/_index.md"
        issue: "Line 17: 'if you clean up per Phần 4' — Vietnamese word in English cost-recap"
      - path: "content/en/2-preparation/_index.md"
        issue: "13 occurrences (lines 13, 55, 62, 100, 112, 125, 145, 147, 150, 153, 157, 158, 159) — heaviest concentration"
      - path: "content/en/1-introduction/_index.md"
        issue: "Lines 64, 89, 92, 101 — 4 occurrences in body prose"
      - path: "content/en/3-hands-on/3.1-knowledge-base/_index.md"
        issue: "Lines 9, 107, 143"
      - path: "content/en/3-hands-on/3.2-pipecat-local/_index.md"
        issue: "Lines 9, 99, 268, 297, 305, 321"
      - path: "content/en/4-cleanup/_index.md"
        issue: "Line 148"
      - path: "content/en/5-summary/_index.md"
        issue: "Lines 23, 25"
    missing:
      - "Global rename in content/en/**/*.md — pick one English term (likely 'Section X.Y' for sub-pages and 'Chapter X' for top-level since hugo-theme-learn front-matter has chapter:true on top-level) and apply uniformly"
      - "Re-run bin/check-i18n-parity.sh to confirm parity still holds after the rename (it will — file structure is unchanged)"
      - "Land vi+en in same atomic commit per D-49 (vi files unaffected by this rename; the commit is en-only but the parity convention is preserved because no _index.md count changes)"
deferred:
  - truth: "DOC-11 — copy-paste code snippets + annotated AWS console screenshots present in every chapter"
    addressed_in: "Phase 5 follow-up commit (operator screenshot sweep tracked in 04-HUMAN-UAT items + Plan 05-04 deferred PNG capture)"
    evidence: "REQUIREMENTS.md DOC-11 entry explicitly says 'Pending (operator PNG capture sweep deferred — chapter markdown image refs in place)'. ROADMAP Phase 5 row notes the screenshot sweep is operator-deferred; static/images/{2-preparation,3.3-deploy-agentcore,3.4-web-widget,3.5-observability,4-cleanup}/.gitkeep placeholders ship and 5 image markdown references are inserted at correct locations awaiting PNG drop. The chapter content itself is publishable as-is; Hugo renders alt-text-only placeholders until PNGs arrive. Treated as a deferred item (not a phase-blocking gap) because: (a) the chapter markdown references are wired correctly, (b) the screenshots depend on a future organic CI / operator-driven AWS Console capture, and (c) DOC-11 is explicitly tracked as Pending in REQUIREMENTS.md and ROADMAP Phase 5 row."
human_verification:
  - test: "First organic CI build of the GitHub Pages workflow with the parity gate landed"
    expected: "Workflow runs Checkout (incl. submodule checkout — needs CR-01 fix first) → Check vi/en parity (DOC-12) → Setup Pages → Build with Hugo → Upload artifact → Deploy. Final Pages URL serves the 11 chapters bilingual with language switcher. NOTE: the workflow currently triggers on branches: ['main'] but the active branch is 'master' and the repo has no remote — fix-up needs to happen before the workflow can run organically."
    why_human: "CI build runs on remote infrastructure, requires push to GitHub-hosted repo with Pages enabled, and needs CR-01 (submodule registration) closed first. Cannot be verified by static codebase inspection alone."
  - test: "First learner walkthrough end-to-end from a fresh AWS account on the published Pages site"
    expected: "Cloud Clubs member with no prior knowledge of this repo follows Phần 1 → Phần 2 → Phần 3 (3.1-3.5) → Phần 4 cleanup → Phần 5 summary, copy-pastes the snippets, captures their own screenshots where instructed, and (a) deploys their own KB + agent + widget, (b) talks to it from their own browser, (c) tears down to $0 verified by Cost Explorer 24h after destroy. Phase goal SC#2 + SC#3 are observable only via this walkthrough."
    why_human: "Requires real AWS account, real human reading workshop content, real microphone hardware, real cost-explorer 24h propagation. Pure-code verification cannot test 'a fresh learner reaches the working voice loop end-to-end'. Tracked separately from gaps because the static content is shipped — the only blockers between 'content shipped' and 'fresh learner succeeds' are the gaps above (instructor data leakage, Phần leftover, missing screenshots) plus the inherent walkthrough-required nature of the success criteria."
  - test: "Operator screenshot sweep: capture 6 PNGs to close DOC-11"
    expected: "Operator captures (a) static/images/2-preparation/console-bedrock-model-access.png, (b) static/images/3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png, (c) static/images/3.4-web-widget/widget-idle-state.png, (d) static/images/3.5-observability/billing-alerts-toggle.png, (e) static/images/3.5-observability/cloudwatch-dashboard-hera-prod.png, (f) static/images/4-cleanup/cleanup-verify-output.png. PNGs annotated per D-44 (red box + arrow + label). Hugo renders proper image elements after these land."
    why_human: "AWS Console UI screenshots cannot be auto-generated; require live AWS login + manual capture + annotation. Already tracked in 04-HUMAN-UAT.md and REQUIREMENTS.md DOC-11 Pending status; surfaced here as a deferral aligned with the goal-backward verification scope."
  - test: "WR-01 (REVIEW.md): code-block byte parity drift in 3.4-web-widget"
    expected: "Code-block bash comments in content/{vi,en}/3-hands-on/3.4-web-widget/_index.md should be byte-identical per D-49. Currently the vi file has Vietnamese-only bash comments at lines 117-118 ('mở trong browser desktop... cho phép microphone access') vs the English equivalent in the en file. Verified live by `diff <(awk '/^```/{c=!c; print; next} c{print}' en) <(awk ... vi)` showing 2 line-pair drifts. Fix: revert vi bash comments to English (code blocks are language-neutral per D-49) AND extend bin/check-i18n-parity.sh with a third assertion that diffs the fenced-block-only projection of every paired vi/en file. Surfaced for human decision because: (a) the fix has two parts (content edit + script extension), (b) the parity script's stated intent (D-50) was minimal file-count parity not byte-parity, (c) extending the script is a follow-up plan not a trivial closure-plan item."
    why_human: "Decision required: extend the parity script (matches the spirit of D-49) or accept the drift as 'one prose comment got translated, low-impact'? Code-block byte parity for the workshop is a stronger invariant but the original D-50 explicitly rejected per-section heading parity to avoid false positives. The 3.4 chapter drift is real — operator should decide whether to extend the gate or just clean the comment."
---

# Phase 5: Workshop Documentation (vi/en) Verification Report

**Phase Goal:** A Cloud Clubs member who has never seen this repo can land on the GitHub Pages workshop site, follow Phần 1-5 in either Vietnamese or English, and end with their own voice chatbot running in their own AWS account that they can talk to through their own browser — and then tear it back down to zero cost.

**Verified:** 2026-05-07T12:30:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | All 5 chapters (Phần 1 → Phần 5) published in vi+en on the GitHub Pages site, with language switcher and slugs matching across both trees | FAILED | content tree exists (vi=11, en=11 _index.md; bin/check-i18n-parity.sh exits 0; slug-tree parity holds), config.toml [languages.vi] + [languages.en] declared with languageName + contentDir for both. BUT: themes/hugo-theme-learn submodule is NOT registered in HEAD (`git ls-tree HEAD themes` empty; `git submodule status` empty; themes/hugo-theme-learn/ directory empty). Hugo build will fail with 'theme not found' on first CI run. The published site has never been built — literal phase goal ('land on the GitHub Pages site') is not achievable until CR-01 is closed. |
| 2 | A fresh learner who reads only Phần 2 + Phần 3 successfully deploys Phase 1-3 system into their own AWS account end-to-end | UNCERTAIN (human required) + partial blockers | Content covers AWS account checklist + model access + tool installs + credentials + cost (Phần 2), and KB deploy + Pipecat local + AgentCore deploy + widget + observability (Phần 3.1-3.5). 19 unique source-footer paths cited (D-42); paste-blocks reproduced verbatim from frozen Phase 1-4 source. BUT: copy-paste blocks contain instructor's live state (Account 851725411875, Runtime hera_agent-GIsf2P4ImD, KB BKXE19AH89, CloudFront dg0w939ktclw6.cloudfront.net) — a learner who copies verbatim targets the wrong resources. AND: 30 leftover 'Phần' tokens in en chapters break English-track readability. Real walkthrough must validate end-to-end success after these fixes. |
| 3 | After Phần 4 Cleanup, learner verifies via Cost Explorer + verification script that they have $0 ongoing cost | UNCERTAIN (human required) | Phần 4 Cleanup chapter (147 vi / 148 en lines) ships the 3-step destroy-then-verify quy trinh: cdk destroy hera-agentcore + terraform destroy + bash bin/cleanup-verify.sh + 24h-deferred Cost Explorer paste-line per D-38 + ECR force-delete fallback + CloudFront 15-30min disable-then-delete warning. 6 D-42 Source footers per language. Content is correct against RUNBOOK.md frozen Phase 4 source. Real walkthrough verification deferred to 04-HUMAN-UAT item #3 (first organic cleanup-verify run). |
| 4 | Each chapter contains relevant top-N pitfall callouts at the moments the learner is about to hit them | VERIFIED | 8/8 D-51 pitfall callouts placed across Phases 1+2+3 chapters: #1 8-min Sonic stream cap (Phần 3.2), #2 audio sample rate (Phần 3.2), #3 model access per-region/per-model (Phần 2), #4 HTTPS-required-for-mic (Phần 3.4), #5 billing alarm 24h propagation (Phần 3.5), #6 tool-use schema strictness (Phần 3.2), #7 bilingual parity DOC-12 convention (Phần 1), #8 KB sync delay (Phần 3.1). 14 {{% notice %}} shortcodes in vi tree, 14 in en tree (parity). 8 placed exceeds the 'Top 5-7' literal target. |
| 5 | CI enforces vi/en parity on every PR — the parity script counts chapters and fails the build if they diverge | VERIFIED | bin/check-i18n-parity.sh exists (66 lines, executable, syntax clean) with 2 assertions: file-count parity + bidirectional slug-tree parity. Wired into .github/workflows/deploy.yml step 'Check vi/en parity (DOC-12)' between Checkout and Setup Pages. Live verified: `bash bin/check-i18n-parity.sh` exits 0 ('OK: file count parity (vi=11, en=11)' + 'OK: vi/en slug tree parity'). Synthetic mismatch injection in Plan 05-01 confirmed exit 1 with diff list. |

**Score:** 2/5 truths verified (Truth 4 + Truth 5); Truth 1 FAILED (CR-01 blocker); Truths 2-3 UNCERTAIN/HUMAN-NEEDED.

### Deferred Items

Items not yet met but explicitly addressed in later phases or follow-up plans within Phase 5 scope.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | DOC-11 — copy-paste code snippets + annotated AWS console screenshots in every chapter | Phase 5 follow-up commit (deferred operator screenshot sweep) | REQUIREMENTS.md DOC-11 row: 'Pending (operator PNG capture sweep deferred — chapter markdown image refs in place)'. 5 image markdown references inserted at correct chapter locations; .gitkeep placeholders track the directories; Hugo renders alt-text-only until PNGs land. ROADMAP Phase 5 row + Plan 05-04 SUMMARY both explicitly call out the deferred sweep. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `bin/check-i18n-parity.sh` | DOC-12 file-count + slug-tree parity gate, executable, exit 0 on parity, exit 1 on mismatch | VERIFIED | 66 lines, executable, syntax clean (`bash -n` passes). Asserts file-count parity + bidirectional slug-tree parity. Live run exits 0. |
| `.github/workflows/deploy.yml` | Pre-build parity gate wired into Hugo deploy job | VERIFIED (orphaned) | Line 38: `Check vi/en parity (DOC-12)` step calls `bash bin/check-i18n-parity.sh` between Checkout (line 32) and Setup Pages (line 41). YAML parseable. **WARNING: workflow triggers on branches: ['main'] (line 5) but active branch is 'master' and no remote configured — workflow has not run yet.** |
| `config.toml` | Hugo site config with real Hera values, no FCJ template placeholders | VERIFIED | baseURL = `https://KenzyTran.github.io/hera/`; title = `Hera — AWS Voice Agent Workshop`; theme = `hugo-theme-learn`; defaultContentLanguage = `vi`; defaultContentLanguageInSubdir = true; [languages.vi] + [languages.en] both declared; markup.goldmark.unsafe = true. Zero FCJ template placeholders (`grep -E "YOUR_GITHUB_USERNAME|Workshop Title|Your Name|Workshop description"` returns nothing). |
| `content/vi/_index.md` | Hera workshop overview replacing template stub | VERIFIED | 29 lines, Vietnamese title + intro + Info table + Yêu cầu list + {{% children %}} shortcode. |
| `content/en/_index.md` | Hera workshop overview, English mirror | VERIFIED with WARNING | 29 lines, English mirror — but line 17 contains 'per Phần 4' (Vietnamese leftover). Tracked under Truth 3 leftover-Phần gap. |
| `content/{vi,en}/1-introduction/_index.md` | Phần 1 single-page chapter with Mermaid component + sequence diagrams + bilingual-parity callout + folded prereqs H2 | VERIFIED | vi=116 lines, en=117 lines. Both have 2 mermaid blocks (component flowchart + sequence diagram, byte-identical between vi/en), 2 {{% notice warning %}} callouts (cost + bilingual-parity), folded prereqs `## Yêu cầu trước khi bắt đầu` / `## Prerequisites before you start` H2 (D-53 Option A). 4 'Phần' leftovers in en file. |
| `content/{vi,en}/2-preparation/_index.md` | Phần 2 single-page with AWS account checklist + model access + tool installs + credentials + cost | VERIFIED with WARNING | 159 lines per side. D-44 #1 image markdown ref to `/images/2-preparation/console-bedrock-model-access.png` (PNG not yet committed; .gitkeep placeholder ships). D-51 #3 model-access pitfall callout placed. D-54 cost ballpark `~$2-5 USD per 2-hour session` documented. **13 'Phần' leftovers in en file** — heaviest concentration. |
| `content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md` | Sub-page with terraform apply + ingestion + verify + re-index | VERIFIED with WARNING | 143 lines per side. 6 D-42 source footers per side. D-51 #8 KB sync delay callout placed. **Embeds live KB ID `BKXE19AH89` (line 99)** — instructor data leakage. 3 'Phần' leftovers in en. |
| `content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md` | Sub-page with main.py + prompts.py + tools.py + pipeline.py inline quotes + uv path + smoke gate | VERIFIED with WARNING | 321 lines per side. 13 D-42 source footers per side. D-51 callouts #1 (8-min cap), #2 (sample rate), #6 (tool-use schema) all placed. **Embeds live KB `BKXE19AH89` (line 297)** — instructor data leakage. 6 'Phần' leftovers in en. |
| `content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md` | Sub-page with multi-arch buildx + cdk deploy + terraform second-pass + smoke-deploy gate + POST /invocations stub | VERIFIED with WARNING | 181 lines per side. 8 D-42 source footers per side. D-44 #3 service-quotas screenshot ref. D-24 hybrid IaC + D-30 concurrency cap explained. **Embeds live Account 851725411875, Runtime hera_agent-GIsf2P4ImD, CloudFront dg0w939ktclw6.cloudfront.net (lines 161-164)** — instructor data leakage. |
| `content/{vi,en}/3-hands-on/3.4-web-widget/_index.md` | Sub-page with frontend structure + presigner Lambda Function URL + bin/build-widget.sh + 5-state record button + AudioWorklet 16kHz | VERIFIED with WARNING | 148 lines per side. 7 D-42 source footers per side. D-51 #4 HTTPS-for-mic callout placed. **Code-block drift detected: vi has Vietnamese-only bash comments at lines 117-118 ('mở trong browser desktop' / 'cho phép microphone access') vs en's English equivalents — D-49 byte-parity invariant broken silently.** D-44 #4 widget hero ref. |
| `content/{vi,en}/3-hands-on/3.5-observability/_index.md` | Sub-page with CloudWatch dashboard 5 panels + 2 op alarms + 1 billing alarm cross-region + D-35/D-36 trade-offs | VERIFIED with WARNING | 119 lines per side. 7 D-42 source footers per side. D-51 #5 billing 24h propagation callout placed. **Embeds Runtime hera_agent-GIsf2P4ImD (line 98) inside copy-paste paste-block + Account 851725411875 (line 112)** — instructor data leakage in copy-paste-targeted CLI. D-44 #2 + #5 image refs. |
| `content/{vi,en}/4-cleanup/_index.md` | Phần 4 Cleanup single-page with cdk destroy + terraform destroy + bin/cleanup-verify.sh + Cost Explorer 24h paste-line | VERIFIED with WARNING | vi=147, en=148 lines. 6 D-42 Source footers per side. {{% notice info %}} deferred-callout for D-44 #6 cleanup-verify-output.png hero (PNG ships in follow-up commit). 1 'Phần' leftover in en (line 148). |
| `content/{vi,en}/5-summary/_index.md` | Phần 5 Summary single-page with cost recap + DOC-09 expansion roadmap (Twilio + multi-language + multi-agent + history) | VERIFIED with WARNING | 82 lines per side. 1 D-42 Source footer per side. v2 IDs cited literally: TWIL-01..03, I18N-01..02, ADV-01..04, AUTH-01..02, THEME-01..02. 2 'Phần' leftovers in en (lines 23, 25). |
| `static/images/{2-preparation,3.3-deploy-agentcore,3.4-web-widget,3.5-observability,4-cleanup}/.gitkeep` | Directory placeholders for D-44 PNGs (deferred to operator sweep) | VERIFIED | 5 .gitkeep files exist. PNG drops deferred per DOC-11 Pending status. |
| `themes/hugo-theme-learn/` | Hugo theme submodule registered in git tree, fetched on CI checkout, drives Hugo build | **MISSING (BLOCKER)** | `.gitmodules` declares the submodule but `git ls-tree HEAD themes` returns empty (no gitlink commit-pointer entry). `git submodule status` returns empty. Local `themes/hugo-theme-learn/` is an empty directory. CI Hugo build will fail with 'theme not found'. **Pre-existing repo state predating Phase 5 but actively blocking the published-site goal.** |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `.github/workflows/deploy.yml` | `bin/check-i18n-parity.sh` | run: bash bin/check-i18n-parity.sh step before Build with Hugo | WIRED | Line 38-39: literal `bash bin/check-i18n-parity.sh` invocation between Checkout and Setup Pages. |
| `content/vi/1-introduction/_index.md` | `content/en/1-introduction/_index.md` | matching slug under content/{vi,en}/1-introduction/_index.md (D-49 + D-50) | WIRED | Both files exist; bin/check-i18n-parity.sh slug-tree assertion passes for the 1-introduction path. Mermaid blocks byte-identical between vi+en (verified in Plan 05-01 SUMMARY). |
| `config.toml` | `themes/hugo-theme-learn` | theme = "hugo-theme-learn" still set after edit | NOT_WIRED (BLOCKER) | config.toml line 3 declares `theme = "hugo-theme-learn"` correctly, but the theme directory is empty (no theme files; submodule not registered in HEAD tree). Hugo build will fail at theme resolution. |
| `config.toml` [languages.vi/en] | `content/vi/`, `content/en/` | contentDir = "content/vi" / "content/en" | WIRED | Both languages declared with correct contentDir paths; 11 _index.md per side. Language switcher will render correctly IF the theme renders (currently blocked by submodule gap). |
| `content/{vi,en}/3-hands-on/3.X-*/_index.md` | `bin/<script>.sh` / `RUNBOOK.md (<section>) — Phase X Plan Y` | D-42 italic Source footer | WIRED | 19 unique repo-relative source paths cited across the chapters; per-chapter footer counts: 1-intro=2, 2-prep=8, 3.1=6, 3.2=14, 3.3=8, 3.4=7, 3.5=7, 4-cleanup=6, 5-summary=1 (vi side; en side identical). Drift trivially auditable via `grep '^*Source:'`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `bin/check-i18n-parity.sh` | VI_COUNT, EN_COUNT, VI_SLUGS, EN_SLUGS | `find content/{vi,en} -name "_index.md" -type f` | Yes — 11 per side actually returned on disk | FLOWING |
| `.github/workflows/deploy.yml` Build with Hugo | hugo binary + `theme = "hugo-theme-learn"` from config.toml | apt install + checkout (with submodules: recursive) | NO — theme submodule not registered, checkout fetches nothing under themes/, Hugo errors at build-time | DISCONNECTED (BLOCKER) |
| Chapter image markdown refs | PNG files | `static/images/<chapter>/<filename>.png` | NO — only .gitkeep placeholders ship; 5 image markdown refs render alt-text-only fallback | STATIC (deferred per DOC-11) |
| 3.3 chapter "Live state (instructor reference)" block | Account / Runtime / Live URL hardcoded values | None — hardcoded literals from instructor's live deploy | YES (but stale + leaks instructor identity) | HOLLOW_PROP — these copy-paste targets are instructor-private moving targets that learners must NOT use verbatim |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Parity script exits 0 against current tree | `bash bin/check-i18n-parity.sh` | exit 0; '2/2 parity assertions passed'; vi=11 en=11 | PASS |
| Parity script syntax | `bash -n bin/check-i18n-parity.sh` | exit 0 | PASS |
| Workflow YAML parseable | `python -c "import yaml; yaml.safe_load(open('.github/workflows/deploy.yml'))"` | YAML_OK | PASS (verified in Plan 05-01 SUMMARY; not re-run here — file unchanged) |
| Submodule registered | `git ls-tree HEAD themes` | empty | FAIL (BLOCKER — CR-01) |
| Submodule fetched | `git submodule status` | empty | FAIL (BLOCKER — CR-01) |
| FCJ template placeholders gone from config.toml | `grep -E "YOUR_GITHUB_USERNAME\|Workshop Title\|Your Name\|Workshop description" config.toml` | exit 1 (no match) | PASS |
| No emojis in content tree | `grep -P '[\x{1F300}-\x{1F9FF}]' content/{vi,en} -r` | exit 1 (no match) | PASS |
| Code-block byte parity 3.4-web-widget | `diff <(awk fenced en) <(awk fenced vi)` | 2 line-pair drift on lines 117-118 (vi has Vietnamese bash comments) | FAIL (WARNING — surfaced for human decision) |
| 'Phần' leftover audit in en chapters | `grep -c "Phần" content/en/ -r` | 30 occurrences across 7 files | FAIL (gap) |
| Live instructor data audit | `grep -rn "851725411875\|hera_agent-GIsf2P4ImD\|BKXE19AH89\|dg0w939ktclw6" content/` | 14 hits across 8 files | FAIL (gap) |
| Hugo build (would surface theme miss) | not run — no remote, branch mismatch (active='master', workflow trigger='main'), no GH Pages enabled | N/A | SKIP — cannot run statically; flagged for human verification |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DOC-01 | 05-01 | Phần 1 Introduction (vi+en) — voice AI, Nova Sonic, why AgentCore vs ECS, hera high-level diagram | SATISFIED | content/{vi,en}/1-introduction/_index.md (116/117 lines) with Mermaid component + sequence diagrams (D-55), folded prereqs H2 (D-53 Option A), region note (D-47), bilingual-parity callout (D-51 #7), 'why this stack' framing. |
| DOC-02 | 05-02 | Phần 2 Preparation (vi+en) — AWS account checklist + model access + tool installs + credentials + cost | SATISFIED with WARNING (Phần leftover, 13 occurrences in en) | content/{vi,en}/2-preparation/_index.md (159/159 lines) with Bedrock model access steps for Nova 2 Sonic + Titan v2 in ap-northeast-1, AWS CLI v2 / Terraform >=1.9 / uv / Docker buildx / jq install paste-blocks, D-54 anchored ~$2-5 USD/2-hour ballpark, D-51 #3 model-access pitfall callout. |
| DOC-03 | 05-02 | Phần 3.1 Knowledge Base (vi+en) — write catalog + deploy modules/kb + verify Retrieve API | SATISFIED with WARNING (instructor KB ID leak) | content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md (143/143 lines) mirrors RUNBOOK Phase 1, D-51 #8 KB sync delay callout, 6 source footers per language. |
| DOC-04 | 05-02 | Phần 3.2 Pipecat Local (vi+en) — code structure + system prompt + tool definition + run local test | SATISFIED with WARNING (instructor KB ID leak) | content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md (321/321 lines) with main.py + prompts.py + tools.py + pipeline.py inline quotes, 3 D-51 callouts (#1/#2/#6), 13 source footers per language. |
| DOC-05 | 05-03 | Phần 3.3 Deploy AgentCore (vi+en) — build container + push ECR + deploy AgentCore + verify endpoint | SATISFIED with BLOCKER (instructor account+runtime+CloudFront leak in copy-paste blocks) | content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md (181/181 lines) with bin/push-image.sh + cdk deploy + terraform second-pass + smoke-deploy gate + POST /invocations stub paste-blocks. D-24 hybrid IaC documented. **Lines 161-164 leak instructor's live state.** |
| DOC-06 | 05-03 | Phần 3.4 Web Widget (vi+en) — HTML/JS + browser microphone + AgentCore endpoint + S3+CloudFront deploy | SATISFIED with WARNING (code-block parity drift) | content/{vi,en}/3-hands-on/3.4-web-widget/_index.md (148/148 lines) covers presigner Lambda Function URL + bin/build-widget.sh + S3+CloudFront deploy + 5-state record button + AudioWorklet 16kHz Int16. D-51 #4 HTTPS-for-mic callout. |
| DOC-07 | 05-03 | Phần 3.5 Observability (vi+en) — CloudWatch dashboard walk-through + alarm setup | SATISFIED with BLOCKER (instructor runtime ID inside copy-paste paste-block) | content/{vi,en}/3-hands-on/3.5-observability/_index.md (119/119 lines) walks dashboard hera-prod 5 panels + 2 op alarms + 1 billing alarm cross-region + D-35/D-36 trade-offs. D-51 #5 billing 24h callout. **Line 98 leaks instructor's runtime ID.** |
| DOC-08 | 05-04 | Phần 4 Cleanup (vi+en) — terraform destroy + manual checks + verification script | SATISFIED with WARNING (1 Phần leftover in en) | content/{vi,en}/4-cleanup/_index.md (147/148 lines) mirrors RUNBOOK Phase 4 quy trinh: cdk destroy + terraform destroy + bin/cleanup-verify.sh + 24h Cost Explorer paste-line + ECR fallback. D-44 #6 hero deferred-callout. |
| DOC-09 | 05-04 | Phần 5 Summary (vi+en) — cost recap + Twilio/multi-language/multi-agent expansion roadmap | SATISFIED with WARNING (2 Phần leftovers in en) | content/{vi,en}/5-summary/_index.md (82/82 lines) with What-you-built recap + cost recap (~$2-5 USD ballpark per D-54) + DOC-09 expansion roadmap (TWIL-01..03 / I18N-01..02 / ADV-01 / ADV-03) + v2 backlog. |
| DOC-10 | 05-01..05-03 | Top 5-7 pitfall callouts at the trigger moment in chapters | SATISFIED | All 8 D-51 callouts placed (8 > 5-7 target): #1/#2/#6 in 3.2, #3 in 2-prep, #4 in 3.4, #5 in 3.5, #7 in 1-intro, #8 in 3.1. Style: {{% notice warning %}} for 'watch out', {{% notice info %}} for 'FYI'. |
| DOC-11 | (none of 05-01..05-04) | Each chapter has copy-paste code button + screenshot AWS console with annotation | DEFERRED (operator screenshot sweep) | Chapter image markdown refs in place (5 PNG paths referenced); .gitkeep placeholders for the 5 directories ship; PNGs deferred to operator sweep. Tracked Pending in REQUIREMENTS.md DOC-11 row + ROADMAP Phase 5 row. |
| DOC-12 | 05-01 | vi/en parity check runs in CI (script counts chapters, fails on mismatch) | SATISFIED | bin/check-i18n-parity.sh (66 lines, executable) wired into .github/workflows/deploy.yml line 38 between Checkout and Setup Pages. Live exits 0 against current tree (vi=11 en=11). Synthetic mismatch verified exits 1. |

**Coverage:** 11/12 SATISFIED + 1/12 DEFERRED. No ORPHANED requirements (all 12 DOC IDs accounted for in plan frontmatter). 4/12 SATISFIED carry WARNING/BLOCKER quality issues that flow into the gaps section.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `themes/hugo-theme-learn/` | N/A | Empty directory; not a registered submodule | BLOCKER | CI Hugo build will fail with 'theme not found' — published site never builds |
| `content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md` | 161-164 | Hardcoded instructor account 851725411875 + runtime hera_agent-GIsf2P4ImD + CloudFront dg0w939ktclw6 | BLOCKER | Copy-paste blocks target instructor's resources; learner-facing security + correctness regression |
| `content/{vi,en}/3-hands-on/3.5-observability/_index.md` | 98, 112 | Hardcoded runtime ID inside `aws bedrock-agentcore-control update-agent-runtime --agent-runtime-id` paste-block + account ID in dashboard URL resolution path | BLOCKER | Same as above — copy-paste targeting wrong AWS resource |
| `content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md` | 99 | Hardcoded 'live KB BKXE19AH89' literal in narrative | WARNING | Narrative is not copy-pasted but is a moving target (KB ID changes after destroy/redeploy) |
| `content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md` | 297 | Hardcoded 'KB BKXE19AH89' literal in narrative | WARNING | Same as above |
| `content/en/2-preparation/_index.md` | 13, 55, 62, 100, 112, 125, 145, 147, 150, 153, 157, 158, 159 | Vietnamese 'Phần' word in English-prose chapter (13 occurrences) | WARNING | English-track readability — learner-facing copy-paste artifact from D-49 vi-first authoring |
| `content/en/1-introduction/_index.md` | 64, 89, 92, 101 | 'Phần' leftover in English chapter (4 occurrences) | WARNING | Same as above |
| `content/en/3-hands-on/3.2-pipecat-local/_index.md` | 9, 99, 268, 297, 305, 321 | 'Phần' leftover (6 occurrences) | WARNING | Same as above |
| `content/en/3-hands-on/3.1-knowledge-base/_index.md` | 9, 107, 143 | 'Phần' leftover (3 occurrences) | WARNING | Same as above |
| `content/en/4-cleanup/_index.md` | 148 | 'Phần' leftover (1 occurrence) | WARNING | Same as above |
| `content/en/5-summary/_index.md` | 23, 25 | 'Phần' leftover (2 occurrences) | WARNING | Same as above |
| `content/en/_index.md` | 17 | 'Phần' leftover in cost row of root info table | WARNING | Same as above |
| `content/{vi,en}/3-hands-on/3.4-web-widget/_index.md` | 117-118 | Code-block byte-parity drift: vi has Vietnamese bash comments vs en's English equivalents (D-49 invariant violation) | WARNING | bin/check-i18n-parity.sh does not assert byte-parity (only file-count + slug-tree); silent drift; surfaced for human decision (extend script or fix content) |
| `static/images/{2-preparation,3.3-deploy-agentcore,3.4-web-widget,3.5-observability,4-cleanup}/<filename>.png` | N/A | 5 PNG files referenced in markdown but only .gitkeep placeholders ship | INFO (deferred per DOC-11) | Hugo renders alt-text-only fallback; chapters publishable; PNG drop tracked in 04-HUMAN-UAT |
| `.github/workflows/deploy.yml` | 5 | `branches: ["main"]` trigger but active branch is 'master' and no remote | INFO | Workflow has not run organically; first publish requires either branch alignment or trigger update |
| `config.toml` | 29 | `themeVariant = "workshop"` references custom variant that may not exist in upstream theme | INFO | Cannot verify until submodule lands (CR-01); silent no-op fallback to default styling if variant missing |

### Human Verification Required

#### 1. First organic CI build of GitHub Pages workflow

**Test:** Push the repo to a remote with GitHub Pages enabled, on a branch matching `.github/workflows/deploy.yml` trigger (currently `main`, but active branch is `master`). Wait for workflow to run.
**Expected:** Workflow steps complete in order — Install Hugo CLI → Checkout (with submodule fetch) → Check vi/en parity (DOC-12) (must exit 0) → Setup Pages → Build with Hugo → Upload artifact → Deploy. Final Pages URL serves all 11 chapters bilingual with language switcher.
**Pre-requisite:** CR-01 (themes/hugo-theme-learn submodule registration) MUST be closed first; without it the Build with Hugo step will fail at theme resolution.
**Why human:** CI runs on remote infrastructure, requires GH Pages enabled, requires branch + remote alignment. Cannot be verified by static codebase inspection.

#### 2. First learner walkthrough end-to-end on the published Pages site

**Test:** A Cloud Clubs member with no prior knowledge of this repo lands on the published Pages URL, follows Phần 1 → Phần 2 → Phần 3 (3.1-3.5) → Phần 4 → Phần 5 in either Vietnamese or English. Copy-pastes snippets, captures screenshots when chapters reference them, deploys to their own AWS account.
**Expected:**
- Phần 2 + Phần 3 enables Bedrock model access, deploys KB, runs Pipecat local, deploys to AgentCore, talks to their widget through HTTPS browser.
- Phần 4 cleanup tears down to verify $0 ongoing cost (verified via Cost Explorer 24h after destroy + bin/cleanup-verify.sh all-green).
- Phần 5 summary closes the workshop.
**Pre-requisite:** CR-01 closed + instructor data redacted + en 'Phần' tokens cleaned. Without these, the literal walkthrough will fail at multiple points.
**Why human:** Requires real AWS account, real human reading workshop content, real microphone hardware, real Cost Explorer 24h propagation. Pure-code verification cannot test 'fresh learner reaches working voice loop end-to-end'.

#### 3. Operator screenshot sweep for DOC-11

**Test:** Operator captures 6 PNGs (annotated per D-44 with red box + arrow + label) and commits to `static/images/<chapter>/<filename>.png`:
1. `2-preparation/console-bedrock-model-access.png`
2. `3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png`
3. `3.4-web-widget/widget-idle-state.png`
4. `3.5-observability/billing-alerts-toggle.png`
5. `3.5-observability/cloudwatch-dashboard-hera-prod.png`
6. `4-cleanup/cleanup-verify-output.png`
**Expected:** Hugo renders proper image elements after PNGs land; chapters lose alt-text-only fallback. DOC-11 flips to Complete in REQUIREMENTS.md + ROADMAP Phase 5 row.
**Why human:** AWS Console UI screenshots cannot be auto-generated; require live AWS login + manual capture + annotation. Already tracked in 04-HUMAN-UAT items + REQUIREMENTS.md DOC-11 Pending status.

#### 4. Code-block byte-parity drift in 3.4-web-widget (D-49 invariant decision)

**Test:** Operator decides whether to (a) revert the vi bash comments at content/vi/3-hands-on/3.4-web-widget/_index.md lines 117-118 to English and extend bin/check-i18n-parity.sh with a third assertion that diffs the fenced-block-only projection of every paired vi/en file, OR (b) accept the drift as low-impact prose comment translation.
**Expected:** If (a): vi+en bash blocks become byte-identical AND the parity script catches future drifts. If (b): documented decision in next Phase 5 SUMMARY explaining the D-50 minimal-parity-only stance was retained.
**Why human:** Decision depends on whether the operator wants D-49's byte-parity invariant enforced strictly or treated as a soft convention. The original D-50 explicitly rejected per-section heading parity to avoid false positives — extending to code-block parity is a similar judgment call.

### Gaps Summary

Phase 5 ships substantial content (22 bilingual chapter files; vi=11 en=11 _index.md tree; 14+14 notice callouts; 8/8 D-51 pitfalls placed; DOC-12 parity gate live and exits 0; config.toml replaced; 19 unique source-footer paths cited; submodule untouched per plan invariant). The DOC-12 parity gate works as advertised, the chapters are the right shape and dimensions, the pitfall callouts are placed at the right moments, and the 5-step Phase 1-5 walkthrough is documented end-to-end.

**However, three gaps prevent the literal phase goal from being achieved:**

1. **CR-01 (BLOCKER): Hugo theme submodule unregistered in HEAD.** The phase goal starts with 'land on the GitHub Pages workshop site' — but the published site cannot build. `.gitmodules` declares the submodule, but `git ls-tree HEAD themes` is empty and `git submodule status` returns nothing. Local `themes/hugo-theme-learn/` is empty. CI Hugo build will fail at theme resolution. This is pre-existing repo state predating Phase 5, but Phase 5 wired the parity gate into the same broken build path so the broken state is now actively gating publication. Fix: register the submodule properly (single 4-command git sequence; ~5 minutes including verify).

2. **CR-02 (BLOCKER): Live instructor account state in copy-paste blocks.** A learner who copy-pastes verbatim from Phần 3.3, 3.5, 3.1, 3.2 will reference the instructor's AWS account ID (5×), runtime ID (3×, including inside an `aws bedrock-agentcore-control update-agent-runtime --agent-runtime-id` paste-block), KB ID (2×), and CloudFront subdomain (1×). All are instructor-private moving targets. Even with disclaimers, AWS Well-Architected guidance is to redact account IDs from public docs. Fix: replace concrete values with `<your-account-id>` / `<your-runtime-id>` / `<your-kb-id>` / `<your-distribution>.cloudfront.net` placeholders + cite resolution commands; vi+en in same atomic commit per D-49.

3. **WR-02 (gap): 30 'Phần' tokens leftover in English chapters.** The English-track learner reads 'run Phần 4 Cleanup' and 'Phần 3.3 builds the multi-arch container' — Vietnamese vocabulary in what should be English prose. The 3.3, 3.4, 3.5 chapters consistently use 'Section X.Y' (correct) — the inconsistency is a copy-paste artifact from D-49 vi-first authoring. Fix: global rename in content/en/**/*.md.

**Deferred items (not gaps):** DOC-11 PNG capture sweep is operator-deferred and tracked in REQUIREMENTS.md + ROADMAP Phase 5 row.

**Items routed to human verification:** First organic CI build, first learner walkthrough, operator screenshot sweep, and a decision on extending the parity script to enforce code-block byte parity (D-49 invariant; surfaced by WR-01 in REVIEW.md).

The gaps are concentrated and individually closable; recommend a single closure plan that (a) registers the submodule, (b) redacts instructor data with placeholder + resolution-command pattern, (c) global-renames 'Phần' → 'Section' / 'Chapter' across content/en, in 1-3 atomic commits per D-49 commit hygiene.

---

_Verified: 2026-05-07T12:30:00Z_
_Verifier: Claude (gsd-verifier)_
