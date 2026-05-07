---
phase: 05-workshop-documentation-vi-en
reviewed: 2026-05-07T00:00:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - .gitmodules
  - .github/workflows/deploy.yml
  - content/vi/3-hands-on/3.1-knowledge-base/_index.md
  - content/en/3-hands-on/3.1-knowledge-base/_index.md
  - content/vi/3-hands-on/3.2-pipecat-local/_index.md
  - content/en/3-hands-on/3.2-pipecat-local/_index.md
  - content/vi/3-hands-on/3.3-deploy-agentcore/_index.md
  - content/en/3-hands-on/3.3-deploy-agentcore/_index.md
  - content/vi/3-hands-on/3.5-observability/_index.md
  - content/en/3-hands-on/3.5-observability/_index.md
  - content/en/_index.md
  - content/en/1-introduction/_index.md
  - content/en/2-preparation/_index.md
  - content/en/4-cleanup/_index.md
  - content/en/5-summary/_index.md
findings:
  critical: 0
  warning: 2
  info: 1
  total: 3
status: issues_found
---

# Phase 5 (re-review after 05-05): Code Review Report

**Reviewed:** 2026-05-07
**Depth:** standard
**Files Reviewed:** 15 source files (16 listed in config; `.gitmodules` is one file, all 15 source files were inspected)
**Status:** issues_found

## Summary

This re-review covers the gap closure (plan 05-05) that addressed the prior CR-01
(submodule), CR-02 (instructor data) and WR-02 (Phần) findings. The closure work
is solid:

- **Submodule registration (`.gitmodules`)** — syntactically valid Git config;
  `git submodule status` reports the registered SHA `3202533a` for
  `themes/hugo-theme-learn` (matcornic 2.5.0-27-g3202533) cleanly. CR-01 closed.
- **Instructor literal redaction** — grep against the 4 known literals
  (`851725411875`, `hera_agent-GIsf2P4ImD`, `BKXE19AH89`, `dg0w939ktclw6`)
  returns zero matches across `content/`. CR-02 closed.
- **`Phần`/`Bước`/`Chương` removal in `content/en/`** — grep finds zero
  Vietnamese-language scaffolding terms (incl. `Mục tiêu`, `Tiếp theo`,
  `Phần này`, `Cấu trúc`, `Lưu ý`) in any of the 11 English `_index.md` files.
  WR-02 closed.
- **`deploy.yml` branch trigger** — the only branch literal in the workflow is
  `master` on line 5; no stray `main` references elsewhere in the file.
- **vi/en parity** — `bin/check-i18n-parity.sh` reports `vi=11, en=11` slug-tree
  parity passes; line counts of pairs are within 1 line of each other (e.g.
  vi=29 vs en=29 for `_index.md`, vi=116 vs en=117 for `1-introduction`).
- **Hugo shortcodes** — `{{% notice %}}` open/close pairs are balanced in
  every reviewed file (count even on every file: 2/2, 4/4, 6/6).
- **Code fences** — fence counts are even in every reviewed file (e.g.
  16 in 3.3 en/vi, balanced).

Two new defects and one nit were introduced by the redaction work itself.
They are placeholder-naming and placeholder-coverage problems, not security
or build issues. Both warnings are isolated to the smoke-output success block
in `3-hands-on/3.3-deploy-agentcore/_index.md` (vi+en, identical bytes).

## Warnings

### WR-01: Inconsistent placeholder name `<your-account>` vs `<your-account-id>`

**File:** `content/en/3-hands-on/3.3-deploy-agentcore/_index.md:134` and
`content/vi/3-hands-on/3.3-deploy-agentcore/_index.md:134`

**Issue:** The smoke-output success block prints the Runtime ARN as
`arn:aws:bedrock-agentcore:ap-northeast-1:<your-account>:runtime/...`,
while the "Reference values (resolve from your own deploy)" section 27 lines
below uses `<your-account-id>` for the same value (line 161:
``Account: `<your-account-id>` — resolve via `aws sts get-caller-identity`...``).

