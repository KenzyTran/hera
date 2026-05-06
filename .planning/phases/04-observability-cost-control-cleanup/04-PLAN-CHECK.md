# Plan Check - Phase 4

**Checked:** 2026-05-06
**Plans verified:** 04-01, 04-02, 04-03
**SC scope:** Phase 4 SC#1..SC#5 + Phase 3 SC#2 (carry-over via Wave 1)

## Verdict: PASS-WITH-CONCERNS

Plans cover every Phase 4 SC and the carried Phase 3 SC#2; all 9 must-checks resolve favorably. 3 MEDIUMs and 2 LOWs warrant inline planner fixes before execute. Zero HIGH blockers.

## Goal-backward SC coverage matrix

| SC | Owner plan | Owner task | Verdict | Note |
|----|-----------|------------|---------|------|
| Phase 3 SC#2 (carry-over) | 04-01 | T1+T2+T3 | COVERED | T1 adds /invocations, T2 deploys + invoke-agent-runtime smoke, T3 ROADMAP edit. |
| Phase 4 SC#1 (dashboard 5 panels) | 04-02 | T2 | COVERED | 5 widgets verbatim (active sessions, latency p50/p95, error rate, Bedrock invocations+tokens, billing). |
| Phase 4 SC#2 (op alarms + billing alarm) | 04-02 | T2+T3 | COVERED-WITH-DEVIATION | Op alarms via metric_query arithmetic + extended_statistic=p95 (T2); billing alarm us-east-1 (T3). SC#2 wording says billing alarm triggers SNS - D-35 explicitly drops SNS. Tracked as MED-1 below. |
| Phase 4 SC#3 (concurrency + per-IP limit + Lambda CB) | 04-02 | T6 (RUNBOOK only) | COVERED-WITH-DEVIATION | Per-IP rate limit dropped (D-36) and Lambda CB dropped (D-35); RUNBOOK trade-off doc is the closure. SC wording says are configured - see MED-2. |
| Phase 4 SC#4 (terraform destroy clean; cleanup-verify exits 0) | 04-03 | T1+T2+T3 | COVERED | 19 resource checks; D-24 cleanup-contract; final exit 0/1. |
| Phase 4 SC#5 (Cost Explorer 0 USD 24h after destroy) | 04-03 | T3 | COVERED | RUNBOOK 24h-deferred paste-line per D-38 (no script call per per-request fee). |

## REQ coverage matrix

| REQ | Owner plan | Verdict | Note |
|-----|-----------|---------|------|
| OBS-01 (dashboard panels) | 04-02 T2 | COVERED | 5 panels from auto-emitted AWS/Bedrock-AgentCore + AWS/Bedrock metrics; zero PutMetric. |
| OBS-02 (error/latency alarms) | 04-02 T2 | COVERED | Verbatim REQ thresholds (>5%/5min, >5s/5min). |
| OBS-03 (billing alarm 5 USD/day) | 04-02 T3 | COVERED | 5 USD verbatim from D-29; us-east-1 provider alias correct. |
| OBS-04 (per-IP rate limit + concurrency cap) | 04-02 T6 + 04-03 T1 | COVERED-WITH-AMBIGUITY | Plan 04-03 frontmatter lists requirements OBS-04 because the script verifies cleanup; Plan 04-02 carries the per-IP-skip RUNBOOK trade-off. Per CONTEXT D-36, documentation IS the closure. See MED-2 - REQUIREMENTS.md line 51 wording is closer to fully-implemented than CONTEXT D-36 admits. |
| OBS-05 (cost circuit breaker) | 04-02 T6 (RUNBOOK doc) | COVERED-WITH-DEVIATION | D-35 explicit: best-effort = billing alarm + RUNBOOK manual stop. REQUIREMENTS.md line 52 itself says (best-effort, document trade-off) - REQ pre-authorizes the trade-off. |

## Findings

### HIGH (blockers - must fix before execute)

None. The plan set will achieve the stated phase goal as written.

### MEDIUM (should-fix; planner can address inline)

**MED-1: SC#2 wording vs D-35 - billing alarm triggers SNS never satisfied as worded.** ROADMAP.md:109 says billing alarm triggers SNS at the configured daily Bedrock cost cap (default 5 USD/day). CONTEXT D-35 (04-CONTEXT.md:29) explicitly forbids SNS. 04-02 ships alarm_actions=[] (verified in 04-02-PLAN.md:140, 197). The plan honors the locked decision but does NOT satisfy the literal SC text. The verifier will flag this. Fix: ROADMAP.md SC#2 wording for Phase 4 should be revised in 04-01 Task 3 (the same RUNBOOK/ROADMAP commit) to drop triggers SNS and reference the D-35 trade-off, OR a separate docs(04) commit. As written, no plan task touches this line - the contradiction sits unresolved.

