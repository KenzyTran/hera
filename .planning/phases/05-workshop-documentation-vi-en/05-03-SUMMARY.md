---
phase: 05-workshop-documentation-vi-en
plan: 03
subsystem: workshop-docs
tags: [docs, hugo, vi-en, deploy, agentcore, web-widget, observability]
dependency-graph:
  requires:
    - phase 05 plan 02 (parity gate live + 8 _index.md tree to extend)
    - phase 03 (live evidence: bin/push-image.sh, bin/build-widget.sh, bin/smoke-deploy.sh, frontend/, infra/cdk/)
    - phase 04 (live evidence: infra/modules/observability/, RUNBOOK Phase 4 sections, agent/hera_agent/main.py POST /invocations stub)
  provides:
    - "content/vi/3-hands-on/3.3-deploy-agentcore/_index.md (DOC-05 vi)"
    - "content/en/3-hands-on/3.3-deploy-agentcore/_index.md (DOC-05 en)"
    - "content/vi/3-hands-on/3.4-web-widget/_index.md (DOC-06 vi)"
    - "content/en/3-hands-on/3.4-web-widget/_index.md (DOC-06 en)"
    - "content/vi/3-hands-on/3.5-observability/_index.md (DOC-07 vi)"
    - "content/en/3-hands-on/3.5-observability/_index.md (DOC-07 en)"
    - "static/images/3.3-deploy-agentcore/.gitkeep (D-44 #3 placeholder)"
    - "static/images/3.4-web-widget/.gitkeep (D-44 #4 placeholder)"
    - "static/images/3.5-observability/.gitkeep (D-44 #2 + #5 placeholders)"
  affects:
    - .planning/REQUIREMENTS.md (DOC-05 + DOC-06 + DOC-07 + DOC-10 flipped to [x])
    - .planning/STATE.md (Plan 05-03 complete; progress 89% -> 94%; 16 -> 17 plans)
    - .planning/ROADMAP.md (Phase 5 progress 2/4 -> 3/4)
tech-stack:
  added: []
  patterns: [hugo-theme-learn-notice-shortcode, d49-vi-en-same-commit, d42-source-footer, d44-image-placeholder, d47-region-default, d24-hybrid-iac-explainer, d30-concurrency-cap-instructor-sidebar, d35-manual-stop-fallback, d36-no-per-ip-rate-limit, d51-pitfall-callout]
key-files:
  created:
    - content/vi/3-hands-on/3.3-deploy-agentcore/_index.md
    - content/en/3-hands-on/3.3-deploy-agentcore/_index.md
    - content/vi/3-hands-on/3.4-web-widget/_index.md
    - content/en/3-hands-on/3.4-web-widget/_index.md
    - content/vi/3-hands-on/3.5-observability/_index.md
    - content/en/3-hands-on/3.5-observability/_index.md
    - static/images/3.3-deploy-agentcore/.gitkeep
    - static/images/3.4-web-widget/.gitkeep
    - static/images/3.5-observability/.gitkeep
  modified:
    - .planning/REQUIREMENTS.md (DOC-05/06/07/10 flipped to [x]; DOC-02/03/04 traceability-table catch-up sweep)
    - .planning/ROADMAP.md (Phase 5 row 2/4 -> 3/4; 05-03 plan row [x])
    - .planning/STATE.md (frontmatter + Current Position + Velocity + Session Continuity)
decisions:
  - "Plan 05-03 honors D-49 vi-first-then-en-same-commit verbatim — 4 atomic commits (1 chore + 3 feat) with vi+en for one chapter landing in one commit per chapter."
  - "D-44 #3 Service Quotas screenshot moved into instructor-reference info notice (per plan content) rather than learner-mainline path — workshop default is concurrency cap=10 (no learner action needed); D-30 cap=2 is instructor-only optimization."
  - "DOC-10 satisfied with 8 of 8 D-51 pitfall callouts placed across Phases 1+2+3 chapters (Plans 05-01..05-03 cumulative); literal target was Top 5-7."
  - "Source footer count per file averages 7-8 (well above min 5 in plan acceptance criteria); each fenced bash block has its own footer per D-42."
  - "All cdk-deploy + terraform-apply paste-blocks reuse the literal RUNBOOK source verbatim (no paraphrase), so when RUNBOOK drifts, a docs-only follow-up plan re-syncs without re-deriving commands."
metrics:
  duration: ~25 min
  tasks: 4
  files_created: 9
  files_modified: 3
  commits: 4
  completed: 2026-05-07
---

# Phase 5 Plan 03: Phần 3.3 Deploy AgentCore + Phần 3.4 Web Widget + Phần 3.5 Observability Summary

3 sub-pages published bilingual covering deploy → live widget → observability — the arc from local agent (Phần 3.2) to a fully-deployed conversation on a public HTTPS URL with a CloudWatch dashboard watching it.

## What was built

