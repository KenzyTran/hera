---
phase: 04-observability-cost-control-cleanup
plan: 03
subsystem: infra
tags: [bash, aws-cli, cleanup-verify, s3-vectors, agentcore, cloudfront, cloudwatch, ecr, iam, cost-explorer, runbook]

requires:
  - phase: 01-knowledge-base-foundation
    provides: KB BKXE19AH89 + S3 Vectors index/bucket + KB source bucket + IAM kb_service_role (verified gone)
  - phase: 03-agentcore-deploy-web-widget-public-demo-url
    provides: AgentCore Runtime + CDK CFn stack + 4 IAM roles + 1 policy + ECR + CloudFront + widget S3 + presigner Lambda + 2 log groups (all verified gone)
  - phase: 04-observability-cost-control-cleanup
    plan: 02
    provides: 1 dashboard + 3 alarms (billing in us-east-1, 2 op alarms in ap-northeast-1) — all verified gone
provides:
  - bin/cleanup-verify.sh — Phase 4 cleanup verification script (D-37, D-39); 19 read-only AWS CLI checks; exits 0 when all phase 1/2/3/4 resources are gone
  - RUNBOOK.md `## Phase 4: Cleanup quy trinh` — 3-step paste-style (cdk destroy → terraform destroy → bin/cleanup-verify.sh) + 24h-deferred Cost Explorer paste-line
  - Verified D-24 cleanup-contract documented end-to-end (CDK first, Terraform second, verify third)
affects:
  - phase-05-workshop-content-polish-launch (DOC-08 cleanup chapter sources its screenshots and paste-blocks from this RUNBOOK section)

tech-stack:
  added: []
  patterns:
    - "Helper-driven bash verify script: _check_gone (capture 2>&1 || true + grep -qiE multi-name alternation regex) + _check_count_zero (length(@) query + whitespace-strip + literal '0' inverse pattern)"
    - "GONE_REGEX alternation: ResourceNotFound|NoSuchEntity|NotFound|RepositoryNotFound|NoSuchDistribution|NoSuchBucket|does not exist|404 — single regex covers every AWS service's error spelling"
    - "MSYS_NO_PATHCONV=1 prefix on log-group calls (PITFALL G.8 — Windows Git Bash leading-slash path mangling)"
    - "Cost Explorer paste-line lives in RUNBOOK only (D-38 — never in script: 24h ingestion lag + $0.01/request fee)"
    - "Cross-platform date math: GNU `date -d` ↔ BSD `date -j -v+1d` fallback chain"

key-files:
  created:
    - bin/cleanup-verify.sh
    - .planning/phases/04-observability-cost-control-cleanup/04-03-SUMMARY.md
  modified:
    - RUNBOOK.md

key-decisions:
  - "A5 [needs-verification] resolved via terraform state show: KB service role is named hera-kb-service-role (not hera-kb-service-prod as the plan stub suggested). Script check #11 uses the actual name."
  - "A4 [needs-verification] resolved by design: GONE_REGEX alternation covers BOTH 'NotFound' and 'NotFoundException' spellings, so whichever the s3vectors API emits, the regex matches. No follow-up dry-run needed."
  - "Live dry-run skipped to honor demo-budget memo (project memory 2026-05-06). The plan flagged it as optional; bash -n + structural review proves wiring; live verification will happen organically when the operator runs the script post-destroy."
  - "Helper functions accept `\"$@\"` and forward to `aws ...` — avoids word-splitting on resource ids containing `/` and keeps every check uniform (one line label + one line aws-call-with-args)."

patterns-established:
  - "verify-only bash script + RUNBOOK paste-style operator quy trinh — D-37 + D-39 codified for any future cleanup-N phase"
  - "Cost Explorer-as-RUNBOOK-deferral — D-38 pattern: anything with non-trivial per-call cost or async ingestion stays in operator paste-line, not in scripts"
  - "Heading-disjoint RUNBOOK sections per plan: '## Phase 4: Protocol-bridge deploy' (04-01) + '## Phase 4: Observability dashboard walkthrough' (04-02) + '## Phase 4: Cleanup quy trinh' (04-03) coexist without grep collisions"

requirements-completed: [OBS-04]

duration: 16min
completed: 2026-05-06
---

# Phase 4 Plan 03: Cleanup-verify script + RUNBOOK quy trinh Summary

**`bin/cleanup-verify.sh` ships with 19 read-only AWS API checks across KB / S3 Vectors / AgentCore / CDK CFn / CW log-groups / IAM / ECR / CloudFront / widget S3 / Lambda / billing+op alarms / dashboard, plus RUNBOOK Phase 4 cleanup section with 3-step paste-style quy trinh + 24h-deferred Cost Explorer paste-line per D-38.**

