---
phase: 05-workshop-documentation-vi-en
reviewed: 2026-05-07T05:03:49Z
depth: standard
files_reviewed: 24
files_reviewed_list:
  - .github/workflows/deploy.yml
  - bin/check-i18n-parity.sh
  - config.toml
  - content/en/_index.md
  - content/en/1-introduction/_index.md
  - content/en/2-preparation/_index.md
  - content/en/3-hands-on/3.1-knowledge-base/_index.md
  - content/en/3-hands-on/3.2-pipecat-local/_index.md
  - content/en/3-hands-on/3.3-deploy-agentcore/_index.md
  - content/en/3-hands-on/3.4-web-widget/_index.md
  - content/en/3-hands-on/3.5-observability/_index.md
  - content/en/4-cleanup/_index.md
  - content/en/5-summary/_index.md
  - content/vi/_index.md
  - content/vi/1-introduction/_index.md
  - content/vi/2-preparation/_index.md
  - content/vi/3-hands-on/3.1-knowledge-base/_index.md
  - content/vi/3-hands-on/3.2-pipecat-local/_index.md
  - content/vi/3-hands-on/3.3-deploy-agentcore/_index.md
  - content/vi/3-hands-on/3.4-web-widget/_index.md
  - content/vi/3-hands-on/3.5-observability/_index.md
  - content/vi/4-cleanup/_index.md
  - content/vi/5-summary/_index.md
findings:
  critical: 2
  warning: 6
  info: 4
  total: 12
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-05-07T05:03:49Z
**Depth:** standard
**Files Reviewed:** 24
**Status:** issues_found

## Summary

Phase 5 ships a parity-gate bash script, a CI workflow update, a Hugo `config.toml`,
and 22 bilingual chapter files (vi+en × 11 chapters). The submitted artifacts have
two BLOCKER-class defects:

1. **Hugo theme submodule is unregistered in git's tree** — `.gitmodules` declares
   the `hugo-theme-learn` submodule but no gitlink entry exists under `themes/` in
   `HEAD`. CI (`actions/checkout@v4` with `submodules: recursive`) cannot fetch
   what isn't registered, so `hugo --minify` will fail with "theme not found" and
   the GitHub Pages deploy will never produce a site. The new parity step itself
   is wired correctly but the build step downstream of it cannot succeed.
2. **Real instructor account ID + runtime ID + KB ID + CloudFront subdomain are
   embedded in published workshop content** — `851725411875`, `hera_agent-GIsf2P4ImD`,
   `BKXE19AH89`, and `https://dg0w939ktclw6.cloudfront.net/` ship in both vi and
   en chapters. AWS account IDs are not "secret" in the cryptographic sense, but
   AWS Trust & Safety + IR teams treat publishing one as a bad practice (it
   simplifies enumeration + targeted phishing). Either redact to a placeholder
   (`<your-account-id>`) or delete the "Live state (instructor reference)" sub-
   sections entirely before publish.

Beyond those, the most consequential WARNING is that the parity script only
asserts slug-tree equality — it does NOT enforce code-block byte parity per D-49,
and the 3.4-web-widget chapter already contains a Vietnamese-only line inside
what should be a parity-byte-identical `bash` block. CI is green; the real
invariant the script claims to enforce is silently broken.

The remaining items are quality issues: leftover Vietnamese "Phần" in English
prose (2-preparation has 9 occurrences alone), inconsistent "Section" vs "Phần"
choice across en chapters, missing screenshot files (only `.gitkeep`s under
`static/images/{2-preparation,3.3,3.4,3.5}/`), and the Hugo content directory
contains an `_index.md` for `3-hands-on/` itself that was not in the
review file list (silently in scope; mentioned for completeness).

## Critical Issues

### CR-01: Hugo theme submodule is unregistered in git tree — CI build will fail

**File:** `.gitmodules` (root) + missing `themes/hugo-theme-learn` gitlink in `HEAD`
**Issue:** `.gitmodules` declares the submodule, but `git ls-tree HEAD themes` is
empty — no gitlink commit-pointer entry has ever been added. `actions/checkout@v4`
with `submodules: recursive` only fetches submodules that have a registered
gitlink in the tree, so the workshop GitHub Pages deploy will fail at the
`Build with Hugo` step with `Error: module "hugo-theme-learn" not found`. The
new parity step (added by Phase 5 to `deploy.yml`) is wired correctly but it
runs ahead of a build that cannot succeed in CI. Locally the directory exists
but is empty (verified: `themes/hugo-theme-learn/` is an empty placeholder).

This is pre-existing repo state, but Phase 5 ships the GitHub Pages workflow
that depends on it — the deploy will not work as documented.