- **Phần 3.3 Deploy AgentCore (DOC-05):** sub-page mirroring RUNBOOK Phase 3 + Phase 4 protocol-bridge sections. Walks `bin/push-image.sh` (multi-arch buildx → ECR), `cdk deploy hera-agentcore` (CDK Python — D-24 hybrid IaC), second-pass `terraform apply -var=agentcore_runtime_arn=<arn>` (Plan 03-04 4-step lifecycle), `bin/smoke-deploy.sh` end-to-end gate, and the `POST /invocations` AgentCore HTTP protocol stub from Plan 04-01. Hybrid IaC trade-off (Terraform owns everything except AgentCore Runtime; CDK Python owns the single Runtime resource) explicitly documented. D-30 concurrency cap=2 moved to instructor-reference sidebar; learners run on default cap=10. 8 D-42 Source footers per side; 181 lines.
- **Phần 3.4 Web Widget (DOC-06):** sub-page covering frontend/ structure, presigner Lambda Function URL bridge (D-25 Rule-4 — browser cannot SigV4-sign WS upgrades), `bin/build-widget.sh` sed-injection of `__PRESIGN_URL__`, deploy widget to S3+CloudFront, mic permission UX (5-state record-button table from UI-SPEC + verbatim WID-06 error strings with em-dash preserved per Plan 03-02 rationale), AudioWorklet 16 kHz Int16 capture path. **D-51 #4 HTTPS-required-for-mic warning callout** placed at the local-vs-CloudFront comparison. 7 D-42 Source footers per side; 148 lines.
- **Phần 3.5 Observability (DOC-07):** sub-page walking CloudWatch dashboard `hera-prod` (5 panels: active sessions, latency p50/p95, error rate via metric_query arithmetic, Bedrock invocations+tokens, billing widget cross-region from us-east-1), 2 operational alarms (`hera-error-rate-prod`, `hera-latency-p95-prod`), 1 billing alarm `hera-billing-prod` in us-east-1 (AWS/Billing namespace cross-region constraint). AgentCore concurrency cap (default 10, instructor cap=2 D-30) explained as the rate-limit gate with OBS-04/OBS-05 trade-offs (D-35 `alarm_actions=[]` manual-stop fallback, D-36 no per-IP rate limit on presigner Function URL). **D-51 #5 billing alarm 24h propagation warning callout** placed. 7 D-42 Source footers per side; 119 lines.
- **3 .gitkeep placeholders** (`static/images/{3.3-deploy-agentcore,3.4-web-widget,3.5-observability}/.gitkeep`) — directories tracked so chapter image markdown references render alt-text-only placeholder until operator drops PNGs in.

## Commits

| # | Hash | Type | Description |
|---|------|------|-------------|
| 1 | `326b893` | chore | create static/images/<chapter>/.gitkeep placeholders (Task 1) |
| 2 | `ffb8d01` | docs | author Phan 3.3 Deploy AgentCore in vi+en (D-49) (Task 2) |
| 3 | `2885030` | docs | author Phan 3.4 Web Widget in vi+en (D-49) (Task 3) |
| 4 | `f48d8f3` | docs | author Phan 3.5 Observability in vi+en (D-49) (Task 4) |

## Pitfall callouts placed in this plan (D-51)

| # | Callout | Chapter | Files |
|---|---------|---------|-------|
| #4 | HTTPS required for microphone | Phần 3.4 (Bước 2 Mở widget URL) | content/{vi,en}/3-hands-on/3.4-web-widget/_index.md |
| #5 | Billing alarm 24h propagation lag | Phần 3.5 (Alarms section, after the 3-row table) | content/{vi,en}/3-hands-on/3.5-observability/_index.md |

DOC-10 status post-plan: **8 of 8 listed D-51 pitfalls placed across Phases 1+2+3 chapters** (Plans 05-01..05-03 cumulative): #1 8-min cap (3.2), #2 sample rate (3.2), #3 model access (Phần 2), #4 HTTPS-for-mic (3.4), #5 billing alarm (3.5), #6 tool-use schema (3.2), #7 bilingual parity (Phần 1), #8 KB sync delay (3.1). 8 placed exceeds the "Top 5-7" target — DOC-10 flipped to `[x]`.

## Image markdown references (D-44 — operator follow-up sweep inputs)

The plan inserts inline markdown image references; the operator captures the PNGs from AWS Console / live widget UI in a deferred sweep. Hugo renders alt-text-only placeholder until each PNG file lands.

| D-44 | Filename | Used in chapter |
|------|----------|-----------------|
| #3 | `static/images/3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png` | Phần 3.3 (instructor-reference info notice — D-30 cap=2 quota request) |
| #4 | `static/images/3.4-web-widget/widget-idle-state.png` | Phần 3.4 (Bước 2 Mở widget URL — widget hero) |
| #2 | `static/images/3.5-observability/billing-alerts-toggle.png` | Phần 3.5 (Pre-flight Receive Billing Alerts toggle) |
| #5 | `static/images/3.5-observability/cloudwatch-dashboard-hera-prod.png` | Phần 3.5 (Bước 2 dashboard walk-through hero) |

