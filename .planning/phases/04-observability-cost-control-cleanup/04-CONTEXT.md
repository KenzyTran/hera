# Phase 4: Observability, Cost Control, Cleanup - Context

**Gathered:** 2026-05-06
**Status:** Ready for research and planning

<domain>
## Phase Boundary

Phase 4 closes Phase 3's protocol-bridge gap (Wave 1 priority — exposes `POST /invocations` per AgentCore HTTP protocol contract on the live Pipecat container so the browser → CloudFront → presigner → AgentCore → Sonic voice loop works end-to-end), then ships the operability layer that lets a learner or instructor see what the deployed system is doing (CloudWatch dashboard with active session count, latency p50/p95, error rate, Bedrock invocation/cost), get notified before a runaway bill happens (CloudWatch billing alarm at $5/day cap, dashboard-only — no SNS/email/Lambda), bound public-URL abuse with a documented trade-off (rely on AgentCore concurrency cap=2 at the downstream Runtime — no per-IP rate limit on the presigner Function URL), and tear everything down to verified zero ongoing AWS cost (`bin/cleanup-verify.sh` bash + AWS CLI script that runs AFTER operator-driven `cdk destroy → terraform destroy`, asserting no resource leftovers; Cost Explorer $0 confirmation lives in RUNBOOK as a 24h-deferred manual paste-line, not in the script).