**Fix:**
```bash
# Register the submodule properly in git's tree:
cd C:/Users/trant/projects/hera
rm -rf themes/hugo-theme-learn
git submodule add https://github.com/matcornic/hugo-theme-learn.git themes/hugo-theme-learn
git add .gitmodules themes/hugo-theme-learn
git commit -m "fix(theme): register hugo-theme-learn as a real submodule"

# Verify:
git ls-tree HEAD themes/   # must list a 160000 commit entry, not empty
```

### CR-02: Live instructor AWS account ID + runtime ID + CloudFront URL embedded in published docs

**File:**
- `content/{en,vi}/3-hands-on/3.3-deploy-agentcore/_index.md:161-164`
- `content/{en,vi}/3-hands-on/3.5-observability/_index.md:98 (runtime-id), :112 (account)`
- `content/{en,vi}/3-hands-on/3.1-knowledge-base/_index.md:99` (KB ID `BKXE19AH89`)
- `content/{en,vi}/3-hands-on/3.2-pipecat-local/_index.md:297` (KB ID)

**Issue:** Workshop content publishes:
- AWS account ID `851725411875` (5 occurrences across 4 files).
- AgentCore runtime ID `hera_agent-GIsf2P4ImD` (4 occurrences) — appears inside
  `aws bedrock-agentcore-control update-agent-runtime --agent-runtime-id ...`
  paste-blocks that learners will copy verbatim, accidentally targeting the
  instructor's resource (which won't authorize their session, but the
  intent is wrong).
- KB ID `BKXE19AH89` (2 occurrences in 3.1 + 3.2 chapters).
- CloudFront subdomain `dg0w939ktclw6.cloudfront.net` (en + vi 3.3 chapter).

The Markdown also notes (3.3 chapter) "Account: 851725411875 (instructor's; you
use your own account)" — even with that disclaimer, AWS Well-Architected
guidance is to redact account IDs from public docs because they are personally
identifying for IAM principals + simplify reconnaissance for phishing.

The KB ID + runtime ID also hard-code a session-state that is a moving target —
when the instructor re-deploys (or after `terraform destroy` per the cleanup
chapter), every "live result measured at ... KB BKXE19AH89" line is a stale
artifact, not a paste-replicable fact.

**Fix:** Replace every concrete value with a placeholder + cite the resolution
command. Example for the 3.3 chapter "Live state (instructor reference)" block:
```markdown
## Live state (instructor reference)

- Account: `<instructor-account-id>` (you use your own account; resolve yours via
  `aws sts get-caller-identity --query Account --output text`).
- Region: `ap-northeast-1`.
- Runtime: created by your `cdk deploy` — capture from
  `jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json`.
- Live URL: resolved via
  `terraform -chdir=infra/envs/prod output -raw widget_cloudfront_url`.
```
Apply the same redaction to:
- 3.5 chapter `--agent-runtime-id <your-runtime-id>` paste-block.
- 3.1 + 3.2 chapter "live KB `BKXE19AH89`" → `<your-kb-id>` plus a sentence noting
  the score is environment-dependent.
- 3.3 chapter `Live URL` line → `<your-distribution>.cloudfront.net`.

## Warnings

### WR-01: Parity script does NOT enforce code-block byte-identity (D-49) — silent drift in 3.4

**File:** `bin/check-i18n-parity.sh:38-49` + drift in `content/{en,vi}/3-hands-on/3.4-web-widget/_index.md:115-119`

**Issue:** The script claims to be the "DOC-12 parity gate" but only asserts:
- File count parity (`vi`==`en`).
- Slug-tree set equality.

D-49 ("vi+en files share fenced code blocks byte-identically") is the stated
invariant per the Phase 5 plan, but the script never compares code-block content.
Consequence: the 3.4-web-widget chapter currently has two Vietnamese-only lines
inside a `bash` block in the en file vs. en in the en file — they have already
diverged, and CI green-lights the divergence:

```diff
# en/3-hands-on/3.4-web-widget/_index.md:117-118 (English block)
-# -> open in a desktop browser (Chrome/Firefox/Safari/Edge all work).
-# -> click "Record" -> allow microphone access.

# vi/3-hands-on/3.4-web-widget/_index.md:117-118 (NOT byte-identical to en!)
+# -> mở trong browser desktop (Chrome/Firefox/Safari/Edge đều OK).
+# -> click "Record" -> cho phép microphone access.
```
Verified by:
```bash
diff <(awk '/^```/{c=!c; print; next} c{print}' content/en/3-hands-on/3.4-web-widget/_index.md) \
     <(awk '/^```/{c=!c; print; next} c{print}' content/vi/3-hands-on/3.4-web-widget/_index.md)
```