**MED-2: SC#3 wording vs D-36 - per-IP rate limits are configured never satisfied as worded.** ROADMAP.md:110 says AgentCore concurrency limits and per-IP rate limits are configured. D-36 explicitly drops per-IP rate limits; D-30 concurrency cap is operational (service-quota request, not IaC). RUNBOOK 04-02 T6 documents the trade-off but no resource is configured. Same fix path: amend ROADMAP SC#3 wording to align with D-36 (trade-off documented in RUNBOOK). Otherwise verifier reports SC#3 not literally met.

**MED-3: 04-03 Task 1 helper-function exit-code edge case.** 04-03-PLAN.md:222-230 helper _check_count_zero captures stdout+stderr together via 2>and1 with a fallback to ERR. When the AWS call fails, count becomes ERR - script reports FAIL count=ERR (correct). When the call succeeds and stderr emits a deprecation banner, the captured stdout becomes the integer plus banner noise and the equality test against the literal 0 fails on whitespace/banner-leak. Fix: pre-strip whitespace before the equality test, or split into a strict variant that uses 2>/dev/null so banners do not leak into the count variable. Low actual blast radius, but a flaky-script outcome on Windows Git Bash would undermine SC#4 PASS/FAIL determinism.

### LOW (nice-to-have; can be deferred to executor judgment)

**LOW-1: 04-03 wave parallelization opportunity.** Plan 04-03 (autonomous=true, files bin/cleanup-verify.sh + RUNBOOK.md) does NOT depend on 04-01 or 04-02 in any functional way (RESEARCH section H confirms cleanup-verify can ship in any wave). 04-03 yaml says depends_on=[01] but the only thing 04-03 reads from 04-01 is RUNBOOK heading awareness - which 04-03 already handles via heading-disjoint convention. 04-03 could ship in Wave 1 alongside 04-01 with no risk. Not a blocker; planner already chose conservative ordering.

**LOW-2: MSYS_NO_PATHCONV may be belt-and-suspenders here.** 04-03-PLAN.md:301 prefixes _check_count_zero calls with env MSYS_NO_PATHCONV=1. Per Plan 03-04 / PITFALL G.8 the trap is real, BUT the FLAG VALUE /aws/bedrock-agentcore/hera-agent is what gets mangled, not the flag itself. The env MSYS_NO_PATHCONV=1 prefix sets the env var only for the wrapper command - fine. Just noting this is belt-and-suspenders rather than wrong.

## Locked-decision audit (D-31..D-39 + carry-forward D-12/13/14/24/29)

| Decision | Plan(s) | Honored? | Evidence |
|----------|---------|----------|----------|
| D-31 native /invocations route, no Pipecat bridge | 04-01 | YES | 04-01-PLAN.md:30 (route shape), :155-160 (verbatim awslabs envelope), no pipeline.py edit. |
| D-32 verify-gate = local-only PASS, then 1 cdk deploy | 04-01 | YES | 04-01-PLAN.md:174-194 (local docker run + curl gate), T2 = 1 push + 1 deploy + 1 smoke. |
| D-33 scope = agent/ + RUNBOOK only | 04-01 | YES | 04-01-PLAN.md files_modified:7-9 (agent/main.py + RUNBOOK + ROADMAP only). |
| D-34 SC#2 closure smoke = invoke-agent-runtime 200 | 04-01 | YES | 04-01-PLAN.md:255-269 (verbatim CLI form per RESEARCH section A). |
| D-35 billing alarm = no SNS/Lambda | 04-02 | YES | 04-02-PLAN.md:140 (alarm_actions=[]), :197 same; T6 RUNBOOK manual-stop fallback. |
| D-36 no per-IP rate limit | 04-02 | YES | T6 RUNBOOK trade-off (04-02-PLAN.md:706-720), no IaC change. |
| D-37 cleanup-verify = bash + AWS CLI per verify-kb pattern | 04-03 | YES | 04-03-PLAN.md:163-260 (set -euo, command -v preflight, REGION default, paste-style); zero python/boto3. |
| D-38 24h Cost Explorer = RUNBOOK paste-line, not script | 04-03 | YES | T3 RUNBOOK section (04-03-PLAN.md:478-509); script has zero aws ce calls (verify gate at :549). |
| D-39 verify-only; operator destroys | 04-03 | YES | Script has zero destroy invocations (gate at 04-03-PLAN.md:549); RUNBOOK 3-step quy trinh (T3:430-470). |
| D-12 fixed names (no random_id) | 04-02 | YES | hera-prod, hera-billing-prod, hera-error-rate-prod, hera-latency-p95-prod (04-02-PLAN.md:227-232 PATTERNS, :754). |
| D-13 zero IAM wildcards | 04-02 | YES | Plan ships ZERO new IAM roles/policies (04-02-PLAN.md:43, :595-596 verify gate). |
| D-14 region default ap-northeast-1, override us-east-1 | 04-02 | YES | var.region for ap-NE-1; aws.us_east_1 alias for billing (04-02-PLAN.md:474-489); documented as service constraint. |
| D-24 cleanup-contract (cdk first, tf second) | 04-03 | YES | T3 RUNBOOK (04-03-PLAN.md:434-446); script hint on FAIL at :381-383. |
| D-29 5 USD/day banner verbatim | 04-02 | YES | billing_threshold_usd default 5 (04-02-PLAN.md:284-287). |
| D-30 concurrency cap=2 (operational, not IaC) | (not in plans) | YES | Correctly out-of-scope; CONTEXT 04:11 + Phase 3 D-30 marks operational. |