The two placeholders refer to the same AWS account ID, but a learner doing
the natural copy-paste-and-search workflow ("I see `<your-account>` in the
output — where is that resolved?") will not find a hit because the resolution
bullet uses `<your-account-id>`. This is the exact failure mode CR-02's fix
was supposed to prevent.

**Fix:** Rename the placeholder in the smoke success block on line 134 of
both files to match the rest of the document:

```text
Runtime ARN : arn:aws:bedrock-agentcore:ap-northeast-1:<your-account-id>:runtime/...
```

Apply identically in `content/en/3-hands-on/3.3-deploy-agentcore/_index.md`
and `content/vi/3-hands-on/3.3-deploy-agentcore/_index.md` (byte-parity for
this fragment is preserved per D-49 since both files already share the same
literal).

### WR-02: `<your-fn-url>` placeholder has no resolution command

**File:** `content/en/3-hands-on/3.3-deploy-agentcore/_index.md:133` and
`content/vi/3-hands-on/3.3-deploy-agentcore/_index.md:133`

**Issue:** The smoke success block prints
`Presign URL : https://<your-fn-url>.lambda-url.ap-northeast-1.on.aws/`
which introduces the placeholder name `<your-fn-url>`. However, the
"Reference values (resolve from your own deploy)" bullet list 27 lines
below (lines 159-165) documents resolution commands for **5** placeholders —
account, region, runtime, live URL, cost — but **omits** `<your-fn-url>`.

The closest mention is line 122 ("Reads the `presign_url` output, exports it
as `PRESIGN_URL`") which describes what `bin/smoke-deploy.sh` does
internally, not how a learner reading the rendered output should resolve
the placeholder by hand. A learner who did not run `smoke-deploy.sh`
(e.g. ran the manual 4-step lifecycle) sees the literal `<your-fn-url>` in
the docs but no cited path to map it to their actual function URL.

The plan-05-05 contract stated all instructor literals would be replaced with
"placeholders + cited resolution commands" — this is the only placeholder in
the redacted set whose resolution command is missing from the reference
list.

**Fix:** Add a sixth bullet to the "Reference values" list (after line 165)
in both files:

en (`content/en/3-hands-on/3.3-deploy-agentcore/_index.md`):
```markdown
- Presign URL: `https://<your-fn-url>.lambda-url.ap-northeast-1.on.aws/` — resolve via `terraform -chdir=infra/envs/prod output -raw presign_url` after Step 3.5 second-pass apply.
```

vi (`content/vi/3-hands-on/3.3-deploy-agentcore/_index.md`):
```markdown
- Presign URL: `https://<your-fn-url>.lambda-url.ap-northeast-1.on.aws/` — resolve qua `terraform -chdir=infra/envs/prod output -raw presign_url` sau Step 3.5 second-pass apply.
```

The `presign_url` Terraform output is already documented elsewhere on the
same page (line 104 / 122) and on `3.4-web-widget/_index.md:105`, so this is
just a missing cross-reference, not new infra work.

## Info

### IN-01: `deploy.yml` master-only trigger is intentional but creates forward coupling

**File:** `.github/workflows/deploy.yml:5`

**Issue:** The workflow trigger `branches: ["master"]` is correct for the
current state (active branch is `master`, no remote configured yet, per
context). The step on line 39 invokes `bash bin/check-i18n-parity.sh` and
the script exists; running it locally returns
`2/2 parity assertions passed`, so the CI gate is wired correctly.

This is a forward-coupling nit only: when `origin/main` eventually exists
(GitHub Pages convention), this file will need to re-add or replace the
trigger. No action required for Phase 5; flagging so the GitHub Pages
publish phase notices.

**Fix:** None for v1. Track for the publish phase: decide between adding
`main` back to the trigger list, renaming the local branch, or keeping
`master`-only deploy.

---

## Items checked and confirmed clean

- `.gitmodules` syntactic validity (verified via `git submodule status`
  and `git ls-files --stage`).
- All 4 instructor literals scrubbed from `content/` (zero grep hits for
  `851725411875`, `hera_agent-GIsf2P4ImD`, `BKXE19AH89`, `dg0w939ktclw6`).
- All Vietnamese-language scaffolding terms removed from `content/en/`
  (zero grep hits for `Phần`, `Bước`, `Chương`, `Mục tiêu`, `Tiếp theo`,
  `Cấu trúc`, `Lưu ý`, `Phần này`).
- Hugo `{{% notice %}}` shortcode pairing balanced in every reviewed file.
- Code fence count balanced in every reviewed file.
- vi/en file-count + slug-tree parity (`bin/check-i18n-parity.sh` 2/2 PASS).
- `deploy.yml` branch trigger consistency (no stray `main` references
  anywhere in the file).
- Cross-references (`Section 3.x`, `Chapter N`, `Step N`) all resolve
  internally in `content/en/` (76 references across 10 files, none orphan).
- AWS CLI snippets cited next to placeholders are syntactically correct
  (`aws sts get-caller-identity --query Account --output text`,
  `terraform -chdir=infra/envs/prod output -raw kb_id`,
  `jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json`,
  `aws bedrock-agentcore-control update-agent-runtime --agent-runtime-id
  <your-runtime-id> --region ap-northeast-1 --status STOPPED`).
- Mermaid diagrams in `1-introduction/_index.md` use balanced fences and
  valid `flowchart LR` / `sequenceDiagram` syntax.
- en/_index.md correctly mirrors vi/_index.md shape (same table layout,
  same `{{% children depth="1" %}}` shortcode usage).

---

_Reviewed: 2026-05-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Re-review scope: gap closure for prior CR-01, CR-02, WR-02 (plan 05-05).
Earlier 05-REVIEW.md (2026-05-07T05:03:49Z, 24 files reviewed) is
superseded by this report._