**Fix:** Two-part:
1. Make the en + vi 3.4 chapter code-block bash comments byte-identical (English
   only, since code blocks are language-neutral per D-49):
   ```diff
   # vi/3-hands-on/3.4-web-widget/_index.md
   -# -> mở trong browser desktop (Chrome/Firefox/Safari/Edge đều OK).
   -# -> click "Record" -> cho phép microphone access.
   +# -> open in a desktop browser (Chrome/Firefox/Safari/Edge all work).
   +# -> click "Record" -> allow microphone access.
   ```
2. Extend `bin/check-i18n-parity.sh` with a third assertion that diffs the
   fenced-block-only projection of every paired vi/en file:
   ```bash
   for f in content/vi/**/_index.md; do
     en="${f/content\/vi/content\/en}"
     [[ -f "$en" ]] || continue
     vi_blocks=$(awk '/^```/{c=!c; print; next} c{print}' "$f")
     en_blocks=$(awk '/^```/{c=!c; print; next} c{print}' "$en")
     if [[ "$vi_blocks" != "$en_blocks" ]]; then
       echo "FAIL: code-block drift in $f vs $en"
       FAIL_COUNT=$((FAIL_COUNT + 1))
       break  # one failure is enough to flip exit code
     fi
   done
   ```

### WR-02: English chapters contain leftover Vietnamese "Phần" — fails the en-only-prose convention

**File:** Multiple en files
- `content/en/_index.md:17`
- `content/en/1-introduction/_index.md:64,89,92,101`
- `content/en/2-preparation/_index.md:13,55,62,100,112,125,145,147,150,153,157,158,159` (~14 hits)
- `content/en/3-hands-on/3.1-knowledge-base/_index.md:9,107,143`
- `content/en/3-hands-on/3.2-pipecat-local/_index.md:9,99,268,297,305,321`
- `content/en/4-cleanup/_index.md:148`
- `content/en/5-summary/_index.md:23,25`

**Issue:** ~30+ occurrences of the Vietnamese word "Phần" in what should be
English-only chapters. This contradicts the project convention "vi files in
Vietnamese, en in English; code identical" and produces awkward sentences like
"run Phần 4 Cleanup" in the en cost-recap. The 3.3, 3.4, 3.5 chapters
consistently use "Section X.Y" (correct) — the inconsistency is a copy-paste
artifact from the vi original.

**Fix:** Global rename in `content/en/**/*.md`:
- `Phần X` → `Section X` (or `Chapter X` for top-level, your choice — pick one).
- Rerun the parity script — code blocks are unaffected; only prose changes.

### WR-03: 5 image references resolve to missing files — broken images in published site

**File:** Multiple chapter files reference `/images/.../*.png` paths that exist
only as `.gitkeep` placeholders:
- `content/{en,vi}/2-preparation/_index.md:52` → `/images/2-preparation/console-bedrock-model-access.png`
- `content/{en,vi}/3-hands-on/3.3-deploy-agentcore/_index.md:31` → `/images/3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png`
- `content/{en,vi}/3-hands-on/3.4-web-widget/_index.md:123` → `/images/3.4-web-widget/widget-idle-state.png`
- `content/{en,vi}/3-hands-on/3.5-observability/_index.md:13` → `/images/3.5-observability/billing-alerts-toggle.png`
- `content/{en,vi}/3-hands-on/3.5-observability/_index.md:47` → `/images/3.5-observability/cloudwatch-dashboard-hera-prod.png`

**Issue:** Verified `find static/images -type f` — directories exist but contain
only `.gitkeep` files; no PNGs are committed. Hugo will render `<img>` tags
pointing at 404 URLs. Five broken images on the production site.

**Fix:** Either (a) commit the actual screenshots under `static/images/...` so
Hugo picks them up, or (b) wrap the `![...]` lines in a Hugo conditional /
remove them until the screenshots land. Option (a) is the path the markdown
clearly assumes — the alt-text is annotated specifically (e.g. "Bedrock Console
— Model Access for Nova 2 Sonic + Titan v2 (ap-northeast-1)").

### WR-04: Inconsistent "Section X" vs "Phần X" terminology in en chapters

**File:** Mixed across `content/en/*.md`

**Issue:** 3.3, 3.4, 3.5 chapters say "Section 3.X" (correct English). 1-introduction,
2-preparation, 3.1, 3.2, 4-cleanup, 5-summary chapters say "Phần X" (Vietnamese
literal copy). Within the same chapter (3.4) you find both "Section 3.3" (line 9)
and "Phần" elsewhere is absent — but this within-set inconsistency makes
cross-chapter navigation jarring for an English-speaking learner.

**Fix:** Ride along with the WR-02 mass rename. Land on a single term — the
hugo-theme-learn convention is "Chapter X" for top-level + "Section X.Y" for
sub-pages, which matches the front-matter `chapter: true` flag at the top-level
`_index.md` files.

### WR-05: 3.5 + 3.4 chapters use "Section X" but 1.x / 2.x / 4 use "Phần" — workshop heading drift

**File:** Same as WR-04, listed separately for follow-up tracking.
**Issue:** Even within the en chapters that DID get translated, "Section 3.X"
vs "Section 4" vs "Section 5" is mixed unpredictably. Examples:
- 3.4-web-widget en says "Section 3.5" (line 148) — correct.
- 4-cleanup en says "Phần 5 wraps up" (line 148) — should be "Chapter 5" or
  "Section 5".
- 5-summary en says "with cleanup per Phần 4" (line 23) — should be "Chapter 4".

**Fix:** Same global rename as WR-04 — pick one terminology and apply uniformly.

### WR-06: Section heading "### Hands-on" + "# Hands-on Steps" double-renders the chapter title

**File:** `content/{en,vi}/3-hands-on/_index.md:9-11` (file not in primary review
list but discovered during scope check — it is part of the parity tree).

**Issue:** The file front-matter sets `title: "Hands-on"` (renders as the page
title via the theme), then the body has `### Hands-on` (h3) immediately followed
by `# Hands-on Steps` (h1). The h3 then h1 sequence is non-semantic — h1 should
precede h3, never follow it, or both should be omitted in favor of the front-
matter `title`. The same anti-pattern appears in `content/{en,vi}/2-preparation/`
("### Preparation" then "# Environment Setup") and `content/{en,vi}/_index.md`
("### Introduction" inside the body).

**Fix:** In hugo-theme-learn, the `title` front-matter is already rendered by
the theme as the page heading — drop the manual h3+h1 lines from the body, or
collapse to a single h2 "Overview" if you want a leading paragraph anchor.

## Info

### IN-01: `bin/check-i18n-parity.sh` does not validate `find` output ordering across platforms

**File:** `bin/check-i18n-parity.sh:39-40`
**Issue:** `find -name "_index.md" -type f | sed ... | sort` — relies on `sort`
being LC_COLLATE-stable across platforms. On Windows Git Bash the default
collation can differ from Linux glibc when filenames contain non-ASCII
characters. v1 paths are pure ASCII, so this is currently fine; flag for
follow-up if vi-localized slugs are ever introduced (D-49 says slugs stay en
verbatim, so unlikely to bite).
**Fix:** Add `LC_ALL=C sort` to harden:
```bash
VI_SLUGS=$(find content/vi -name "_index.md" -type f | sed 's|^content/vi/||' | LC_ALL=C sort)
EN_SLUGS=$(find content/en -name "_index.md" -type f | sed 's|^content/en/||' | LC_ALL=C sort)
```

### IN-02: Hugo `disableLandingPageButton = true` parameter may not be honored by the theme variant

**File:** `config.toml:28`
**Issue:** `disableLandingPageButton` is a hugo-theme-learn convention; we
verified the theme submodule isn't checked out (CR-01) so we can't confirm the
parameter is read by the theme. Flag for follow-up after CR-01 lands.
**Fix:** Run `hugo server -D` after the submodule lands, confirm there is no
"home" call-to-action button on the landing page; if it's still present, switch
to the theme-specific override path or keep this param even if unused (cost: 0).

### IN-03: `themeVariant = "workshop"` references a custom variant that may not exist in the upstream theme

**File:** `config.toml:29`
**Issue:** hugo-theme-learn ships built-in variants `red`, `blue`, `green`,
`purple`, `mine`, `relearn-bright`, `relearn-dark`, `relearn-light`, etc. —
"workshop" is not a default. With the submodule unchecked-out (CR-01) we cannot
confirm whether a custom `themes/hugo-theme-learn/static/css/theme-workshop.css`
exists. If it doesn't, the theme falls back to default styling and the param is
a silent no-op.
**Fix:** Either (a) add `static/css/theme-workshop.css` under `static/` (Hugo's
overrides path beats the theme's), or (b) replace with a known-good variant
like `themeVariant = "blue"` to remove the unknown.

### IN-04: 5-summary `## Thanks` paragraph references "URL from `config.toml` `baseURL`" but the en-prose context is awkward

**File:** `content/en/5-summary/_index.md:72`
**Issue:** "Issues / improvements: PR into the workshop repo on GitHub (URL from
`config.toml` `baseURL`)." The `baseURL` is `https://KenzyTran.github.io/hera/`
— that's the deployed-site URL, not the source-repo URL. A learner clicking
"PR into the workshop repo" can't PR against a `.github.io` URL. The vi mirror
has the same wording.
**Fix:** Replace with the literal repo URL or a placeholder:
```markdown
Issues / improvements: open a PR at <https://github.com/KenzyTran/hera>.
```
Apply to en + vi together to keep parity.

---

_Reviewed: 2026-05-07T05:03:49Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
