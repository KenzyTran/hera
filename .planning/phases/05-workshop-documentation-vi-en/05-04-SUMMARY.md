---
phase: 05-workshop-documentation-vi-en
plan: 04
subsystem: workshop-content
tags: [docs, hugo, bilingual, cleanup, summary, doc-08, doc-09]
dependency_graph:
  requires:
    - .planning/phases/05-workshop-documentation-vi-en/05-03-SUMMARY.md
    - RUNBOOK.md (Phase 4 Cleanup quy trinh + Verify $0 ongoing cost sections)
    - bin/cleanup-verify.sh
  provides:
    - content/vi/4-cleanup/_index.md (Phần 4 Cleanup chapter, single-page)
    - content/en/4-cleanup/_index.md (Phần 4 Cleanup chapter, single-page)
    - content/vi/5-summary/_index.md (Phần 5 Summary chapter, single-page)
    - content/en/5-summary/_index.md (Phần 5 Summary chapter, single-page)
    - static/images/4-cleanup/.gitkeep (placeholder for D-44 #6 hero PNG, deferred)
  affects:
    - .planning/REQUIREMENTS.md (DOC-08 + DOC-09 flipped to [x]; DOC-11 stays Pending)
    - .planning/ROADMAP.md (Phase 5 row -> Complete; 05-04 row -> [x])
    - .planning/STATE.md (Phase 5 -> COMPLETE; progress 100%; v1 milestone reached)
tech-stack:
  added: []
  patterns:
    - "Single-page Phần section (D-41) for closure chapters — Phần 4 Cleanup + Phần 5 Summary stay one _index.md each (no sub-pages), unlike Phần 3 which splits 5 ways per D-40."
    - "{{% notice info %}} deferred-callout pattern (per checker BLOCKER 4 option b) for screenshots that ship in a follow-up commit — preserves chapter completeness while honoring demo budget (operator captures PNG post-workshop, single follow-up commit replaces the callout with the image markdown reference)."
    - "Cost recap as ballpark + post-launch placeholder paragraph (per checker WARNING 2 option a) — single paragraph anchored to D-54 ~$2-5 USD/2-hour session, no per-service breakdown table; deferred to instructor's actual 24h Cost Explorer pull (04-HUMAN-UAT item #4)."
    - "DOC-09 expansion roadmap as 4 H3 sub-sections per chapter — Twilio + multi-language + multi-agent + conversation history persistent — each with its v2 requirement IDs cited verbatim (TWIL-01..03, I18N-01..02, ADV-01, ADV-03)."
key-files:
  created:
    - static/images/4-cleanup/.gitkeep
    - .planning/phases/05-workshop-documentation-vi-en/05-04-SUMMARY.md
  modified:
    - content/vi/4-cleanup/_index.md (replaced FCJ-template stub; 147 lines)
    - content/en/4-cleanup/_index.md (replaced FCJ-template stub; 148 lines)
    - content/vi/5-summary/_index.md (replaced FCJ-template stub; 82 lines)
    - content/en/5-summary/_index.md (replaced FCJ-template stub; 82 lines)
    - .planning/REQUIREMENTS.md (DOC-08 + DOC-09 -> [x]; traceability table updated)
    - .planning/ROADMAP.md (Phase 5 + 05-04 rows -> complete)
    - .planning/STATE.md (Phase 5 closed; progress 100%)
decisions:
  - "Phần 4 ships text-only for the cleanup-verify hero section (per checker BLOCKER 4 option b) — D-44 #6 PNG deferred to follow-up commit pending 04-HUMAN-UAT item #3 first organic cleanup-verify run; inline {{% notice info %}} callout records the deferral instead of inserting a broken image link."
  - "Phần 5 cost section ships as ballpark + placeholder paragraph (per checker WARNING 2 option a) — drops the per-service breakdown table; instructor's actual 24h Cost Explorer pull (04-HUMAN-UAT item #4) lands as a follow-up commit replacing the placeholder paragraph with the real per-service numbers."
  - "DOC-11 stays Pending — D-44 #6 hero is text-only with deferred-callout, no PNG markdown reference shipped to chapter body. DOC-11 literal acceptance ('screenshot AWS console with annotation') is not yet met; the operator-PNG sweep tracked in 04-HUMAN-UAT.md item #3 + 05-02/05-03 deferred PNG captures will close DOC-11 in a follow-up commit."
metrics:
  duration: ~20 min
  tasks_completed: 3
  files_created: 1
  files_modified: 7
  commits: 3 (chore .gitkeep + 2 chapter feat commits per D-49)
  completed: 2026-05-07
---

# Phase 5 Plan 04: Phần 4 Cleanup + Phần 5 Summary (vi+en) Summary

Closing 2 chapters of the workshop authored bilingual: Phần 4 Cleanup (DOC-08) walks the 3-step destroy-then-verify quy trinh from RUNBOOK Phase 4 with the 24h-deferred Cost Explorer paste-line and the D-44 #6 hero screenshot deferred to a follow-up commit; Phần 5 Summary (DOC-09) wraps with a D-54 cost ballpark, a 4-section expansion roadmap (Twilio, multi-language, multi-agent, conversation history persistent) citing all v2 requirement IDs, and an attribution to AWS Cloud Clubs Vietnam — closing Phase 5 and reaching the v1 milestone with vi=11 en=11 chapter parity intact.

## What was built

### Task 1: static/images/4-cleanup/.gitkeep (commit 061958e)

Empty placeholder file under `static/images/4-cleanup/` so the directory is tracked in git. The eventual `cleanup-verify-output.png` (D-44 #6 hero) will land alongside this `.gitkeep` in a follow-up commit after the operator runs the post-workshop-close cleanup-verify sweep against actually-torn-down state (04-HUMAN-UAT.md item #3 — first organic run).

### Task 2: Phần 4 Cleanup vi+en (commit 3354893; same atomic commit per D-49)

`content/{vi,en}/4-cleanup/_index.md` replaced — was an FCJ-template stub (24 lines) with placeholder "Delete EC2 / Security Group / VPC" content irrelevant to Hera's stack. Now both files are 147+148-line single-page chapters with 9 H2 sections covering:

1. Lead `{{% notice warning %}}` callout — "Đừng bỏ qua phần này" / "Don't skip this chapter" — anchors the cleanup-imperative tone with explicit cost-driver naming (AgentCore Runtime + Bedrock KB + S3 Vectors + CloudFront keep billing) and the D-38 24h Cost Explorer follow-up pointer.
2. Mục tiêu phần này / Goal of this chapter — 1-paragraph framing.
3. Cleanup contract: thứ tự bắt buộc (D-24) / Cleanup contract: required ordering (D-24) — 3-paragraph explainer for CDK-first / Terraform-second ordering, verify-only script (D-39 — operator destroys, script verifies), and `HERA_REGION` pin guidance.
4. Bước 1: cdk destroy hera-agentcore — paste-block + Source footer + 30-60s timing note.
5. Bước 2: terraform destroy — paste-block + Source footer + extra `{{% notice warning %}}` callout for the CloudFront 15-30 minute disable-then-delete cycle (DO NOT interrupt; Ctrl+C leaves distribution stuck at `Enabled=false, Deployed=true`).
6. Bước 3: bin/cleanup-verify.sh — paste-block + Source footer + 5-bullet description of the 19 read-only checks + helper-function shape (`_check_gone` / `_check_count_zero`) + Windows-bash `MSYS_NO_PATHCONV=1` quirk note + expected success block + `{{% notice info %}}` deferred-callout for the D-44 #6 PNG.
7. Nếu cleanup-verify FAIL / If cleanup-verify FAILs — common causes (Step 1/2 reversed, CloudFront cycle interrupted, ECR repo with images) + ECR `batch-delete-image` fallback paste-block with Source footer + `var.force_delete = true` alternative.
8. Verify $0 ongoing cost (24h sau destroy — D-38) / Verify $0 ongoing cost (24h after destroy — D-38) — 24h ingestion lag explainer + $0.01-per-call cost discipline (1 OK, 90-cohort = $0.90) + the full Cost Explorer paste-block with `DESTROY_DATE` template + `/tmp/no-tax-credits.json` heredoc + `aws ce get-cost-and-usage` invocation + jq filter + Source footer + expected `"0"` output explanation + Cost Explorer region-pin note (`us-east-1` regardless of deploy region).
9. Tiếp theo / Next — pointer to Phần 5.

**6 D-42 Source footers per language** anchored to RUNBOOK.md (Phase 4 Cleanup Step 1, Step 2, Step 2 warning, ECR fallback, Verify $0 ongoing cost) + bin/cleanup-verify.sh.

### Task 3: Phần 5 Summary vi+en (commit b08b77a; same atomic commit per D-49)

`content/{vi,en}/5-summary/_index.md` replaced — was an FCJ-template stub (26 lines) with generic "Knowledge 1/2/3" bullets. Now both files are 82-line single-page chapters with 6 H2 sections:

1. Bạn đã làm được gì / What you built — 5-bullet recap covering Apple catalog -> Bedrock KB on S3 Vectors with Titan v2 / Pipecat 1.1.0 + Python 3.12 + multi-arch container + AgentCore Runtime in ap-northeast-1 / web widget on S3+CloudFront + presigner Lambda Function URL bridge for SigV4 WSS auth / CloudWatch hera-prod dashboard + 2 op alarms + 1 billing alarm cross-region / cleanup quy trinh verified via `bin/cleanup-verify.sh` 19 read-only checks.
2. Cost recap (D-54) — D-54 ballpark `~$2-5 USD per 2-hour session` with cleanup, plus `~$5-15 USD/day` no-cleanup penalty. Two main cost drivers (Bedrock Sonic streaming per-active-conversation-minute, AgentCore Runtime per-active-session-second). Per-service breakdown placeholder paragraph (per checker WARNING 2 option a — table dropped, deferred to post-launch update from 04-HUMAN-UAT item #4 instructor pull). 1 D-42 Source footer (D-54 ballpark + 04-HUMAN-UAT item #4 deferred). 3-bullet caveats (Free Tier reset monthly, Cost Explorer 24h lag, AWS pricing drift).
3. Mở rộng (DOC-09) / Expansion (DOC-09) — 1-paragraph intro + 4 H3 sub-sections:
   - Twilio Voice Channel (TWIL-01..03 — v2) — phone number + Media Streams + workshop chapter "Phone channel via Twilio" + bridge layer note (μ-law 8kHz vs Int16 16kHz resample at presigner/dedicated Lambda) + Twilio docs URL.
   - Multi-language chatbot (I18N-01..02 — v2) — auto-detect vi/en + Sonic-vi quality wait-for-AWS-upgrade note + workshop docs already bilingual via DOC-12 parity gate.
   - Multi-agent routing (ADV-01 — v2) — orchestrator routing pattern + awslabs/agentcore-samples reference + ADV-03 conversation history dependency.
   - Conversation history persistent (ADV-03 — v2) — DynamoDB per-user session store + AUTH-01..02 Cognito SSO dependency + TTL auto-expire pattern.
4. Các deferral khác (v2 backlog) / Other deferrals (v2 backlog) — 6-bullet list: AUTH-01..02 + ADV-04 ECS Fargate alt + THEME-01..02 Hugo theme migration + custom domain (Phase 3 D-26 deferred) + ADV-02 KB re-ranking + Bedrock Guardrails (PROJECT.md Out of Scope v1) + tracking pointer to .planning/REQUIREMENTS.md § v2 Requirements.
5. Cảm ơn / Thanks — 3-paragraph attribution: AWS Cloud Clubs Vietnam target audience + AWS blog "Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1" blueprint + sample-nova-sonic-websocket-agentcore reference repo + GitHub Pages PR pointer for community contributions + living-doc disclaimer.
6. Tài liệu tham khảo / References — 7-bullet pointer list to RUNBOOK.md, .planning/PROJECT.md, .planning/REQUIREMENTS.md, .planning/ROADMAP.md, AWS Bedrock pricing, AgentCore Runtime docs, Pipecat 1.1.0 docs.

**1 D-42 Source footer per language** (D-54 ballpark + 04-HUMAN-UAT item #4 deferred — Phase 5 Plan 05-04).

**6 v2 IDs cited verbatim** in both vi and en: TWIL-01, I18N-01, ADV-01, AUTH-01, THEME-01, ADV-04 (and additional mentions of ADV-02, ADV-03, AUTH-02, TWIL-02..03, I18N-02, THEME-02 for completeness across the expansion roadmap and v2 backlog).

## File-count parity (DOC-12)

This plan modifies existing chapter root index bodies and adds 1 .gitkeep under `static/images/4-cleanup/` (not under `content/`). No new content files. Final tree:

```
content/vi/_index.md
content/vi/1-introduction/_index.md
content/vi/2-preparation/_index.md
content/vi/3-hands-on/_index.md
content/vi/3-hands-on/3.1-knowledge-base/_index.md
content/vi/3-hands-on/3.2-pipecat-local/_index.md
content/vi/3-hands-on/3.3-deploy-agentcore/_index.md
content/vi/3-hands-on/3.4-web-widget/_index.md
content/vi/3-hands-on/3.5-observability/_index.md
content/vi/4-cleanup/_index.md           <- modified
content/vi/5-summary/_index.md           <- modified
                                          (vi=11)
content/en/_index.md
content/en/1-introduction/_index.md
content/en/2-preparation/_index.md
content/en/3-hands-on/_index.md
content/en/3-hands-on/3.1-knowledge-base/_index.md
content/en/3-hands-on/3.2-pipecat-local/_index.md
content/en/3-hands-on/3.3-deploy-agentcore/_index.md
content/en/3-hands-on/3.4-web-widget/_index.md
content/en/3-hands-on/3.5-observability/_index.md
content/en/4-cleanup/_index.md           <- modified
content/en/5-summary/_index.md           <- modified
                                          (en=11)
```

`bash bin/check-i18n-parity.sh` exits 0:
```
OK: file count parity (vi=11, en=11)
OK: vi/en slug tree parity
check-i18n-parity: 2/2 parity assertions passed
OK: vi/en _index.md tree parity (DOC-12)
```

## Cost-table values written into Phần 5 (for future PR re-verification)

Per checker WARNING 2 option a, no per-service breakdown table ships in this plan. The single placeholder paragraph anchors to **D-54 ballpark `~$2-5 USD per 2-hour session`** (with cleanup) + **`~$5-15 USD/day`** (no cleanup, AgentCore Runtime idle penalty + CloudFront request volume). The `~$2-5` literal appears once per language in the cost-recap section.

When the instructor lands the actual 24h Cost Explorer pull (04-HUMAN-UAT.md item #4), a follow-up PR can replace the placeholder paragraph with a per-service breakdown table sourced from real account data. The current paragraph explicitly reserves space for that future table ("Per-service breakdown sẽ cập nhật post-launch... Lúc đó bảng chi tiết per-service sẽ thay thế đoạn này — số instructor's actual spend là ground truth thay cho estimate.").

## v2 requirement IDs cited in Phần 5 (full DOC-09 expansion roadmap coverage)

Both vi and en mention literally:

- **TWIL-01..03** (Twilio Voice Channel — phone number + Media Streams + workshop chapter)
- **I18N-01..02** (multi-language chatbot — auto-detect + Sonic-vi voice quality)
- **ADV-01** (multi-agent routing — orchestrator + specialized agents)
- **ADV-02** (KB with RAG re-ranking — extra Bedrock invocation per retrieve trade-off)
- **ADV-03** (conversation history persistent — DynamoDB per-user session store)
- **ADV-04** (ECS Fargate alternative deployment chapter)
- **AUTH-01..02** (Cognito SSO + per-user quota)
- **THEME-01..02** (Hugo theme migration learn -> relearn)

Plus implicit references to D-26 (custom domain + ACM cert deferred), D-30 (AgentCore concurrency cap=2), D-21 (Phase 2 in-memory state), D-12 parity gate, and the PROJECT.md Out of Scope v1 list (Bedrock Guardrails PII redaction).

## Deferred operator action

Capture `cleanup-verify-output.png` (D-44 #6 hero) after running `bash bin/cleanup-verify.sh` against an actually-torn-down account post-workshop close, and commit to `static/images/4-cleanup/cleanup-verify-output.png` along with a follow-up edit to `content/{vi,en}/4-cleanup/_index.md` swapping the `{{% notice info %}}` deferred-callout for an `![cleanup-verify all-green PASS](/images/4-cleanup/cleanup-verify-output.png)` markdown image reference. This carries from 04-HUMAN-UAT.md item #3 (first organic cleanup-verify run against actually-torn-down state).

The same operator-PNG sweep also closes the remaining DOC-11 acceptance gate (along with the deferred PNGs from Plans 05-02 + 05-03 already placeholdered at `static/images/{2-preparation,3.3-deploy-agentcore,3.4-web-widget,3.5-observability}/`).

## Deviations from Plan

None - plan executed exactly as written. The 3 tasks landed in their specified order:

1. Task 1 (Create `.gitkeep`) — straight `mkdir -p` + `touch` per the `<action>` block; verified `test -d` + `test -f` + `[ ! -s ]` all pass.
2. Task 2 (Phần 4 vi+en) — replaced both files in lockstep, ran all `<verify><automated>` gates inline (file existence, frontmatter, callout counts, Source-footer counts, literal greps for `bin/cleanup-verify.sh` / `cdk destroy hera-agentcore` / `terraform destroy` / `aws ce get-cost-and-usage` / `19/19` / `D-24` / `D-38` / `Hero screenshot deferred` / `ap-northeast-1` / `us-east-1`), wc-l >= 90 per side (147 vi, 148 en), 0 emojis, parity exit 0.
3. Task 3 (Phần 5 vi+en) — replaced both files in lockstep, ran all `<verify><automated>` gates inline (frontmatter, v2 ID literals TWIL-01/I18N-01/ADV-01/AUTH-01, stack mentions Twilio/Bedrock Nova 2 Sonic/AgentCore Runtime/S3 Vectors/Pipecat, placeholder paragraph markers `Per-service breakdown` + `post-launch`, `~$2-5` cost literal, Source-footer count >= 1), wc-l >= 80 per side (82 vi, 82 en), 0 emojis, parity exit 0.

No Rule 1/2/3 auto-fixes were needed and no Rule 4 architectural decisions were surfaced. The plan's acceptance criteria mapped 1:1 to executable shell gates, and all gates passed on first author.

## Threat surface scan

The plan introduces zero new IAM, zero AWS deploys, zero new network endpoints. All snippets are quoted from frozen Phase 1-4 source (RUNBOOK.md + bin/cleanup-verify.sh) with D-42 Source footers anchoring each paste-block to its provenance. Cost numbers are aggregate USD ballparks from D-54 — no per-customer billing data, no PII, no payment method exposure. No new threat surface. STRIDE register entries T-05-04-01..03 (Information Disclosure / Repudiation / Tampering) all carry `accept` dispositions per the plan's threat_model section.

## TDD Gate Compliance

Not applicable — plan type is content authoring (markdown), not code. No RED/GREEN/REFACTOR cycle required. Plan frontmatter has `tdd="false"` on every task.

## Self-Check: PASSED

**File existence checks:**
- FOUND: static/images/4-cleanup/.gitkeep (empty, tracked)
- FOUND: content/vi/4-cleanup/_index.md (147 lines)
- FOUND: content/en/4-cleanup/_index.md (148 lines)
- FOUND: content/vi/5-summary/_index.md (82 lines)
- FOUND: content/en/5-summary/_index.md (82 lines)

**Commit existence checks:**
- FOUND: 061958e (chore(05-04): create static/images/4-cleanup/.gitkeep)
- FOUND: 3354893 (docs(05-04): author Phan 4 Cleanup in vi+en (D-49))
- FOUND: b08b77a (docs(05-04): author Phan 5 Summary in vi+en (D-49))

**Gate checks:**
- bin/check-i18n-parity.sh exits 0 (vi=11, en=11; slug-tree parity OK)
- 0 emojis across all 4 modified content files
- themes/hugo-theme-learn submodule untouched (`git diff --submodule themes/hugo-theme-learn` empty)
- Plan acceptance criteria 1:1 verified inline during Tasks 2 + 3