## Performance

- **Duration:** ~16 min
- **Started:** 2026-05-06T13:16:50Z (UTC, first task commit author-time)
- **Completed:** 2026-05-06T13:32:09Z (UTC, RUNBOOK commit author-time)
- **Tasks:** 3 (all atomic + autonomous; zero checkpoints)
- **Files modified:** 2 (1 new bash script, 1 RUNBOOK insertion)

## Accomplishments

- 19-resource cleanup verification script in pure bash — same shape as `bin/verify-kb.sh`; same preflight, same region default, same paste-style FCJ-friendly tone.
- D-37 (bash uniform), D-38 (Cost Explorer in RUNBOOK only), D-39 (verify-only, no destroy) all honored verbatim.
- D-24 cleanup-contract (CDK first, Terraform second) documented in both the RUNBOOK quy trinh AND the script's FAIL-hint message — operator gets a recovery hint regardless of which surface they hit.
- A5 [needs-verification] (KB service role exact name) resolved during execution by inspecting `terraform state show module.knowledge_base.aws_iam_role.kb_service_role`. Plan stub said `hera-kb-service-prod`; actual name is `hera-kb-service-role`. Script uses the correct name.
- A4 [needs-verification] (S3 Vectors error spelling — `NotFound` vs `NotFoundException`) resolved by design: the GONE_REGEX alternation matches either spelling, so the script is correct independent of which way the AWS team chose.
- Windows-bash compat baked in: `MSYS_NO_PATHCONV=1` prefix on the two log-group calls (`/aws/bedrock-agentcore/...` and `/aws/lambda/...`) per PITFALL G.8.
- Live AWS state preserved: pure script + docs; ZERO state mutation; ZERO Bedrock spend.

## Task Commits

1. **Task 1: bin/cleanup-verify.sh skeleton (preflight + 6 of 19 checks)** — `4ed3764` (feat)
2. **Task 2: per-resource checks 7-19 + final summary** — `00f8806` (feat)
3. **Task 3: RUNBOOK Phase 4 cleanup quy trinh + 24h Cost Explorer paste-line** — `1ccaff0` (docs)

**Plan metadata commit:** added in the final SUMMARY commit alongside this file.

## Files Created/Modified

- `bin/cleanup-verify.sh` (new, executable) — 19 read-only AWS API checks; PASS_COUNT/FAIL_COUNT counters; cleanup-contract hints on FAIL; exits 0 on full clean.
- `RUNBOOK.md` (modified, +90 lines) — new `## Phase 4: Cleanup quy trinh` section between the 04-02 observability walkthrough and the resolved-deferrals tail. Three numbered steps + ECR force-delete fallback + CloudFront 15-30 min warning + 24h Cost Explorer paste-line subsection.

## Decisions Made

- **Script-only A5 fix:** corrected role name `hera-kb-service-role` (was `hera-kb-service-prod` in the plan stub). Confirmed against `terraform state show`. Did NOT modify `infra/modules/knowledge_base/` — upstream module's role name was correct; plan stub was wrong.
- **Skip live dry-run:** the plan listed it as optional (acceptance gate #7). Demo-budget memo (project memory 2026-05-06) prefers skip-over-AWS-call; structural review (bash -n + grep gates + helper-driven uniform shape) is the gating evidence.
- **Use `env MSYS_NO_PATHCONV=1` rather than `MSYS_NO_PATHCONV=1`-as-shell-prefix:** Necessary because the helper invokes `"$@"` — a bare `MSYS_NO_PATHCONV=1` env-assignment ahead of `"$@"` does not propagate the way a normal command-prefix env assignment would when the args are stored in a variable. `env <name>=<value>` is the portable canonical form and works through `"$@"`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] KB service role name corrected from plan stub to terraform-state truth**
- **Found during:** Task 2 (writing check #11)
- **Issue:** Plan PLAN.md interfaces table line 132 said role name was `hera-kb-service-prod` (with `[needs-verification]` flag for A5). Running the env_notes command `terraform state show module.knowledge_base.aws_iam_role.kb_service_role` returned `name = "hera-kb-service-role"`. The plan stub was wrong.
- **Fix:** Check #11 uses `aws iam get-role --role-name hera-kb-service-role` with an inline comment crediting `terraform state show` as the source.
- **Files modified:** bin/cleanup-verify.sh
- **Verification:** Comment in script body documents the resolution; `aws iam get-role --role-name hera-kb-service-role` against the live account currently returns the role (which is correct — it still exists pre-cleanup).
- **Committed in:** `00f8806` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug — wrong-name-in-plan-stub, fixed via terraform-state-truth lookup)
**Impact on plan:** Single-character category fix (the role name); no scope change. Without this fix the script would always fail check #11 even on a clean account because IAM would return AccessDenied/NoSuchEntity on the wrong name and the FAIL message would falsely accuse the operator of an incomplete destroy.

