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
- [ ] **Phase 3: AgentCore Deploy + Web Widget + Public Demo URL** - Container deployed to Bedrock AgentCore Runtime; browser widget talks to it over a public HTTPS URL
- [ ] **Phase 4: Observability, Cost Control, Cleanup** - CloudWatch dashboards/alarms live, billing cap enforced, `terraform destroy` proven on a fresh account
- [ ] **Phase 5: Workshop Documentation (vi/en)** - 5 chapters published bilingual on GitHub Pages so a fresh learner can deploy their own copy

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
- [ ] 03-02-PLAN.md — Polished frontend widget (Apple-Store light per UI-SPEC) + bin/build-widget.sh sed-injection script. Covers WID-01, WID-02, WID-03, WID-04, WID-05, WID-06, DEM-03.

**Wave 2** *(03-03 depends on 03-01: needs ECR repo URL output)*
- [ ] 03-03-PLAN.md — bin/push-image.sh multi-arch buildx push to ECR + RUNBOOK Phase 3 deploy section. Covers DEP-02, DEP-03.

**Wave 3** *(03-04 depends on 03-01 + 03-02 + 03-03: needs all TF outputs, deployed widget, pushed image)*
- [ ] 03-04-PLAN.md — CDK Python AgentCore stack + bin/smoke-deploy.sh end-to-end live-AWS smoke + RUNBOOK smoke section. Covers DEP-01, DEP-02, DEP-03, DEP-04, DEP-06, DEM-01, DEM-02.

**UI hint**: yes (UI-SPEC.md commit a71b70a is the design contract)

### Phase 4: Observability, Cost Control, Cleanup
**Goal**: A learner (or instructor) can see what their deployed system is doing, get woken up before a runaway bill happens, and tear everything down to verified zero ongoing AWS cost.
**Depends on**: Phase 3
**Requirements**: OBS-01, OBS-02, OBS-03, OBS-04, OBS-05
**Success Criteria** (what must be TRUE):
  1. A CloudWatch dashboard shows active session count, latency p50/p95 (utterance → first audio chunk), error rate, and Bedrock invocation/cost metrics — populated by real traffic from Phase 3.
  2. Operational alarms fire on threshold breach — error rate above 5% over 5 minutes and latency p95 above 5s over 5 minutes — and a billing alarm triggers SNS at the configured daily Bedrock cost cap (default $5/day).
  3. Anonymous-public-URL abuse is bounded — AgentCore concurrency limits and per-IP rate limits are configured, and a Lambda cost circuit-breaker can stop the AgentCore endpoint when the billing alarm fires (best-effort, trade-off documented).
  4. Running `terraform destroy` from a freshly-cloned repo on a clean AWS account leaves no Bedrock KB, no S3 Vectors index, no AgentCore endpoint, no log groups, no orphaned IAM roles — verified by an automated `cleanup-verify.sh` script that exits non-zero if anything is left behind.
  5. Cost Explorer shows $0 ongoing spend 24 hours after destroy, confirmed by the cleanup verification script.
**Plans**: TBD

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
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Knowledge Base Foundation | 3/3 | Complete (verifier passed 5/5 must-haves; live KB BKXE19AH89) | 2026-05-05 |
| 2. Pipecat Voice Agent (Local) | 3/3 | Complete (Wave 1: 02-01 + 02-03; Wave 2: 02-02 - AGT-04 latency gate passed against live Bedrock Nova 2 Sonic) | 2026-05-05 |
| 3. AgentCore Deploy + Web Widget + Public Demo URL | 1/4 | Wave 1 in progress (03-01 complete; 03-02 next) | - |
| 4. Observability, Cost Control, Cleanup | 0/TBD | Not started | - |
| 5. Workshop Documentation (vi/en) | 0/TBD | Not started | - |

## Notes on Phase Shape

**Granularity calibration.** Config sets `granularity: coarse` (3-5 phases). The synthesizer's draft suggested 7 phases; this roadmap consolidates to **5** by:
- Folding the synthesizer's "AgentCore deploy" + "Web widget" + "instructor demo URL" phases into a single Phase 3 — they share the same deliverable (a working public conversation) and splitting them would leave intermediate phases without a verifiable user-facing success criterion.
- Folding "Observability + cost cap" with "Cleanup verification" into Phase 4 — both are operational-correctness work that protects learners from bill bombs; treating them as one phase keeps the cleanup verification connected to the alarms it depends on.
- Dropping the synthesizer's separate "End-to-end smoke test from a fresh AWS account" phase — that smoke test is folded into Phase 5's Success Criterion #2 (a fresh learner deploying from docs *is* the smoke test).

**Why workshop docs trail implementation.** Phần 3 Hands-on screenshots, code snippets, and verification commands all come from real working code in Phases 1-3, and Phần 5 cost recap depends on AgentCore pricing surfaced during Phase 3 planning. Writing docs before the system works produces stale screenshots and unverifiable code blocks.

**Phase 3 has the most unknowns.** AgentCore Terraform-provider support, exact deploy steps, pricing, concurrency quotas, and WebRTC-vs-WebSocket transport choice are all open questions flagged by SUMMARY.md. Phase 3 planning should consume `/gsd-research-phase` to resolve these before any container is built; the IaC fallback (Terraform + CDK/CLI hybrid) is named in DEP-04 specifically so the decision can be locked there.

**UI phases.** Phase 3 (browser widget) and Phase 5 (Hugo workshop site) involve user-facing UI surfaces and are flagged for `/gsd-ui-phase` consideration during their planning.
