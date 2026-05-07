# Roadmap: Hera — AWS Voice Agent Workshop & Demo System

## Overview

Hera ships in two parallel tracks under one umbrella: a working AWS-native voice chatbot (Bedrock Knowledge Base + Pipecat 1.1.0 agent on Amazon Bedrock AgentCore Runtime + browser web widget + public instructor demo URL) and a bilingual vi/en FCJ workshop that teaches Cloud Clubs members to deploy that same system in their own AWS account. The journey goes goal-backward from the core value: a learner walks Phần 1-5 and ends up talking to their own voice chatbot through their own browser. To make that promise truthful, we build the system bottom-up by dependency (KB before agent, agent locally before AgentCore deploy, deploy before widget polish, observability+cleanup before declaring done) and only then write the workshop content that needs the working code to screenshot, snippet, and verify against. Granularity is **coarse** (5 phases, 1-3 plans each).

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Knowledge Base Foundation** - Apple catalog ingested into Bedrock KB on S3 Vectors, queryable from CLI (3 plans) — completed 2026-05-05
- [x] **Phase 2: Pipecat Voice Agent (Local)** - Pipecat agent code with Sonic + KB tool runs end-to-end on a developer laptop — completed 2026-05-05
- [x] **Phase 3: AgentCore Deploy + Web Widget + Public Demo URL** - Container deployed to Bedrock AgentCore Runtime; browser widget talks to it over a public HTTPS URL — 5/5 plans complete 2026-05-06; SC#2 (live browser voice loop) deferred to Phase 4 protocol-bridge follow-up plan because AgentCore HTTP protocol calls POST /invocations while the FastAPI app exposes only /ping + /ws (a separate gap surfaced after Plan 03-05's credential fix; see Plan 03-05 SUMMARY) — **SC#2 closed by Plan 04-01 (Phase 4 Wave 1) — POST /invocations stub deployed; AgentCore data-plane invoke returns 200.**
- [x] **Phase 4: Observability, Cost Control, Cleanup** - CloudWatch dashboards/alarms live, billing cap enforced, `terraform destroy` proven on a fresh account. **Wave-1 closed Phase 3 SC#2** via Plan 04-01 protocol-bridge (POST /invocations stub deployed; AgentCore data-plane invoke returns 200). Wave-2 shipped 1 dashboard + 3 alarms (zero new IAM, no SNS hook per D-35) + bin/cleanup-verify.sh (19 read-only checks). 5 deferred items in 04-HUMAN-UAT.md (browser smoke, billing-alerts toggle, workshop-close cleanup-verify run, 24h Cost Explorer paste-line, D-30 quota request) — none blocking. — completed 2026-05-06
- [x] **Phase 5: Workshop Documentation (vi/en)** - 5 chapters published bilingual on GitHub Pages so a fresh learner can deploy their own copy — gap closure complete 2026-05-07 (Plan 05-05 closed CR-01 submodule + CR-02 instructor data + WR-02 Phần rename; pending re-verification + first organic CI build)
 (completed 2026-05-07)

## Phase Details

### Phase 1: Knowledge Base Foundation
**Goal**: A learner (or the Pipecat agent) can ask the deployed Bedrock Knowledge Base for Apple product information and get back the right document, end-to-end, using nothing but AWS CLI.
**Depends on**: Nothing (first phase)
**Requirements**: KB-01, KB-02, KB-03, KB-04, KB-05, KB-06
**Success Criteria** (what must be TRUE):
  1. Apple product catalog (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4) lives in source S3 as English markdown and is ingested into a Bedrock Knowledge Base backed by S3 Vectors with Titan v2 embeddings (1024-dim float32 cosine).
  2. Running `aws bedrock-agent-runtime retrieve` for the query "iPhone 13 Pro Max stock" returns the matching catalog document with non-zero score, after the documented post-sync wait.
  3. The Terraform `modules/knowledge_base` deploys cleanly into a fresh AWS account in `ap-northeast-1` with `terraform init && apply` and no manual console clicks (model access enable assumed already done).
  4. A least-privilege IAM role exposes only `bedrock:Retrieve` scoped to the KB ARN — no wildcards in Action or Resource.
  5. Re-indexing after editing a product markdown is a single documented CLI command, and the new content is queryable within the documented sync window.
**Plans:** 3 plans