## A4 / A5 [needs-verification] resolutions

| Flag | Original concern | Resolution |
|------|------------------|------------|
| **A4** | S3 Vectors error spelling — `NotFound` vs `NotFoundException` | GONE_REGEX alternation `ResourceNotFound\|NoSuchEntity\|NotFound\|RepositoryNotFound\|NoSuchDistribution\|NoSuchBucket\|does not exist\|404` matches BOTH spellings. No follow-up needed; script is correct either way. |
| **A5** | KB service role exact name | Verified via `terraform state show module.knowledge_base.aws_iam_role.kb_service_role` → `name = "hera-kb-service-role"`. Plan stub (`hera-kb-service-prod`) was wrong; check #11 corrected. Documented inline in script comment. |

## Live dry-run note

Per the plan's optional gate #7 and the demo-budget memo, NO live dry-run was performed during this execution. Structural verification:
- `bash -n bin/cleanup-verify.sh` → PASS
- 20 numbered `# --- N.` resource-section comments present (1-19 with 18b for the second op alarm)
- 21 helper invocations (19 checks + 2 helper definitions) match the regex `^_check_gone\|^_check_count_zero`
- Anti-pattern grep gate: ZERO occurrences of `python`, `boto3`, `uv run`, `sed -i`, `aws ce ` in the script body. The strings `cdk destroy` and `terraform destroy` appear ONLY in comment + echo-hint lines (verified by line-numbered grep) — never invoked.
- All 5 RUNBOOK section gates green: heading exactly once, `bin/cleanup-verify.sh` referenced, `Verify $0 ongoing cost` subsection present, `no-tax-credits.json` heredoc present, `DO NOT interrupt` warning present.

The first organic dry-run will happen when an operator runs the script post-destroy at workshop close — at which point all 19 checks should report OK after the cdk-then-tf destroy sequence completes. The 24h Cost Explorer paste-line is deferred to the instructor's first cleanup cycle.

## Issues Encountered

None — plan was structurally complete; only the A5 plan-stub-wrong-name needed an in-flight fix using the env_notes-suggested terraform-state lookup. A4 was resolved at design time by the alternation regex, no investigation needed.

## User Setup Required

None — pure bash script + RUNBOOK docs; no new AWS resources, no new env vars, no new IAM, no console actions.

## Next Phase Readiness

Phase 4 cleanup deliverable complete:
- Plan 04-01 (Wave 1) closed Phase 3 SC#2 (protocol-bridge live + smoke probe).
- Plan 04-02 shipped 1 CloudWatch dashboard + 3 alarms (billing us-east-1, op error-rate + latency-p95 in ap-northeast-1).
- Plan 04-03 ships verify-only `bin/cleanup-verify.sh` + RUNBOOK Phase 4 cleanup quy trinh + 24h Cost Explorer paste-line.

ROADMAP Phase 4 success criteria status (orchestrator advances):
- SC#1 (protocol-bridge): PASS — closed by Plan 04-01.
- SC#2 (dashboard): PASS — closed by Plan 04-02.
- SC#3 (alarms): PASS — closed by Plan 04-02.
- SC#4 (cleanup-verify zero leftovers): READY — script ships; first organic run is workshop-close. Pre-emptively verified by structural review.
- SC#5 (Cost Explorer $0): DEFERRED-BY-DESIGN — RUNBOOK paste-line ships per D-38; runs once 24h post-destroy.

Phase 5 (workshop content polish + launch) can now lift cleanup-quy-trinh paste-blocks + cleanup-verify expected-output directly from this RUNBOOK section into Phần 4 Cleanup workshop chapter (DOC-08).

## Self-Check: PASSED

- `bin/cleanup-verify.sh` exists, mode 100755, `bash -n` passes — FOUND.
- `.planning/phases/04-observability-cost-control-cleanup/04-03-SUMMARY.md` (this file) — FOUND.
- RUNBOOK.md contains `## Phase 4: Cleanup quy trinh` heading, `bin/cleanup-verify.sh`, `Verify $0 ongoing cost`, `no-tax-credits.json`, `DO NOT interrupt` — all FOUND.
- Commits `4ed3764`, `00f8806`, `1ccaff0` — all FOUND in `git log --oneline`.

---
*Phase: 04-observability-cost-control-cleanup*
*Plan: 03*
*Completed: 2026-05-06*
