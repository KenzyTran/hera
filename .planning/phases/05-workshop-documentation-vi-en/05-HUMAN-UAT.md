---
status: partial
phase: 05-workshop-documentation-vi-en
source: [05-VERIFICATION.md]
started: 2026-05-07T06:25:53Z
updated: 2026-05-07T06:25:53Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. First organic CI build of the GitHub Pages workflow
expected: Workflow fires on push to master: Install Hugo CLI -> Checkout (submodules: recursive fetches themes/hugo-theme-learn at sha 3202533a) -> Check vi/en parity (DOC-12, exits 0) -> Setup Pages -> Build with Hugo (theme resolves; all 22 bilingual _index.md rendered) -> Upload artifact -> Deploy. Final Pages URL serves all 11 chapters in both Vietnamese and English with language switcher navigating between /vi/ and /en/ trees.
why_human: CI build runs on GitHub-hosted infrastructure, requires push to a configured remote, and requires GitHub Pages enabled on the repository. No remote is currently configured (`git remote -v` is empty). This cannot be verified by static codebase inspection alone. The codebase artifacts — submodule gitlink, deploy.yml trigger on master, parity gate wired before Hugo build — are all correct; the first organic build is the only remaining blocker for SC#1 to be fully observable.
result: [pending]

### 2. First learner walkthrough end-to-end from a fresh AWS account on the published Pages site
expected: A Cloud Clubs member with no prior knowledge of this repo lands on the published Pages URL, follows Chapter 1 -> Chapter 2 -> Section 3.1-3.5 -> Chapter 4 -> Chapter 5 in either Vietnamese or English. Copy-pastes snippets (all instructor literals now replaced with `<your-*>` placeholders + resolution commands), captures screenshots where prompted, deploys their own KB + AgentCore + widget, talks to the agent through HTTPS browser, tears down to verified $0 ongoing cost (via Cost Explorer 24h post-destroy + bin/cleanup-verify.sh all-green).
why_human: Requires real AWS account, real human reading workshop content, real microphone hardware, real Cost Explorer 24h propagation. Pure-code verification cannot test "a fresh learner reaches the working voice loop end-to-end". SC#2 and SC#3 are inherently human-verifiable; the static content that gates them (instructor data redacted, Phần tokens gone) is now confirmed clean.
result: [pending]

### 3. Operator screenshot sweep to close DOC-11 (6 PNGs across 5 chapters)
expected: |
  Operator captures and annotates per D-44 (red box + arrow + label):
  (a) static/images/2-preparation/console-bedrock-model-access.png
  (b) static/images/3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png
  (c) static/images/3.4-web-widget/widget-idle-state.png
  (d) static/images/3.5-observability/billing-alerts-toggle.png
  (e) static/images/3.5-observability/cloudwatch-dashboard-hera-prod.png
  (f) static/images/4-cleanup/cleanup-verify-output.png
  Hugo renders proper image elements after PNGs land; DOC-11 flips to Complete in REQUIREMENTS.md.
why_human: AWS Console UI screenshots cannot be auto-generated; require live AWS login + manual capture + annotation. Already tracked in 04-HUMAN-UAT.md item #3 and REQUIREMENTS.md DOC-11 Pending.
result: [pending]

### 4. Code-block byte-parity drift in 3.4-web-widget (WR-01 from prior REVIEW — operator decision required)
expected: |
  Operator decides between:
  (a) reverting vi bash comments at content/vi/3-hands-on/3.4-web-widget/_index.md lines 117-118 to English and optionally extending bin/check-i18n-parity.sh with a third fenced-block parity assertion, OR
  (b) accepting the drift as low-impact prose comment translation (D-50 minimal-parity-only stance retained).
why_human: Extends a judgment call that predates 05-05. D-50 explicitly rejected per-section heading parity to avoid false positives; code-block byte parity is the same class of judgment call. Operator must decide whether the D-49 byte-parity invariant is enforced strictly for bash comments inside fences, or treated as a soft convention for prose-only drift. Neither path blocks the phase goal; this is a quality/convention decision.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