D-44 #1 (Bedrock Console — Model Access for Nova Sonic + Titan v2) was already inserted by Plan 05-02 in Phần 2 with `.gitkeep` at `static/images/2-preparation/`.

## Trade-off attribution paragraphs (CONTEXT carried)

| Trade-off | Decision ID | Where documented |
|-----------|-------------|------------------|
| Hybrid IaC: Terraform owns everything except AgentCore Runtime; CDK Python owns the single Runtime resource | D-24 | Phần 3.3 — H2 "Hybrid IaC: Terraform + CDK Python (D-24)" |
| AgentCore concurrency: cap=10 default for learners; cap=2 instructor-only optimization | D-30 | Phần 3.3 — H2 "Bước 0: AgentCore concurrency mặc định (cap=10)" + instructor-reference info notice |
| Billing alarm `alarm_actions=[]` no SNS hook; manual-stop fallback via `aws bedrock-agentcore-control update-agent-runtime --status STOPPED` or `cdk destroy hera-agentcore` | D-35 | Phần 3.5 — H2 "OBS-05 trade-off — billing alarm manual-stop fallback (D-35)" |
| Presigner Lambda Function URL OPEN; no per-IP rate limit; AgentCore concurrency cap is the gate; v2 adds WAF or token-bucket | D-36 | Phần 3.5 — H2 "OBS-04 trade-off — không có per-IP rate limit (D-36)" |

## Verification

- `bash bin/check-i18n-parity.sh` exits `0` post-plan: file count parity (vi=11, en=11) + bidirectional slug-tree parity both PASS.
- `find content/vi -name "_index.md" -type f | wc -l` = `11`.
- `find content/en -name "_index.md" -type f | wc -l` = `11`.
- `find content/vi content/en -type d -path "*3-hands-on/3.[3-5]-*" | wc -l` = `6` (3 sub-pages × 2 langs).
- `find static/images/3.3-deploy-agentcore static/images/3.4-web-widget static/images/3.5-observability -name ".gitkeep" | wc -l` = `3`.
- Source-footer audit per file: `8, 7, 7, 8, 7, 7` (all >= 5 plan acceptance min).
- Pitfall callout count across the 6 new files: `4` (1 in 3.4 vi+en + 1 in 3.5 vi+en) — matches plan verification target.
- Emoji audit: zero matches across all 6 new files (`grep -cP '[\x{1F300}-\x{1F9FF}]'`).
- Submodule untouched: `git diff --submodule themes/hugo-theme-learn` empty.
- 4 unique D-44 image markdown references inserted (`/images/3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png`, `/images/3.4-web-widget/widget-idle-state.png`, `/images/3.5-observability/billing-alerts-toggle.png`, `/images/3.5-observability/cloudwatch-dashboard-hera-prod.png`).

## Deviations from Plan

None — plan executed exactly as written. No Rule-1/2/3/4 deviations during execution.

## Authentication gates

None encountered — Phase 5 is docs-only with zero AWS API calls.

## Deferred operator action (non-blocking)

- **Capture 4 PNGs and commit them to `static/images/<chapter>/`** for D-44 #2/#3/#4/#5 inventory items. Hugo currently renders alt-text-only placeholders; chapters are publishable as-is. This is the same operator-deferred sweep that Plan 05-02 opened for D-44 #1. DOC-11 stays unflipped pending this sweep.

## Live state (unchanged this plan)

Plan 05-03 is docs-only — zero AWS API calls. Live state from Phase 4 unchanged:

- AgentCore Runtime `hera_agent-GIsf2P4ImD` v3 (image `hera-agent:7e72b66`).
- Widget URL `https://dg0w939ktclw6.cloudfront.net/`.
- CloudWatch dashboard `hera-prod` + 3 alarms (2 op in ap-northeast-1 + 1 billing in us-east-1).
- 5 deferred-by-design items in `04-HUMAN-UAT.md` — none blocking.

## Self-Check: PASSED

Files verified:

- FOUND: content/vi/3-hands-on/3.3-deploy-agentcore/_index.md
- FOUND: content/en/3-hands-on/3.3-deploy-agentcore/_index.md
- FOUND: content/vi/3-hands-on/3.4-web-widget/_index.md
- FOUND: content/en/3-hands-on/3.4-web-widget/_index.md
- FOUND: content/vi/3-hands-on/3.5-observability/_index.md
- FOUND: content/en/3-hands-on/3.5-observability/_index.md
- FOUND: static/images/3.3-deploy-agentcore/.gitkeep
- FOUND: static/images/3.4-web-widget/.gitkeep
- FOUND: static/images/3.5-observability/.gitkeep

Commits verified in git log:

- FOUND: 326b893 (chore Task 1)
- FOUND: ffb8d01 (feat Task 2 — Phần 3.3 vi+en)
- FOUND: 2885030 (feat Task 3 — Phần 3.4 vi+en)
- FOUND: f48d8f3 (feat Task 4 — Phần 3.5 vi+en)