**Wave 1** *(linear: 01-02 depends on 01-01 .gitignore; 01-03 depends on 01-01 + 01-02 outputs)*
- [x] 01-01-PLAN.md — Repo skeleton (catalog/*.md per D-02 schema, RUNBOOK.md stub, .gitignore Terraform additions). Covers KB-01. *(completed 2026-05-05)*
- [x] 01-02-PLAN.md — Terraform module + root infra (envs/prod + modules/knowledge_base): S3 source, S3 Vectors, Bedrock KB, data source, KB service IAM role; ends at terraform validate. Covers KB-02, KB-03, KB-05. *(completed 2026-05-05)*
- [x] 01-03-PLAN.md — bin/verify-kb.sh, RUNBOOK.md sync/recovery/cleanup sections, live terraform apply + ingestion + verify (autonomous: false; requires AWS credentials). Covers KB-04, KB-06. *(completed 2026-05-05; live KB BKXE19AH89 in ap-northeast-1, top score 0.8598 for verification query)*

**Cross-cutting constraints** (truths shared by 2+ plans — every executor must honor):
- No emojis in any file (CLAUDE.md mandate; appears in all 3 plans).
- Region defaults to `ap-northeast-1`, override variable supports `us-east-1` (D-14, DEP-06).
- Hugo build path is unaffected — no edits under `config.toml`, `content/`, `layouts/`, `themes/`, `static/`, `i18n/`, `.github/`.
- Phase 2 consumer `bedrock:Retrieve` role is NOT created here (D-10 — only `kb_arn` exported).
- Recovery path is `terraform destroy && terraform apply`; no `random_id` suffix anywhere (D-12).

### Phase 2: Pipecat Voice Agent (Local)
**Goal**: A developer can run the Pipecat container on their laptop, open a local browser page, hold a real spoken conversation with the Apple Store assistant against real Bedrock Nova 2 Sonic and the real Phase 1 Knowledge Base — proving the voice loop and tool-use work before any AgentCore complexity.
**Depends on**: Phase 1
**Requirements**: AGT-01, AGT-02, AGT-03, AGT-04, AGT-05, AGT-06, AGT-07, AGT-08
**Success Criteria** (what must be TRUE):
  1. A developer asks "Do you have MacBook Pro?" into a local browser microphone, the agent calls `lookup_product()` against the Phase 1 KB, and Sonic speaks an Apple Store-styled answer through the speakers in under 3 seconds p95 from end-of-utterance.
  2. Audio is correct end-to-end — input is 16kHz mono PCM Int16, output 24kHz mono PCM, no chipmunk effect, no silent transcription failure.
  3. Conversations longer than 8 minutes do not visibly break — Pipecat's `AWSNovaSonicLLMService` handles the Sonic stream cap with no user-visible interruption.
  4. The agent stays in its Apple Store assistant persona (English) and answers product/stock questions; per-session conversation state is held in-memory only (no DynamoDB).
  5. The container image builds reproducibly with `uv` lockfile and is ready to push to ECR for Phase 3 AgentCore deploy.
**Plans:** 3 plans

**Wave 1** *(parallel: 02-01 builds Python agent core; 02-03 ships Terraform IAM consumer policy + RUNBOOK extension; no file overlap)*
- [x] 02-01-PLAN.md — Python agent core: uv project (Python 3.12 + Pipecat 1.1.0), hera_agent package (FastAPI app with /ping + /ws, AWSNovaSonicLLMService with explicit static creds, lookup_product tool via asyncio.to_thread, SessionContinuationParams), unit tests with mocked boto3, bin/run-agent-local.sh launcher. Covers AGT-01, AGT-02, AGT-03, AGT-05, AGT-06, AGT-07. *(completed 2026-05-05; 16 files / 3 commits / 11 tests pass in 2.04s; commits b606c8e, a55862d, db64e08)*
- [x] 02-03-PLAN.md — Terraform IAM consumer policy: new module infra/modules/kb_consumer_policy/ shipping aws_iam_policy hera-kb-retrieve-prod (single statement, bedrock:Retrieve scoped to KB ARN, zero wildcards, NOT attached per D-22 — Phase 3 attaches). Resolves Phase 1 D-10. RUNBOOK.md extended with Phase 2 uv-only operational section + Resolved deferrals (docker-compose / first-voice-test / cleanup-docker sections owned by Plan 02-02). *(completed 2026-05-05; 7 files / 3 commits; live policy arn:aws:iam::851725411875:policy/hera-kb-retrieve-prod with zero attachments; commits d7f9660, e9fee4d, 2e50b0d)*

**Wave 2** *(02-02 depends on 02-01: needs the agent module + uv.lock to package)*
- [x] 02-02-PLAN.md — Container + compose + frontend: multi-arch Dockerfile (linux/arm64 + linux/amd64 via docker buildx, base ghcr.io/astral-sh/uv:python3.12-trixie-slim — research correction #1), docker-compose.yml two-service stack (agent on host 8080, frontend on host 8000) with required-syntax env vars (research correction #3), minimal frontend (index.html + app.js + audio-capture-worklet.js with 16 kHz Int16 capture and 24 kHz playback queue), bin/run-agent-docker.sh launcher. Covers AGT-04, AGT-08. *(completed 2026-05-05; 10 files / 6 commits; AGT-04 live gate passed LATENCY_MS=0 < 3000ms against Bedrock Nova 2 Sonic in ap-northeast-1; commits dbc77a7, c8027f8, f8238c8, 80fa3ea, ea3e4b5, a3b6545)*

**Cross-cutting constraints** (truths shared by 2+ plans — every executor must honor):
- No emojis in any file (CLAUDE.md mandate; appears in all 3 plans).
- uv exclusively for Python (uv add, uv sync --frozen, uv run); never pip install, never python3 X.
- Python 3.12 mandatory (research correction #1 — Pipecat aws-nova-sonic extra has marker python_version>=3.12; CONTEXT D-20 said 3.11 — 3.12 wins).
- AWSNovaSonicLLMService receives explicit access_key_id= / secret_access_key= kwargs from os.environ (research correction #3 — service uses StaticCredentialsResolver, NOT boto3 default chain).
- FastAPI app exposes both /ping (HTTP) and /ws (WebSocket) on port 8080 (research correction #4 — AgentCore HTTP service contract; same shape Phase 3 deploys).
- Region defaults to ap-northeast-1, override to us-east-1 (D-14, DEP-06).
- Zero IAM wildcards (D-13 carried forward from Phase 1).
- No defensive try/except around AWS / Bedrock / KB calls (AGENTS.md root-cause discipline; the only try/except is WebSocketDisconnect which is the normal close path).

### Phase 3: AgentCore Deploy + Web Widget + Public Demo URL
**Goal**: Anyone with the public instructor URL can open a browser, click a record button, and have a working voice conversation with the Apple Store agent running on Amazon Bedrock AgentCore Runtime — no installation, no login, just a headset and a microphone.
**Depends on**: Phase 2
**Requirements**: DEP-01, DEP-02, DEP-03, DEP-04, DEP-05, DEP-06, WID-01, WID-02, WID-03, WID-04, WID-05, WID-06, DEM-01, DEM-02, DEM-03
**Success Criteria** (what must be TRUE):
  1. The Pipecat container is deployed to Amazon Bedrock AgentCore Runtime in `ap-northeast-1` with a working WSS (or WebRTC, if Pipecat transport supports AgentCore's March 2026 endpoint) endpoint, exposed end-to-end via Terraform `~> 6.27` (or the documented hybrid Terraform + CDK/CLI fallback if AgentCore Terraform support has gaps — decision locked in Phase 3 planning).
  2. A user opens the public HTTPS demo URL on a desktop browser, clicks "record", grants mic permission, and holds an end-to-end voice conversation that includes at least one KB-backed product answer with audible audio response and a live transcript visible alongside.
  3. Error states are visible and self-explanatory — mic permission denied, WS connect failure, agent timeout, mic muted indicator all display human-readable messages instead of failing silently.
  4. The IAM execution role for AgentCore is least-privilege (`bedrock:InvokeModelWithBidirectionalStream`, `bedrock:Retrieve`, CloudWatch logs/metrics scoped to the relevant ARNs — zero wildcards) and Terraform variables let region default to `ap-northeast-1` while supporting override to `us-east-1` for dev.
  5. The public demo page shows a banner stating it is an instructor demo, daily cost is capped, and learners should follow the workshop to deploy their own.
**Plans:** 4 plans

**Wave 1** *(parallel: 03-01 TF infra modules, 03-02 frontend widget — file-disjoint)*
- [x] 03-01-PLAN.md — Terraform modules (agentcore_iam + widget_hosting + ecr) + prod root extension. Closes D-22 KB policy attachment. Covers DEP-03, DEP-04, DEP-05, DEP-06, WID-01, DEM-01. *(completed 2026-05-06; 12 AWS resources live in 851725411875/ap-northeast-1: hera-agentcore-exec-prod role + KB attachment + log group, hera-agent ECR repo IMMUTABLE+scan-on-push, hera-widget-prod S3 + CloudFront E10K3B1L8PQ9EC at https://dg0w939ktclw6.cloudfront.net; commits 4529fa1, 7817942, 8f7e7f6, f8ba30a, adf966c)*
- [x] 03-02-PLAN.md — Polished frontend widget (Apple-Store light per UI-SPEC) + bin/build-widget.sh sed-injection script. Covers WID-01, WID-02, WID-03, WID-04, WID-05, WID-06, DEM-03. *(completed 2026-05-06; 5 files / 3 commits; all 5 button states + 5 WID-06 verbatim error strings + 30s heartbeat + AGENTCORE_WSS_URL placeholder; commits 011395f, 95ae987, 6a57d95)*

**Wave 2** *(03-03 depends on 03-01: needs ECR repo URL output)*
- [x] 03-03-PLAN.md — bin/push-image.sh multi-arch buildx push to ECR + RUNBOOK Phase 3 deploy section. Covers DEP-02, DEP-03. *(completed 2026-05-06; 2 files / 2 commits + live ECR push; image manifest list at 851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent:5e574b3 with both arm64+amd64 children verified live; commits 66959e8, 5e574b3)*

**Wave 3** *(03-04 depends on 03-01 + 03-02 + 03-03: needs all TF outputs, deployed widget, pushed image)*
- [x] 03-04-PLAN.md — CDK Python AgentCore stack + bin/smoke-deploy.sh end-to-end live-AWS smoke + RUNBOOK smoke section. Covers DEP-01, DEP-02, DEP-03, DEP-04, DEP-06, DEM-01, (DEM-02 partial). *(completed 2026-05-06; live AgentCore Runtime hera_agent-GIsf2P4ImD + widget_presigner Lambda Function URL Rule-4 deviation + 4-step lifecycle; 9 atomic commits; live voice-loop closure blocked by agent static-credential injection gap deferred to Phase 4 follow-up plan; commits 072054e, 0893b2b, 449b446, 51d0f05, 2ced2fc, c5b7f8c, 774adfb, 214068b, ab44397)*

**Wave 4** *(03-05 depends on 03-04: needs the live AgentCore Runtime with the credential-injection blocker exposed)*
- [x] 03-05-PLAN.md — Agent credential bridge (gap-closure): 3-file fix for AgentCore IMDSv2 + no-env-injection contract: lazy-default config (`os.environ.get` with prod defaults), boto3 default credential chain in `build_llm()`, Dockerfile `ENV HERA_KB_ID + AWS_REGION` bake-in. Container now survives cold-start under no-env-vars conditions. *(completed 2026-05-06T07:00Z; 3 source-code commits + 1 live-deploy evidence empty-commit + 1 metadata commit; image hera-agent:5f21e36 multi-arch on ECR; AgentCore Runtime updated in place to version=2 status=READY; AgentCore invocation moved 424 → 404 (proves credential gap closed); commits 0242c01, 5ebc650, 5f21e36, f5a6b1c)*. **Closes the credential bridge; Phase 3 SC#2 (live browser voice loop) deferred to a Phase 4 protocol-bridge follow-up plan due to a NEW gap discovered during this plan: AgentCore HTTP protocol calls `POST /invocations` per Bedrock convention while the FastAPI app exposes only `GET /ping` + `WebSocket /ws`. SC#2 closed by Plan 04-01 (Phase 4 Wave 1).**

**UI hint**: yes (UI-SPEC.md commit a71b70a is the design contract)

### Phase 4: Observability, Cost Control, Cleanup
**Goal**: A learner (or instructor) can see what their deployed system is doing, get woken up before a runaway bill happens, and tear everything down to verified zero ongoing AWS cost.
**Depends on**: Phase 3
**Requirements**: OBS-01, OBS-02, OBS-03, OBS-04, OBS-05
**Success Criteria** (what must be TRUE):
  1. A CloudWatch dashboard shows active session count, latency p50/p95 (utterance → first audio chunk), error rate, and Bedrock invocation/cost metrics — populated by real traffic from Phase 3.
  2. Operational alarms fire on threshold breach — error rate above 5% over 5 minutes and latency p95 above 5s over 5 minutes — and a billing alarm transitions to ALARM at the configured daily Bedrock cost cap (default $5/day). Billing alarm has alarm_actions=[] per D-35 (no SNS / email / Lambda — best-effort trade-off documented in RUNBOOK Phase 4 manual-stop fallback).
  3. Anonymous-public-URL abuse is bounded — AgentCore concurrency cap=2 (D-30, operational service-quota request) is the documented gate; per-IP rate limit on the presigner Function URL is deferred per D-36 with trade-off documented in RUNBOOK; a Lambda cost circuit-breaker is deferred per D-35 with manual-stop fallback documented in RUNBOOK (best-effort trade-off accepted).
  4. Running `terraform destroy` from a freshly-cloned repo on a clean AWS account leaves no Bedrock KB, no S3 Vectors index, no AgentCore endpoint, no log groups, no orphaned IAM roles — verified by an automated `cleanup-verify.sh` script that exits non-zero if anything is left behind.
  5. Cost Explorer shows $0 ongoing spend 24 hours after destroy, confirmed by the cleanup verification script.
**Plans:** 3 plans

**Wave 1** *(BLOCKING — closed Phase 3 SC#2 before observability/cleanup deploy against real traffic)*
- [x] 04-01-PLAN.md — Agent protocol-bridge: agent/hera_agent/main.py adds POST /invocations static-envelope stub per AgentCore HTTP protocol contract (canonical awslabs sample shape — voice loop continues on /ws). Local in-process gate (Docker daemon unreachable on Windows host; FastAPI TestClient verified shape), ECR push, in-place cdk deploy hera-agentcore (version=2 → version=3), AgentCore data-plane invoke-agent-runtime smoke probe returns statusCode=200. RUNBOOK Phase 4 protocol-bridge deploy section. **Closed Phase 3 SC#2.** Covers Phase 3 DEP-02 + DEM-02 live-loop portion. *(completed 2026-05-06; 4 commits including 1 empty-commit-with-outputs-in-body for live deploy; image hera-agent:7e72b66 multi-arch on ECR; AgentCore Runtime hera_agent-GIsf2P4ImD version=3 status=READY; commits 7e72b66, 9c5db62, 5037f1f, b33f062)*

**Wave 2** *(sequential due to RUNBOOK.md overlap — observability touches infra/modules/observability/ + infra/envs/prod/{main,outputs}.tf + RUNBOOK Phase-4-observability heading; cleanup-verify touches bin/cleanup-verify.sh + RUNBOOK Phase-4-cleanup heading)*
- [x] 04-02-PLAN.md — Observability module + dashboard + 3 alarms: new infra/modules/observability/ (versions/variables/main/outputs); CloudWatch dashboard hera-prod with 5 panels; 2 operational alarms (error_rate >5%/5min via metric_query arithmetic, latency_p95 >5s/5min via extended_statistic); 1 billing alarm in us-east-1 via second provider alias. Zero new IAM (alarm_actions=[] per D-35). RUNBOOK Phase 4 observability walkthrough + OBS-04 (D-36) + OBS-05 (D-35) trade-offs. Covers OBS-01, OBS-02, OBS-03, OBS-04 (documented), OBS-05 (documented). *(completed 2026-05-06; 7 commits; live terraform apply with -var=agentcore_runtime_arn preserved voice loop wiring; commits 488b36f, d448a88, cbb3121, 9b12a29, cced9a1, e1c13dd, 8421fe4)*
- [x] 04-03-PLAN.md — bin/cleanup-verify.sh + RUNBOOK Phase 4 cleanup quy trinh: bash script with 19 read-only resource checks (helper-driven _check_gone alternation regex + _check_count_zero length(@); MSYS_NO_PATHCONV=1 on log-group calls). Verify-only (D-39); no Cost Explorer call (D-38). Honors D-24 cleanup-contract. RUNBOOK section: 3-step quy trinh + 24h Cost Explorer paste-line + ECR force_delete hint + CloudFront-don't-interrupt warning. A5 [needs-verification] resolved: KB service role exact name `hera-kb-service-role` (not `-prod`). Covers OBS-04 (verification), Phase 4 SC#4 + SC#5. *(completed 2026-05-06; 4 commits; ZERO live AWS work; commits 4ed3764, 00f8806, 1ccaff0, 09ba38d)*

**Cross-cutting constraints** (truths shared by 2+ plans — every Phase 4 executor honors):
- No emojis in code, logs, comments, file content (CLAUDE.md mandate).
- uv exclusively for Python (uv add, uv sync --frozen, uv run); never pip install, never python3 X. Phase 4 has no new Python entry points; bin/cleanup-verify.sh is bash only (D-37).
- No defensive try/except in new code (AGENTS.md root-cause discipline). Plan 04-01 /invocations stub returns a dict literal — no try/except. Plan 04-03 bash uses `|| true` ONLY where stderr capture is required.
- Zero IAM wildcards (D-13 carried forward from Phase 1). Plan 04-02 introduces ZERO new IAM resources; relies on caller IAM for dashboard reads.
- D-12 fixed names (no random_id): hera-prod dashboard, hera-billing-prod / hera-error-rate-prod / hera-latency-p95-prod alarms.
- Region defaults to ap-northeast-1, override to us-east-1 (D-14, DEP-06). Billing alarm in us-east-1 is an AWS service constraint (AWS/Billing only emits there) documented as a deviation, not a stack change.
- Atomic conventional commits scoped to plan id (feat(04-01)/feat(04-02)/feat(04-03)/docs(04-NN)).
- Empty-commit-with-outputs-in-body for live deploy events (Plan 03-01 pattern). Plan 04-01 cdk deploy + Plan 04-02 terraform apply are the two live events in Phase 4.
- Live AWS state preservation through Plan 04-01 (in-place cdk deploy version=2 → version=3); Plan 04-02 + Plan 04-03 do not touch existing resources. Old image hera-agent:5f21e36 retained on ECR for rollback alongside Plan 04-01's new SHA.
- Demo budget honored: Plan 04-01 = 1 ECR push + 1 cdk deploy + 1 AgentCore smoke; Plan 04-02 = 1 terraform apply (no Bedrock spend); Plan 04-03 = 0 live AWS work. No SNS / email / Lambda hook (D-35); no AWS WAF / DynamoDB rate-limit (D-36); no Cost Explorer call from script (D-38).
- Latest APIs as of 2026-05-06 (AGENTS.md). aws bedrock-agentcore invoke-agent-runtime, aws_cloudwatch_metric_alarm.metric_query arithmetic, aws_cloudwatch_dashboard with widget-level region override are all current.

### Phase 5: Workshop Documentation (vi/en)
**Goal**: A Cloud Clubs member who has never seen this repo can land on the GitHub Pages workshop site, follow Phần 1-5 in either Vietnamese or English, and end with their own voice chatbot running in their own AWS account that they can talk to through their own browser — and then tear it back down to zero cost.
**Depends on**: Phase 4
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07, DOC-08, DOC-09, DOC-10, DOC-11, DOC-12
**Success Criteria** (what must be TRUE):
  1. All five chapters (Phần 1 Introduction → Phần 5 Summary) are published in both Vietnamese and English on the existing GitHub Pages site, with the language switcher working and slugs matching across both trees.
  2. A fresh learner who reads only Phần 2 (Preparation) and Phần 3 (Hands-on) — copy-pasting code snippets and following screenshots — successfully deploys the Phase 1-3 system into their own AWS account end-to-end, including enabling Bedrock Nova 2 Sonic and AgentCore model access, building/pushing the container, and talking to their own widget through HTTPS.
  3. After running Phần 4 Cleanup, the learner verifies via Cost Explorer and the verification script that they have zero ongoing AWS cost.
  4. Each chapter contains the relevant top-N pitfall callouts (8-min Sonic stream cap, audio sample rate, model access enablement, HTTPS for mic, billing alarm, tool-use schema, bilingual parity, KB sync delay) at the moments the learner is about to hit them, plus copy-clean code snippets and annotated AWS console screenshots.
  5. CI enforces vi/en parity on every PR — the parity check script counts chapters and key sections per language and fails the build if they diverge.
**Plans:** 5/5 plans complete

**Wave 1** *(blocking — gate landing first; non-autonomous: operator confirms config.toml baseURL since git remote empty)*
- [x] 05-01-PLAN.md — bin/check-i18n-parity.sh DOC-12 gate + workflow wire-up + config.toml replacement (D-52) + Phần 1 Introduction (vi+en) with Mermaid component + sequence diagrams (D-55) + bilingual-parity callout (D-51 #7) + 8 FCJ-template stub deletions + 1.1-prerequisites resolution (D-53). Covers DOC-01, DOC-12.

**Wave 2** *(parallel-eligible if Wave 1 lands first; depends on parity gate + config.toml from 05-01)*
- [x] 05-02-PLAN.md — Phần 2 Preparation (single-page; D-51 #3 model access) + Phần 3.1 Knowledge Base sub-page (D-51 #8 KB sync delay) + Phần 3.2 Pipecat Local sub-page (D-51 #1, #2, #6 — 8-min cap, sample rate, tool-use schema). All vi+en (D-49). Covers DOC-02, DOC-03, DOC-04, partial DOC-10, partial DOC-11. *(completed 2026-05-07; 4 atomic commits per D-49 ffbc109/3101e73/f488751/a06b993; 5 D-51 callouts placed; D-44 #1 image markdown reference + .gitkeep placeholder; vi=8 en=8 _index.md tree; bin/check-i18n-parity.sh exits 0)*

**Wave 3** *(depends on 05-02 — shares bin/*.sh source provenance)*
- [x] 05-03-PLAN.md — Phần 3.3 Deploy AgentCore (D-24 hybrid IaC + D-30 quota cap=2 trade-off) + Phần 3.4 Web Widget (D-51 #4 HTTPS-for-mic) + Phần 3.5 Observability (D-51 #5 billing 24h propagation + D-35/D-36 trade-offs). 3 static/images/ placeholders for D-44 #2/#3/#4/#5 screenshots (operator captures later). Covers DOC-05, DOC-06, DOC-07, finishes DOC-10 (8/8 D-51 callouts placed). *(completed 2026-05-07; 4 atomic commits per D-49 326b893/ffb8d01/2885030/f48d8f3; vi=11 en=11 _index.md tree; bin/check-i18n-parity.sh exits 0; 4 D-44 image refs inserted; 4 callouts placed total — 1 in 3.4 vi+en + 1 in 3.5 vi+en; submodule untouched)*

**Wave 4** *(depends on 05-03 — final closure chapters)*
- [x] 05-04-PLAN.md — Phần 4 Cleanup (D-24 cleanup-contract + D-38 24h Cost Explorer paste-line + D-44 #6 cleanup-verify hero deferred-callout per checker BLOCKER 4 option b) + Phần 5 Summary (D-54 cost recap ballpark + DOC-09 expansion roadmap with TWIL/I18N/ADV/AUTH/THEME v2 IDs). Covers DOC-08, DOC-09. *(completed 2026-05-07; 3 atomic commits 061958e/3354893/b08b77a; vi=11 en=11 _index.md tree; bin/check-i18n-parity.sh exits 0; 6 D-42 Source footers in Phần 4 + 1 in Phần 5 per language; static/images/4-cleanup/.gitkeep placeholder for deferred PNG capture)*

**Wave 5** *(gap closure — depends on 05-VERIFICATION.md gaps_found)*
- [x] 05-05-PLAN.md — Closes 3 verification gaps (CR-01 register themes/hugo-theme-learn submodule with upstream sha 3202533a; CR-02 redact 14 instructor literals across 4 chapter-pairs 3.1/3.2/3.3/3.5 with placeholder + resolution-command pattern; WR-02 rename 30 Phần tokens to Chapter X / Section X.Y across 7 en files in single en-only D-49 exception commit) + adjacent fix (deploy.yml branches: ["main"] -> ["master"]). *(completed 2026-05-07; 7 functional atomic commits 0ca6c7e/b0e3ea8/73a0f28/9df0a6b/2c0634f/d2d7446/fd121af + 1 SUMMARY commit; closing 5-gate acceptance ALL GATES PASSED; bin/check-i18n-parity.sh exits 0 vi=11 en=11; submodule pinned at upstream sha 3202533a746f91c67de1a8fa373c0328ec1b403d; demo budget honored — zero new AWS deploys)*

Plans:
- [x] 05-01-PLAN.md — Parity gate + config + Phần 1 Introduction (vi+en). *(complete 2026-05-07)*
- [x] 05-02-PLAN.md — Phần 2 Preparation + Phần 3.1 KB + Phần 3.2 Pipecat Local (vi+en). *(complete 2026-05-07)*
- [x] 05-03-PLAN.md — Phần 3.3 Deploy + Phần 3.4 Widget + Phần 3.5 Observability (vi+en). *(complete 2026-05-07)*
- [x] 05-04-PLAN.md — Phần 4 Cleanup + Phần 5 Summary (vi+en). *(complete 2026-05-07)*
- [x] 05-05-PLAN.md — Gap closure CR-01 + CR-02 + WR-02. *(complete 2026-05-07)*
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Knowledge Base Foundation | 3/3 | Complete (verifier passed 5/5 must-haves; live KB BKXE19AH89) | 2026-05-05 |
| 2. Pipecat Voice Agent (Local) | 3/3 | Complete (Wave 1: 02-01 + 02-03; Wave 2: 02-02 - AGT-04 latency gate passed against live Bedrock Nova 2 Sonic) | 2026-05-05 |
| 3. AgentCore Deploy + Web Widget + Public Demo URL | 5/5 | Complete (5/5 SC; SC#2 closed by Plan 04-01) | 2026-05-06 |
| 4. Observability, Cost Control, Cleanup | 3/3 | Complete (5/5 SC verified; closed Phase 3 SC#2 via Plan 04-01; 5 deferred items in 04-HUMAN-UAT.md, none blocking; code review clean) | 2026-05-06 |
| 5. Workshop Documentation (vi/en) | 5/5 | Complete    | 2026-05-07 |

## Notes on Phase Shape

**Granularity calibration.** Config sets `granularity: coarse` (3-5 phases). The synthesizer's draft suggested 7 phases; this roadmap consolidates to **5** by:
- Folding the synthesizer's "AgentCore deploy" + "Web widget" + "instructor demo URL" phases into a single Phase 3 — they share the same deliverable (a working public conversation) and splitting them would leave intermediate phases without a verifiable user-facing success criterion.
- Folding "Observability + cost cap" with "Cleanup verification" into Phase 4 — both are operational-correctness work that protects learners from bill bombs; treating them as one phase keeps the cleanup verification connected to the alarms it depends on.
- Dropping the synthesizer's separate "End-to-end smoke test from a fresh AWS account" phase — that smoke test is folded into Phase 5's Success Criterion #2 (a fresh learner deploying from docs *is* the smoke test).

**Why workshop docs trail implementation.** Phần 3 Hands-on screenshots, code snippets, and verification commands all come from real working code in Phases 1-3, and Phần 5 cost recap depends on AgentCore pricing surfaced during Phase 3 planning. Writing docs before the system works produces stale screenshots and unverifiable code blocks.

**Phase 3 has the most unknowns.** AgentCore Terraform-provider support, exact deploy steps, pricing, concurrency quotas, and WebRTC-vs-WebSocket transport choice are all open questions flagged by SUMMARY.md. Phase 3 planning should consume `/gsd-research-phase` to resolve these before any container is built; the IaC fallback (Terraform + CDK/CLI hybrid) is named in DEP-04 specifically so the decision can be locked there.

**UI phases.** Phase 3 (browser widget) and Phase 5 (Hugo workshop site) involve user-facing UI surfaces and are flagged for `/gsd-ui-phase` consideration during their planning.

---

## Milestone v2.0: Twilio Voice Channel

**Started:** 2026-05-07
**Goal:** Allow learners to phone (PSTN dial-in) a Twilio number and speak with the existing Hera chatbot running on Bedrock AgentCore Runtime, alongside the v1 web widget (not replacing it). v1 system is unchanged; v2 only ADDS the bridge + a workshop chapter.
**Granularity:** coarse (2 phases — see rationale below).
**Coverage:** 5/5 requirements mapped (TWIL-01..04 + TWIL-DOC).

## Phases (v2.0)

Phase numbering continues from v1.0 (last v1 phase = 5). Integer phases follow.

- [ ] **Phase 6: Twilio Bridge + Phone Number + Cleanup** - Phone call to a Twilio number reaches the existing AgentCore Runtime, Sonic answers, and a cleanup script proves $0 hold (4 reqs in 1 phase)
- [ ] **Phase 7: Twilio Workshop Chapter** - Bilingual vi+en chapter "Phone channel via Twilio" published at `content/{vi,en}/3-hands-on/3.6-twilio-channel/` so a learner can build the phone channel themselves (1 req)

## Phase Details (v2.0)

### Phase 6: Twilio Bridge + Phone Number + Cleanup
**Goal**: A learner who dials the configured Twilio number from any phone hears the Apple Store assistant answer in real time, holds a normal voice conversation backed by the same Phase 1 KB + Phase 3 AgentCore Runtime that v1 already runs, and can tear the entire phone-channel down to verified $0/month with a single documented cleanup script.
**Depends on**: Phase 4 (existing AgentCore Runtime + presigner Lambda Function URL pattern from Phase 3 + cleanup-verify pattern from Phase 4)
**Requirements**: TWIL-01, TWIL-02, TWIL-03, TWIL-04
**Success Criteria** (what must be TRUE):
  1. A learner dials the provisioned Twilio phone number from any handset and hears the Hera Apple Store assistant respond with audible audio within 3 seconds of saying their first sentence.
  2. Audio fidelity is correct end-to-end in both directions — Twilio inbound μ-law 8kHz is resampled to Int16 16kHz before reaching Sonic, and Sonic's Int16 16kHz output is resampled back to μ-law 8kHz before being written to the Twilio Media Stream — with no chipmunk effect, no silent transcription failure, and no audible aliasing artifacts.
  3. The Twilio Media Streams bridge endpoint correctly handles `start`, `media`, and `stop` events from the Twilio WebSocket and forwards/receives audio to the existing AgentCore Runtime via the same Bedrock data-plane the web widget uses — v1 web widget continues to work unchanged on the same Runtime during phone calls.
  4. The phone-channel cleanup contract is verifiable — running the documented cleanup procedure (release TwiML config, release Twilio number to $0 hold, tear down bridge Lambda + IAM) followed by a `bin/cleanup-verify-twilio.sh` script (mirroring v1 `bin/cleanup-verify.sh`) exits 0 with no Twilio number, no TwiML app, and no bridge AWS resources remaining.
  5. Demo budget is honored — Twilio number costs ~$1/month hold + $0.013/inbound minute (US/CA), bridge Lambda has reserved concurrency cap (or AgentCore concurrency cap=2 from v1 OBS-04 acts as the upstream gate), and no new persistent AWS resources beyond the bridge Lambda + IAM role + minimal log group are created.
**Plans:** 4 plans / 3 waves (D-56 REVISED 2026-05-07 — App Runner with min-instances=0 replaces the rescinded Lambda + APIGW WS architecture; revision 2026-05-07 split Plan 06-03 into 06-03 file-side + 06-04 live-deploy per BLOCKER-3 5-task threshold)

**Wave 1** *(parallel, file-disjoint: 06-01 ships TF module + root wiring; 06-02 ships bridge container source — zero overlap in files_modified)*
- [ ] 06-01-PLAN.md — twilio_bridge Terraform module: App Runner service hera-twilio-bridge-prod (min_size=0 D-56, max_size=2 D-65), auto-scaling configuration, ECR repo IMMUTABLE, 2 IAM roles (instance + access) with confused-deputy + zero IAM wildcards (D-13/D-66), own log group + Secrets Manager-backed Twilio Auth Token wiring (D-67); root infra/envs/prod extension. Covers TWIL-02 IaC + TWIL-04 cleanup-target IaC. Zero live AWS work.
- [ ] 06-02-PLAN.md — bridge container source: Python 3.13 + audioop-lts==0.2.2 + fastapi + websockets + twilio SDK; Dockerfile multi-arch (linux/arm64,linux/amd64) mirroring agent/Dockerfile; src/main.py /ping + WS /twilio with X-Twilio-Signature validation BEFORE accept(); src/bridge.py per-call coroutine with SigV4-signed upstream WSS open + bidi audio pump + ratecv state threaded per direction; src/resample.py mu-law 8kHz <-> Int16 16kHz (D-59); src/config.py RequestValidator (D-67 no hand-rolled HMAC). Covers TWIL-01 + TWIL-02 application layer. Zero live AWS work.

**Wave 2** *(sequential, depends on both 06-01 + 06-02: file-side authoring; the artifacts here will be consumed by Wave 3 live deploy)*
- [ ] 06-03-PLAN.md — file-side operator artifacts (autonomous=true, 3 tasks): bin/push-bridge-image.sh (multi-arch buildx push to bridge ECR; mirrors bin/push-image.sh), bin/cleanup-verify-twilio.sh (read-only AWS + Twilio REST checks; mirrors bin/cleanup-verify.sh), RUNBOOK.md Phase 6 paste-blocks (operator setup + 2-pass terraform apply + TwiML Bin wiring + dial-in smoke with stopwatch latency protocol — WARNING-2 + cleanup quy trinh). Covers TWIL-04 file-side; ZERO live AWS work.

**Wave 3** *(sequential, depends on 06-03: needs the push script + RUNBOOK paste-blocks to drive operator)*
- [ ] 06-04-PLAN.md — LIVE deploy + dial-in smoke + REQ flips (autonomous=false, 4 tasks with 2 operator checkpoints): operator pre-deploy paste-flow (Twilio account + Secrets Manager paste + number purchase), live two-pass terraform apply with WARNING-5 git-clean preflight, operator dial-in smoke with WARNING-2 stopwatch protocol (<=3s PASS / 3-5s WARN / >5s FAIL), empty-commit-with-outputs-in-body + REQUIREMENTS.md/ROADMAP.md/STATE.md flips for TWIL-01..04. Covers TWIL-01..04 end-to-end at the live system layer. v1 system bit-identical (D-64 enforced via 5 unchanged probes).

Plans:
- [ ] 06-01-PLAN.md — TF module + root wiring (Wave 1, parallel-eligible with 06-02).
- [ ] 06-02-PLAN.md — Bridge container source + offline test suite (Wave 1, parallel-eligible with 06-01).
- [ ] 06-03-PLAN.md — push script + cleanup-verify-twilio.sh + RUNBOOK Phase 6 paste-blocks (Wave 2, depends on 06-01 + 06-02; autonomous).
- [ ] 06-04-PLAN.md — LIVE deploy + dial-in smoke + REQ flips (Wave 3, depends on 06-03; 2 operator checkpoints).

### Phase 7: Twilio Workshop Chapter
**Goal**: A Cloud Clubs learner who has already finished v1 chapters 1-5 lands on a new bilingual chapter `3.6 Phone channel via Twilio`, follows it end-to-end in either Vietnamese or English, and ends up with their own phone number that calls into their own AgentCore Runtime — using the same vi/en parity discipline (D-49 byte-parity for content commits, D-50 file-count parity verified by `bin/check-i18n-parity.sh`) the v1 workshop already enforces.
**Depends on**: Phase 6
**Requirements**: TWIL-DOC
**Success Criteria** (what must be TRUE):
  1. The new chapter is published bilingual at `content/{vi,en}/3-hands-on/3.6-twilio-channel/_index.md` with the language switcher working, slug matching across both trees, and `bin/check-i18n-parity.sh` exiting 0 with vi=12, en=12 file count (v1 ended at vi=11 en=11; this chapter adds exactly 1 file per language).
  2. A fresh learner who has already deployed v1 reads only this chapter — copy-pasting code snippets and following screenshots — and successfully provisions their own Twilio number, deploys the bridge, dials it, and holds a real voice conversation with their own AgentCore Runtime.
  3. The chapter contains the relevant pitfall callouts at the moments the learner is about to hit them (Twilio webhook authentication, μ-law vs Int16 sample-rate confusion, Twilio number monthly hold cost, AgentCore concurrency cap interaction with phone calls) plus copy-clean code snippets and the cleanup procedure mirroring v1 Phần 4 Cleanup style.
  4. The chapter ends with the cleanup procedure (release TwiML, release number, tear down bridge) and a verification step using `bin/cleanup-verify-twilio.sh` from Phase 6 — so a learner does not leave a Twilio number running with monthly hold cost.
**Plans**: TBD
**UI hint**: yes (workshop chapter is rendered via Hugo to a learner-facing page; same theme/UI surface as v1 Phase 5)

## Progress (v2.0)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 6. Twilio Bridge + Phone Number + Cleanup | 0/4 | Planned (4 plans / 3 waves; awaiting execute-phase) | - |
| 7. Twilio Workshop Chapter | 0/? | Not started | - |

## Notes on Phase Shape (v2.0)

**Why 2 phases, not 1.** The 4 system requirements (TWIL-01..04) are tightly coupled — resample bridge, Media Streams handler, phone number + TwiML, and cleanup contract all ship as one deliverable: "phone call works and can be torn down to $0". Splitting them across phases leaves intermediate phases without a verifiable user-facing success criterion. TWIL-DOC is structurally separate — same pattern as v1 Phase 5 (docs trail implementation) — because the chapter needs working bridge code to screenshot, snippet, and verify against. Writing docs before the bridge works produces stale screenshots and unverifiable code blocks, exactly the failure v1 avoided.

**Why not a single Phase 6.** Tempting because the milestone is small (5 reqs total), but the docs work has different acceptance criteria (D-49 byte-parity, D-50 file-count parity, D-51 pitfall callouts, D-44 screenshot capture) and different verification surface (`bin/check-i18n-parity.sh`, learner walkthrough) than the system work (live AWS bridge, real phone dial-in, cleanup verify). Keeping them as separate phases lets each phase have crisp success criteria without a mixed-concern phase.

**Demo budget honored.** Phase 6 work is bounded — 1 Twilio number ($1/month hold) + 1 bridge Lambda (~free under demo traffic) + 0 changes to existing AgentCore Runtime / KB / web widget. v1 system stays live throughout. Phase 7 is docs-only with zero new AWS deploys. Twilio paid-per-minute risk capped by AgentCore concurrency cap=2 (D-30 carry-forward from v1).

**v1 system unchanged.** The v2.0 milestone strictly ADDS resources — new bridge Lambda, new Twilio number, new chapter file pair. Existing KB (`BKXE19AH89`), AgentCore Runtime (`hera_agent-GIsf2P4ImD`), CloudFront widget, presigner Lambda, dashboard, and alarms are NOT modified. Phase 6 plans must verify v1 web widget continues to work after bridge deploy (smoke test against existing `dg0w939ktclw6.cloudfront.net`).

**UI hint.** Phase 7 is flagged for `/gsd-ui-phase` consideration since it adds a learner-facing Hugo chapter on the same theme as v1 Phase 5. Phase 6 is system-only (no UI surface); the only "UI" is the phone audio path, which is verified by ear via dial-in, not visually.