## [needs-verification] carry-forward

| Flag | Plan | Carried? | Note |
|------|------|----------|------|
| A1 (billing-alerts toggle) | 04-02 | YES | T5 pre-flight (04-02-PLAN.md:546-551) + T6 RUNBOOK pre-flight (:649-651) + verification block (:763). |
| A2 (operator IAM grant for bedrock-agentcore InvokeAgentRuntime) | 04-01 | YES | user_setup.dashboard_config (04-01-PLAN.md:23) + T2 failure path (:280) + T3 RUNBOOK callout (:376-377) + verification block (:438). |
| A3 (TimeToFirstToken on bidi-streaming Sonic) | 04-02 | YES | Verification block (04-02-PLAN.md:764) - TTFT panel intentionally OMITTED to avoid empty widget; documented decision. |
| A4 (S3 Vectors error name) | 04-03 | YES | GONE_REGEX includes NotFound without Exception (04-03-PLAN.md:199); verification :565. |
| A5 (KB service role exact name) | 04-03 | YES | T2 inline [needs-verification] comment (04-03-PLAN.md:321) + verification block (:566). |

All 5 RESEARCH [needs-verification] flags are carried into the relevant plan body so executor surfaces them in SUMMARY.

## Anti-pattern scan

| Pattern | Found? | Where | Mitigation |
|---------|--------|-------|------------|
| New try/except around AWS calls | NO | 04-01 T1 explicitly forbids it (PLAN:166-169); no other Python edits in phase. | OK. |
| IAM Action wildcard or Resource wildcard | NO | 04-02 ships ZERO new IAM (PLAN:43); existing wildcards from prior phases unchanged. | OK. |
| random_id resource | NO | All Phase 4 names are name_prefix + env literals. | OK. |
| pip install / python3 X | NO | 04-01 uses uv run pytest / uv run cdk; 04-03 is bash-only. | OK. |
| Emojis in plan body or proposed file content | NO | Spot-checked all 3 plan files + RUNBOOK content blocks. | OK. |
| :latest ECR tag | NO | 04-01 uses git rev-parse --short HEAD (PLAN:222). | OK. |
| Positive reserved_concurrent_executions | NO | 04-02 touches no Lambda; 04-01 touches no Lambda. | OK. |
| null_resource around AWS CLI | NO | PATTERNS anti-pattern explicitly cited (04-02 :395, :760). | OK. |
| sed -i (BSD/GNU split) | NO | 04-03 verify-only; no in-place edits (PLAN:559). | OK. |
| aws ce inside cleanup-verify script | NO | 04-03 verify gate explicitly checks (PLAN:549). | OK. |
| SNS/email/Lambda hook on billing alarm | NO | alarm_actions=[] mandated D-35; verified (04-02 :140, :197). | OK. |
| Inconsistent Sonic model id | RESOLVED | RESEARCH says v2:0 (typo at lines 149, 192, 282); plans uniformly use v1:0 matching live code in infra/modules/agentcore_iam/variables.tf:31. Plans WIN - codebase reality is amazon.nova-sonic-v1:0. | RESEARCH typo only; plans are correct. |

## Recommended action

PASS-WITH-CONCERNS. Inline-fix instructions for the planner before execute:

1. MED-1 (SC#2 SNS wording): add a 1-line ROADMAP.md edit to 04-01 Task 3 action: append after the existing SC#2 closure note, Phase 4 SC#2 reworded - billing alarm has alarm_actions=[] per D-35; manual-stop fallback documented in RUNBOOK Phase 4 (OBS-05 trade-off accepted). Same commit docs(04-01) RUNBOOK Phase 4 protocol-bridge section + ROADMAP SC#2 closure.
2. MED-2 (SC#3 per-IP wording): same fix vehicle - append a note to ROADMAP.md Phase 4 SC#3 acknowledging D-36 trade-off (per-IP rate limit deferred to v2; AgentCore concurrency cap=2 is the documented gate).
3. MED-3 (count-zero whitespace strip): in 04-03 Task 1 helper definition, sanitize the count variable before the equality test (strip whitespace and any banner noise) - 1-line change, eliminates Windows-Git-Bash flakiness.

Once those three inline edits land, the plan set is execute-ready.