In scope: Plan 04-01 (suggested name `04-01-agent-protocol-bridge`) — `agent/hera_agent/main.py` adds `@app.post("/invocations")` route bridging into the existing Pipecat pipeline; `agent/hera_agent/pipeline.py` may grow a per-request adapter helper; RUNBOOK Phase 4 deploy section; verify gate is local docker run + `curl POST /invocations` + 1 cdk deploy in-place to AgentCore Runtime version=3; closing smoke is a single AgentCore data-plane `InvokeAgentRuntime` 200-assertion. Plan 04-N (count TBD by planner) — CloudWatch dashboard module (active sessions, latency p50/p95, error rate, Bedrock invocation/cost), CloudWatch operational alarms (error >5%/5min, latency p95 >5s/5min), CloudWatch billing alarm $5/day with no notification action (dashboard-visible only), `bin/cleanup-verify.sh` bash + AWS CLI script asserting zero leftover resources across KB / S3 Vectors / AgentCore Runtime / CloudWatch log groups / IAM roles / ECR repo / CloudFront / S3 widget bucket / Lambda presigner, RUNBOOK Phase 4 sections (deploy + cleanup + 24h Cost Explorer paste-line + manual-stop fallback for billing-alarm trade-off + browser-test note for SC#2). Out of scope: SNS topics / email subscriptions / Lambda cost circuit-breaker (REQ-OBS-05 satisfied "best-effort" by billing alarm + RUNBOOK manual stop instructions — documented trade-off); AWS WAF or DynamoDB-backed per-IP rate limiting on presigner Function URL (REQ-OBS-04 satisfied by AgentCore concurrency cap=2 downstream — documented trade-off); custom domain / ACM cert (deferred from Phase 3 D-26 to v2); workshop documentation chapters (Phase 5 owns DOC-01..12); Sonic foundation-model ARN runtime gate (carried from Plan 03-01 — proven once /invocations actually init-streams); AgentCore service-quota request from default-10 to D-30's 2 (operational AWS console action, not IaC); CDK bootstrap deploy-role trust policy for non-root operators (operational, not IaC).

</domain>

<decisions>
## Implementation Decisions

(Numbering continues from Phase 3 D-30. Phase 4 starts at D-31.)

### Plan 04-01 — Agent protocol-bridge (Wave 1 priority; closes Phase 3 SC#2)

- **D-31: Pattern = native `POST /invocations` route added to the existing FastAPI app; keep `/ws` for local docker-compose dev.** Smallest practical diff (1-2 source files: `agent/hera_agent/main.py` + maybe `agent/hera_agent/pipeline.py` for a per-request adapter). Zero infra change — CDK stack already has `ProtocolConfiguration: HTTP` from Plan 03-04 which is the contract that selects `/invocations`. Local `docker compose up` continues to work because `/ws` is preserved. Researcher mines `awslabs/agentcore-samples/.../06-bi-directional-streaming/04-pipecat-sonic-ws` for the canonical AgentCore-HTTP request envelope shape and Pipecat-on-AgentCore bidi-streaming response pattern.
- **D-32: Verify gate is local-only PASS, then 1 cdk deploy in-place — no Bedrock streaming smoke before deploy.** Sequence: (1) build new image via existing `bin/push-image.sh` (or `docker build` locally first), (2) `docker run --rm hera-agent:<sha>` + `curl -X POST http://localhost:8080/invocations -d <synthetic-payload>` + assert HTTP 200 + response shape correct, (3) only when local PASS push image to ECR + `cdk deploy hera-agentcore --context image_tag=<sha>` (in-place version=3 update of live runtime `hera_agent-GIsf2P4ImD`). Demo budget — no Bedrock Sonic streaming spend during iteration; the 1 cdk deploy is the single billable AWS write.
- **D-33: Scope is agent/ + RUNBOOK.md only — no CDK stack changes, no Terraform changes, no frontend changes.** `cdk/agentcore/stack.py` ProtocolConfiguration=HTTP from Plan 03-04 already routes to /invocations on the contained service. RUNBOOK.md extends the existing Phase 3 deploy section with the protocol-bridge step (rebuild + push + cdk deploy + smoke probe).
- **D-34: Plan 04-01 self-closes Phase 3 SC#2 via a single AgentCore data-plane `aws bedrock-agentcore InvokeAgentRuntime` (or equivalent latest API name; researcher confirms) smoke against the live runtime returning 200, plus RUNBOOK note pointing to https://dg0w939ktclw6.cloudfront.net/ for optional manual browser test.** ROADMAP marks Phase 3 SC#2 closed when D-34 smoke PASSes. Browser test stays optional (not a gate) so Plan 04-01 doesn't force another Bedrock streaming spend on instructor verification.

### Cost circuit-breaker (OBS-05) — minimal scope, trade-off documented

- **D-35: Ship CloudWatch billing alarm at $5/day cap only — no SNS topic, no email subscription, no Lambda auto-stop hook.** REQ-OBS-05 ("best-effort, document trade-off") is satisfied by: (a) the alarm exists and visibly transitions to ALARM state in the CloudWatch console / Phase 4 dashboard, (b) RUNBOOK documents manual response procedure ("when alarm fires, console → AgentCore → stop runtime, or `aws bedrock-agentcore-control update-agent-runtime ...`"), (c) the trade-off — "no out-of-band notification; instructor monitors dashboard" — is explicitly stated in RUNBOOK and SUMMARY. Threshold $5/day matches Phase 3 D-29 (banner copy hardcoded) so no banner sed-replace needed. Billing alarm metric (`AWS/Billing` namespace `EstimatedCharges`) lives in `us-east-1` per AWS service constraint — researcher confirms current TF resource shape (`aws_cloudwatch_metric_alarm` with `namespace = "AWS/Billing"`).

### Anonymous-public-URL abuse posture (OBS-04 part 2) — minimal scope, trade-off documented

- **D-36: Skip per-IP rate limit on the presigner Lambda Function URL.** Effective rate-limit lives at the AgentCore Runtime concurrency cap=2 downstream (D-30 from Phase 3); the presigner can mint URLs unboundedly but only 2 WSS sessions can be live at once against the runtime. Trade-off documented in RUNBOOK: "presigner is open; rate-limit is enforced by the 2-session cap on AgentCore Runtime — abuse via cached URL replay returns 503 from runtime once cap is hit". No AWS WAF (~$5/month base + per-rule cost — out of demo budget), no DynamoDB token-bucket Lambda (added complexity, free-tier-ish but adds module). Plan 03-04's existing `reserved_concurrent_executions = -1` on presigner Lambda stays as-is (account-floor constraint).

### `bin/cleanup-verify.sh` (SC#4 + SC#5)

- **D-37: Bash + AWS CLI script following the `bin/verify-kb.sh` pattern.** `set -euo pipefail`, `command -v aws` + `command -v jq` preflight gates with platform install hints, paste-style FCJ workshop friendly. One AWS API query per resource type with assertion: KB / S3 Vectors index + bucket / AgentCore Runtime / CloudWatch log group `/aws/bedrock-agentcore/hera-agent` / IAM role `hera-agentcore-exec-prod` + KB consumer policy + KB service role / ECR repo `hera-agent` / CloudFront distribution `E10K3B1L8PQ9EC` + widget S3 bucket `hera-widget-prod` / Lambda `hera-widget-presign-prod` + its Function URL config / billing alarm + dashboard. Exit non-zero if anything is left behind. No Python / boto3 / `uv run` — uniform with existing `bin/*.sh` style.
- **D-38: Cost Explorer $0 verification (SC#5) lives in RUNBOOK as a 24h-deferred manual section, not in the script.** Workshop pattern: after `cleanup-verify.sh` PASSes, RUNBOOK section "Verify $0 ongoing cost (24h after destroy)" provides a paste-line `aws ce get-cost-and-usage --time-period Start=<destroy-date>,End=<+24h-date> --granularity DAILY --metrics BlendedCost --filter file://no-tax-credits.json | jq '.ResultsByTime[].Total.BlendedCost.Amount'` that the operator runs once 24h has passed. Two-step quy trình documented because Cost Explorer has 24h ingestion lag — running it immediately post-destroy returns stale data and creates UX confusion. Skipping Cost Explorer SDK calls in the script also avoids the $0.01/request fee.
- **D-39: Operator destroys before running verify; script is verify-only.** Quy trình paste-style FCJ: (1) operator pastes `cdk destroy hera-agentcore`, (2) operator pastes `terraform destroy -auto-approve` (with both `infra/envs/prod` + maybe widget hosting if separate), (3) operator runs `bin/cleanup-verify.sh` — script never invokes destroy itself. Honors D-24 cleanup-contract (CDK destroy first, TF destroy second) and matches Phase 1 / Phase 3 RUNBOOK paste-style operator pattern.

### Locked decisions carried forward (NOT re-litigated here)

- **From Phase 1 (D-01..D-16):** zero IAM wildcards (D-13 — Phase 4 alarm/dashboard/cleanup-verify all honor); region default `ap-northeast-1` override `us-east-1` (D-14); fixed names no `random_id` (D-12); recovery path = `terraform destroy && terraform apply`; Terraform `~> 6.27` primary.
- **From Phase 2 (D-17..D-23):** Pipecat 1.1.0 + Python 3.12 + `aws-nova-sonic` extra; FastAPI app `agent/hera_agent/main.py` is the entry point Phase 4 extends (`/ping` + `/ws` + new `/invocations`); `lookup_product` tool contract verbatim (D-18); in-memory session state (D-21); multi-arch container same artifact (D-20).
- **From Phase 3 (D-24..D-30):** hybrid IaC = Terraform owns everything except AgentCore Runtime which is CDK Python (D-24); 4-step deploy lifecycle (D-25 amended); cleanup contract `cdk destroy` first then `terraform destroy` (D-24 cleanup-contract); $5/day banner copy + threshold hardcoded (D-29 — Phase 4 alarm threshold matches verbatim, no sed-replace); AgentCore concurrency cap=2 (D-30 — operational service-quota request not IaC); AWSNovaSonicLLMService gets credentials via boto3 default chain bridged into static kwargs at per-connection time (Plan 03-05); Dockerfile bakes `HERA_KB_ID` + `AWS_REGION` only — never bake AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (Plan 03-05).
- **Demo budget rule (project memory 2026-05-06):** prefer skip / defer / minimal-deploy. Avoid extra cdk deploy + Bedrock streaming smoke loops. Each option in this CONTEXT was chosen with that lens.

### Claude's Discretion (planner / researcher / executor decides)

- Exact CloudWatch dashboard panel JSON shape and metric queries (Bedrock invocation count, Sonic latency, AgentCore Runtime active session count) — researcher resolves which metrics are auto-emitted by AgentCore vs require app-level PutMetric instrumentation.
- Exact alarm `evaluation_periods` + `period` + `comparison_operator` + `treat_missing_data` shape for OBS-02 (error rate >5%/5min, latency p95 >5s/5min) — planner picks defaults aligned with AWS-published least-noise patterns.
- Where the billing alarm + dashboard live in Terraform module structure (new `infra/modules/observability/` vs inline in `infra/envs/prod/main.tf`) — planner picks based on REUSE potential for Phase 5 workshop content.
- Exact AgentCore data-plane API name + payload envelope for the SC#2 closure smoke probe (`InvokeAgentRuntime` vs `InvokeAgentRuntimeWithWebSocketStream` vs `InvokeAgent` — Phase 3 Plan 03-04 deviation #4 hint suggests `WebSocketStream` family) — researcher confirms from latest AWS API as of NOW (per AGENTS.md "Use latest APIs as of NOW").
- `/invocations` request envelope JSON schema + response streaming shape (SSE vs chunked vs single-shot) — researcher mines awslabs sample for the canonical pattern; planner locks in PLAN.md.
- How `agent/hera_agent/pipeline.py` adapts a per-request `/invocations` invocation into the existing Pipecat pipeline (per-request fresh pipeline vs persistent reused pipeline) — planner picks based on what awslabs sample shows + Sonic 8-min stream cap implications.
- Phase 4 wave structure (Plan 04-01 protocol-bridge solo Wave 1, then Wave 2 = OBS-01/02/03 dashboard+alarms + cleanup-verify? Or 04-01 Wave 1 + 04-02 OBS solo + 04-03 cleanup-verify solo?) — planner picks based on file-disjoint parallelism opportunities.
- Whether `bin/cleanup-verify.sh` needs separate `--check-cost` flag or not — D-38 says no (RUNBOOK manual paste-line); planner may keep it absent or add a flag for instructor convenience without changing scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level mandates
- `.planning/PROJECT.md` — core value, locked stack, key decisions table, scope rules
- `.planning/REQUIREMENTS.md` — Phase 4 requirement IDs OBS-01..05 (5 total)
- `.planning/ROADMAP.md` — Phase 4 goal + 5 success criteria (lines 103-114) + protocol-bridge Wave-1 priority note (line 18)
- `.planning/STATE.md` — current state including Phase 3 SC#2 protocol-bridge gap (lines 10-13, 142-144)
- `CLAUDE.md` / `AGENTS.md` — no emojis, uv only, root-cause debugging, no defensive try/except, concise docstrings, latest APIs as of NOW

### Cross-phase research (open questions to resolve)
- `.planning/research/SUMMARY.md` — open questions about AgentCore pricing model + concurrency quotas remain relevant for OBS-01..03 dashboard cost-metric panels.
- `.planning/research/STACK.md` / `FEATURES.md` / `ARCHITECTURE.md` / `PITFALLS.md` — original research; AgentCore-pivot annotations live in SUMMARY.md.

### Prior phase decisions (carry-forward)
- `.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md` — D-12 (fixed names), D-13 (zero wildcards), D-14 (region defaults).
- `.planning/phases/01-knowledge-base-foundation/01-VERIFICATION.md` — live KB id `BKXE19AH89`, account 851725411875, region ap-northeast-1.
- `.planning/phases/02-pipecat-voice-agent-local/02-CONTEXT.md` — D-19 transport WSS, D-20 multi-arch container, D-21 in-memory state, D-22 consumer policy ready-to-attach (closed Phase 3).
- `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-CONTEXT.md` — D-24..D-30 (hybrid IaC, deploy lifecycle, widget hosting, banner copy, AgentCore concurrency=2).
- `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-05-SUMMARY.md` — Plan 03-05 credential bridge fix + the protocol-bridge gap discovery + Phase 3 SC#2 status table. **READ THIS FIRST** when planning Plan 04-01.
- `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-04-SUMMARY.md` — Plan 03-04 CDK AgentCore stack + presigner Lambda Rule-4 deviation + 4-step lifecycle + 5 in-tree fixes; the existing live AWS state baseline Phase 4 builds on.
- `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-VERIFICATION.md` — Phase 3 verifier report (4/5 SC PASS, SC#2 deferred).

### Existing assets to extend
- `agent/hera_agent/main.py` — FastAPI app with `/ping` + `/ws`. Plan 04-01 adds `@app.post("/invocations")` here.
- `agent/hera_agent/pipeline.py` — Pipecat pipeline (RawPCMSerializer, lookup_product, SessionContinuationParams, build_llm with boto3 default chain). Plan 04-01 may add a per-request adapter helper.
- `agent/hera_agent/config.py` — lazy-default config (Plan 03-05). Phase 4 reads from this; no edits expected.
- `agent/Dockerfile` — multi-arch + ENV bake-in (Plan 03-05). Phase 4 reuses verbatim; rebuilds image with new SHA.
- `cdk/agentcore/stack.py` — `ProtocolConfiguration: HTTP` already set (Plan 03-04). Plan 04-01 does NOT touch this; deploy is in-place version=3.
- `infra/envs/prod/main.tf` + `infra/envs/prod/outputs.tf` — TF root. Phase 4 OBS work adds new module(s) here (observability + billing alarm).
- `bin/verify-kb.sh` — pattern source for `bin/cleanup-verify.sh`.
- `bin/smoke-deploy.sh` (Plan 03-04) — pattern source for the AgentCore data-plane smoke probe in Plan 04-01 D-34.
- `bin/push-image.sh` (Plan 03-03) — Plan 04-01 reuses verbatim for the rebuild step.
- `RUNBOOK.md` — extend with Phase 4 sections: protocol-bridge deploy, observability dashboard walkthrough, cleanup quy trình paste-style, 24h Cost Explorer manual section, billing-alarm manual-stop fallback note, browser-test optional pointer.

### External references
- Reference repo `awslabs/agentcore-samples` — specifically `06-bi-directional-streaming/04-pipecat-sonic-ws` is the **canonical Pipecat-on-AgentCore bidi-streaming pattern**. Researcher MUST mine this for `/invocations` envelope shape, Pipecat pipeline lifecycle, and response streaming convention.
- AWS docs: Bedrock AgentCore Runtime HTTP service contract — `/ping` shape (already satisfied), `/invocations` shape (Plan 04-01 implements). Researcher confirms latest schema + envelope per AGENTS.md "latest APIs as of NOW".
- AWS docs: AgentCore concurrency model + service quotas + the data-plane invocation API name (`InvokeAgentRuntime` family — exact verb + payload schema researcher confirms from latest AWS docs).
- AWS docs: CloudWatch metric `AWS/Billing` `EstimatedCharges` — only emitted in `us-east-1`; alarm region constraint matters for the TF resource.
- AWS docs: CloudWatch dashboards JSON shape, embedded metric format if used for AgentCore custom metrics.
- AWS Cost Explorer `GetCostAndUsage` API — for RUNBOOK paste-line; 24h ingestion lag documented.
- AWS blog: [Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/) — primary blueprint.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`agent/hera_agent/main.py`** — FastAPI single app, currently `/ping` + `/ws`. Plan 04-01 adds `/invocations` POST handler in the same file; same port 8080; same Lifespan; same CORS posture. No new module needed.
- **`agent/hera_agent/pipeline.py`** — `build_llm()` (Plan 03-05 boto3-bridge) + `build_pipeline()` (Plan 02-01 Pipecat pipeline assembly). Plan 04-01 may add a per-request adapter (e.g., `run_invocation(payload)`) that constructs a one-shot pipeline run, depending on what awslabs sample shows.
- **`bin/verify-kb.sh`** — exact pattern for `bin/cleanup-verify.sh`: `set -euo pipefail`, `command -v` preflight with platform install hints, paste-style ops, exit-code 2 on missing tools, exit-code 1 on assertion failure.
- **`bin/smoke-deploy.sh`** (Plan 03-04) — pattern for SC#2 closure smoke probe in Plan 04-01 D-34: extract `runtime_arn` from cdk outputs, invoke AgentCore data-plane API with synthetic payload, assert HTTP 200.
- **`bin/push-image.sh`** (Plan 03-03) — multi-arch buildx push to ECR with `--provenance=false --sbom=false`. Plan 04-01 reuses verbatim with new git SHA tag.
- **`infra/modules/knowledge_base/`** + **`infra/modules/kb_consumer_policy/`** + **`infra/modules/agentcore_iam/`** + **`infra/modules/widget_hosting/`** + **`infra/modules/widget_presigner/`** + **`infra/modules/ecr/`** — existing module shape (versions/variables/main/outputs four-file). Phase 4 OBS work likely adds `infra/modules/observability/` (dashboard + alarms + billing alarm).
- **`cdk/agentcore/stack.py`** — `ProtocolConfiguration: HTTP` already set Plan 03-04. Plan 04-01 deploys in place — same stack, same name `hera-agentcore`, image_tag context flag bumps to new SHA.
- **`RUNBOOK.md`** — paste-style operational sections per phase. Phase 4 extends with new sections under existing pattern.

### Established Patterns
- **TF root + thin module** (Phase 1 D-08) — `infra/envs/prod/main.tf` thin; modules under `infra/modules/<name>/` four-file. Phase 4 follows.
- **Zero IAM wildcards** (D-13) — every Action and Resource explicit. Phase 4 alarm role (if any), dashboard read role (if any), cleanup-verify operator IAM (uses caller's CLI credentials, no new role) all honor.
- **Atomic conventional commits** scoped to plan id (e.g., `feat(04-01): add /invocations route`).
- **Paste-style RUNBOOK + bin scripts** — Plan 04-01 adds RUNBOOK section + reuses `bin/push-image.sh` + extends `bin/smoke-deploy.sh` semantics; Plan 04-N adds `bin/cleanup-verify.sh`.
- **No defensive try/except** (AGENTS.md root-cause discipline) — Plan 04-01 introduces no new try/except in `/invocations` handler unless awslabs sample mandates a structured error envelope per AgentCore HTTP convention (planner justifies if so).
- **Empty-commit-with-outputs-in-body for live deploy events** (Plan 03-01) — Plan 04-01's cdk deploy event uses this pattern.
- **Lazy-default config + boto3 default chain credential bridge** (Plan 03-05) — Plan 04-01 inherits; no Dockerfile / config.py / pipeline.py credential changes needed.

### Integration Points
- **AgentCore Runtime → /invocations:** AgentCore HTTP protocol (ProtocolConfiguration=HTTP set by CDK Plan 03-04) routes inbound POST to `/invocations` on the container. Plan 04-01 makes `/invocations` exist — closes the 404 gap from Plan 03-05.
- **/invocations → Pipecat pipeline:** new bridge inside `agent/hera_agent/main.py` calls into existing pipeline via either fresh per-request invocation or queued reuse. Researcher resolves shape from awslabs sample.
- **CloudWatch billing alarm → dashboard:** alarm in us-east-1 (AWS/Billing constraint), dashboard in ap-northeast-1 (everything else). Cross-region dashboard reference is supported. Researcher confirms latest TF resource shape.
- **cleanup-verify.sh → AWS APIs:** read-only describe/list calls only — no destroy from script. Operator destroys; script verifies. Honors D-24 cleanup-contract.
- **Phase 3 → Phase 4 hand-off:** AgentCore Runtime ARN, ECR repo, presigner Lambda Function URL, CloudFront distribution, CloudWatch log group `/aws/bedrock-agentcore/hera-agent` — all live and preserved. Plan 04-01 deploys in-place version=3; Plan 04-N OBS work hangs dashboard + alarms off these existing ARNs.
- **Phase 4 → Phase 5 hand-off:** Plan 04-N RUNBOOK Phase 4 sections (deploy + cleanup + 24h Cost Explorer paste-line + manual-stop fallback) become the screenshot/snippet/verification source for Phần 3.5 Observability + Phần 4 Cleanup workshop chapters (DOC-07, DOC-08).

</code_context>

<specifics>
## Specific Ideas

- **Plan 04-01 suggested name:** `04-01-agent-protocol-bridge` (Wave 1 priority — closes Phase 3 SC#2). Planner may rename if a different ordering fits better.
- **AgentCore Runtime ARN target for in-place deploy:** `arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD` (live, version=2 → version=3 after Plan 04-01).
- **Image tag scheme:** `git rev-parse --short HEAD` per Plan 03-03 D-X (no `:latest` per ECR `imageTagMutability=IMMUTABLE`). Plan 04-01 commits source first, then builds.
- **Live KB id:** `BKXE19AH89` (already baked into Dockerfile ENV per Plan 03-05).
- **Live CloudFront URL:** `https://dg0w939ktclw6.cloudfront.net` (browser-test pointer in RUNBOOK note).
- **Billing alarm threshold:** $5/day verbatim (matches Phase 3 D-29 banner copy hardcode).
- **OBS-02 alarm thresholds verbatim from REQ:** error rate >5% over 5 minutes; latency p95 >5s over 5 minutes.
- **cleanup-verify.sh resource list (target = empty / 404 / NotFound):** KB `BKXE19AH89`; S3 Vectors index `hera-kb-index` + bucket `hera-kb-vectors-prod`; AgentCore Runtime `hera_agent-GIsf2P4ImD`; CloudWatch log group `/aws/bedrock-agentcore/hera-agent`; IAM roles `hera-agentcore-exec-prod` + KB service role + KB consumer policy `hera-kb-retrieve-prod`; ECR repo `hera-agent`; CloudFront distribution `E10K3B1L8PQ9EC` + widget S3 bucket `hera-widget-prod`; Lambda `hera-widget-presign-prod` + its Function URL config; billing alarm + dashboard. Source S3 bucket for KB markdown also needs verifying.
- **Cost Explorer RUNBOOK paste-line target:** `aws ce get-cost-and-usage --time-period Start=<destroy-date>,End=<+24h>` filtering to `BlendedCost` for the affected services (Bedrock, S3, S3 Vectors, CloudFront, Lambda, ECR, CloudWatch).

</specifics>

<deferred>
## Deferred Ideas

(Items raised or implied during discussion that belong outside Phase 4 scope.)

- **SNS topic + email subscription for billing alarm** — explicitly skipped per D-35 ("REQ best-effort satisfied by alarm + RUNBOOK manual stop"). User pushed back on adding email config as scope creep. If a future instructor wants out-of-band notifications, they add an SNS subscription manually — not v1 scope.
- **Lambda cost circuit-breaker (auto-stop AgentCore Runtime or auto-disable presigner Function URL)** — explicitly skipped per D-35. REQ-OBS-05 documents "best-effort, document trade-off"; the trade-off here IS the documented manual response. Capture for v2 if instructor finds dashboard-only too lax.
- **AWS WAF rate-based rule** on CloudFront or presigner Function URL — explicitly skipped per D-36 (~$5/month base out of demo budget). Capture for production deployment if Hera v2 ever serves real public traffic.
- **DynamoDB token-bucket per-IP rate limit Lambda** — alternative to D-36 considered; rejected as added complexity for marginal benefit given AgentCore concurrency cap=2 already bounds abuse.
- **Cost Explorer integration baked into cleanup-verify.sh** — explicitly skipped per D-38 (24h ingestion lag + $0.01/request fee + UX confusion); RUNBOOK manual paste-line is the documented quy trình. If a future instructor wants automated 24h check, they cron the paste-line — not script scope.
- **Python/boto3 cleanup-verify.py** — alternative to D-37 considered; rejected to keep uniform with existing `bin/*.sh` style and avoid adding a uv entry-point.
- **Sonic foundation-model ARN runtime gate (carried from Plan 03-01)** — Phase 4 Plan 04-01 will exercise it for the first time when /invocations actually init-streams. If the ARN is wrong, Plan 04-01 surface-level discovers it and the override flow is documented (Plan 03-01 SUMMARY).
- **AgentCore service quota request from default-10 to D-30's 2** — operational AWS console action, not IaC. Phase 4 RUNBOOK may include a paste-line `aws service-quotas request-service-quota-increase --service-code bedrock-agentcore --quota-code <code> --desired-value 2` if researcher confirms the quota code; otherwise it stays as a documented manual step.
- **CDK bootstrap deploy-role trust policy for non-root operators** — operational, not IaC. Capture for v2.
- **Custom domain + ACM cert for CloudFront** — deferred from Phase 3 D-26 to v2.
- **Browser-driven SC#2 acceptance test** — RUNBOOK note pointing to `https://dg0w939ktclw6.cloudfront.net/` is the hand-off; not a Plan 04-01 gate per D-34.
- **Hugo theme migration `learn` → `relearn`** — explicitly v2 per PROJECT.md; not Phase 4 scope.

</deferred>

<success_signals>
## What Success Looks Like (for downstream agents)

When research and planning complete, the executor should be able to produce a Phase 4 deliverable that satisfies all 5 ROADMAP success criteria PLUS the new Wave-1 protocol-bridge plan:

1. **Plan 04-01 (Wave 1) — Phase 3 SC#2 closure.** `agent/hera_agent/main.py` exposes `POST /invocations` per AgentCore HTTP protocol; local docker run + curl POST returns 200; image rebuilt + pushed to ECR; AgentCore Runtime `hera_agent-GIsf2P4ImD` updated in place to version=3; single AgentCore data-plane invoke smoke probe returns 200; ROADMAP marks Phase 3 SC#2 closed; RUNBOOK has browser-test optional note. /ws preserved for local dev unchanged.

2. **OBS-01 dashboard live.** CloudWatch dashboard in ap-northeast-1 displays: active session count (AgentCore Runtime metric or app PutMetric), latency p50/p95 (utterance-to-first-audio-chunk), error rate (5xx / connection failures), Bedrock invocation count + cost. Populated by real traffic from Plan 04-01's deploy + any subsequent demo runs.

3. **OBS-02 + OBS-03 alarms live.** CloudWatch operational alarms: error rate >5% over 5 min, latency p95 >5s over 5 min. CloudWatch billing alarm in us-east-1: `AWS/Billing` `EstimatedCharges` >$5/day. None of these alarms have notification actions (D-35 trade-off documented). All three transition states are visible on the OBS-01 dashboard.

4. **OBS-04 documented + OBS-05 documented.** RUNBOOK explicitly documents: (a) per-IP rate limit not implemented; AgentCore concurrency cap=2 is the effective rate-limit; trade-off accepted (D-36). (b) Cost circuit-breaker not implemented as Lambda; billing alarm + manual response procedure is the trade-off accepted (D-35).

5. **`bin/cleanup-verify.sh` ships.** Bash + AWS CLI per `bin/verify-kb.sh` pattern; `set -euo pipefail`; `command -v` preflight; one read-only API call per resource type from D-37 specifics list; exits non-zero on any leftover; documented quy trình in RUNBOOK: operator `cdk destroy` → operator `terraform destroy` → operator `bin/cleanup-verify.sh`. Cost Explorer $0 verification in RUNBOOK as a 24h-deferred manual paste-line (D-38).

Plus implicit must-haves:
- Zero new IAM wildcards across all new resources (D-13 carry-forward).
- Region defaults `ap-northeast-1`, override `us-east-1` (D-14 carry-forward) — except billing alarm in us-east-1 (AWS/Billing service constraint, documented).
- All new resources use D-12 fixed names (no `random_id` suffix).
- Live AWS state preserved through Plan 04-01 deploy (no teardown until cleanup-verify.sh is the chosen execution path); old image `hera-agent:5f21e36` kept on ECR for rollback alongside the new SHA from Plan 04-01.
- Demo budget honored — no extra cdk deploy beyond the one in Plan 04-01; Plan 04-N OBS work is pure Terraform + dashboard JSON (no Bedrock streaming spend).

</success_signals>

---

*Phase: 04-Observability, Cost Control, Cleanup*
*Context gathered: 2026-05-06*
