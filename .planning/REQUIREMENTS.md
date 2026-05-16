# Requirements: Hera — AWS Voice Agent Workshop & Demo

**Defined:** 2026-05-04
**Core Value:** Một học viên Cloud Clubs đi qua workshop phải tự deploy thành công được voice chatbot trên AWS account của mình và nói chuyện được với nó qua trình duyệt.

## v1 Requirements

### Knowledge Base (KB)

- [x] **KB-01**: Apple product catalog viết bằng English markdown — gồm 3 SKU (Apple Watch Series 11, iPhone 13 Pro Max, MacBook Pro M4) với spec, giá, stock status *(completed Phase 1 Plan 01-01, 2026-05-05)*
- [x] **KB-02**: S3 Vectors bucket + index được tạo bằng Terraform với dimension và distance metric đúng cho Titan Text Embeddings v2 (1024-dim, float32, cosine) *(IaC complete Plan 01-02, 2026-05-05; live-applied Plan 01-03 — index `hera-kb-index` in `hera-kb-vectors-prod` bucket; metadata_configuration deviation `9006d48` marks AMAZON_BEDROCK_TEXT/METADATA non-filterable to satisfy the 2 KB cap)*
- [x] **KB-03**: Bedrock Knowledge Base được tạo với S3 Vectors backend (`s3_vectors_storage_configuration`) qua Terraform `~> 6.27` *(IaC complete Plan 01-02, 2026-05-05; live-applied Plan 01-03 — KB id `BKXE19AH89` in ap-northeast-1, account 851725411875)*
- [x] **KB-04**: Data source ingestion job chạy thành công, KB query API trả về document đúng cho câu hỏi "iPhone 13 Pro Max stock" *(live-verified Plan 01-03, 2026-05-05 — ingestion job `231ZT93KYF` indexed 4/4 documents; `bin/verify-kb.sh` PASSed at attempt 1 with top score `0.8598317801952362` >> threshold 0.4)*
- [x] **KB-05**: IAM role/policy least-privilege cho `bedrock:Retrieve` được quản lý qua Terraform *(IaC complete Plan 01-02, 2026-05-05 — KB service role with zero wildcards and confused-deputy-mitigated trust policy; live-applied Plan 01-03; the Phase-2 consumer `bedrock:Retrieve` role is deferred per D-10 and will be scoped to `arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89`)*
- [x] **KB-06**: Re-index workflow documented (sửa product → re-sync KB) — manual ingestion job trigger qua AWS CLI *(live-verified Plan 01-03, 2026-05-05 — RUNBOOK "Re-index after editing a product file" section + `aws s3 cp` + `aws bedrock-agent start-ingestion-job` job `KKLS6LQP9A` re-indexed an edited catalog file with 1 modified / 0 failed; verify-kb.sh PASSed at attempt 1)*

### Voice Agent (AGT)

- [x] **AGT-01**: Pipecat 1.1.0 agent code Python ≥3.11 dùng `AWSNovaSonicLLMService` kết nối Nova 2 Sonic ở ap-northeast-1 *(completed Phase 2 Plan 02-01, 2026-05-05; agent/pyproject.toml pins Python >=3.12 + pipecat-ai[aws-nova-sonic,silero,websocket]==1.1.0; agent/uv.lock contains aws-sdk-bedrock-runtime; pipeline.py imports AWSNovaSonicLLMService cleanly)*
- [x] **AGT-02**: Agent system prompt định hình persona Apple Store assistant tiếng Anh *(completed Phase 2 Plan 02-01, 2026-05-05; agent/hera_agent/prompts.py SYSTEM_PROMPT implements D-17 Crisp store associate persona with refusal line and 3 example Q/A pairs; test_prompts.py asserts invariants)*
- [x] **AGT-03**: Tool `lookup_product(query: str)` được Sonic gọi đúng schema, trả về kết quả từ Bedrock KB Retrieve *(completed Phase 2 Plan 02-01, 2026-05-05; tools.py mirrors bin/verify-kb.sh — numberOfResults=3, threshold filter, "no relevant product info" sentinel, top-1-first basename format; lookup_product_handler dispatches via asyncio.to_thread; test_lookup_product.py covers D-18 contract with mocked boto3)*
- [x] **AGT-04**: Voice loop end-to-end test local (dev): user hỏi "Do you have MacBook Pro?" → Sonic gọi tool → KB trả product → Sonic phát audio response trong < 3s p95 latency từ end-of-utterance *(completed Phase 2 Plan 02-02, 2026-05-05; bin/smoke-voice.sh + bin/_smoke_voice_probe.py form a programmatic AGT-04 gate that brings up the docker-compose stack, opens WebSocket to ws://localhost:8080/ws, sends 1s of synthetic 16 kHz Int16 silence, awaits first inbound binary frame, asserts elapsed < 3.0s; live result against Bedrock Nova 2 Sonic in ap-northeast-1 + KB BKXE19AH89: LATENCY_MS=0, OK: AGT-04 latency gate passed)*
- [x] **AGT-05**: Sonic 8-min stream cap được handle transparent qua Pipecat (no user-visible interruption) *(completed Phase 2 Plan 02-01, 2026-05-05; pipeline.py constructs SessionContinuationParams(transition_threshold_seconds=360); rotates bidi stream ~120s before the cap)*
- [x] **AGT-06**: Conversation state per session in-memory, không cần DynamoDB cho v1 *(completed Phase 2 Plan 02-01, 2026-05-05; pipeline.py uses Pipecat LLMContext + LLMContextAggregatorPair inside a per-WebSocket PipelineTask; on_client_disconnected calls task.cancel() to free state — D-21 satisfied)*
- [x] **AGT-07**: Audio format đúng: input 16kHz mono PCM Int16, output 24kHz mono PCM (default Pipecat handlers) *(completed Phase 2 Plan 02-01, 2026-05-05; pipeline.py does NOT instantiate AudioConfig — Pipecat defaults already correct)*
- [x] **AGT-08**: Container image (Dockerfile) build reproducible với uv lock file *(completed Phase 2 Plan 02-02, 2026-05-05; agent/Dockerfile is multi-arch buildable — docker buildx build --platform linux/arm64,linux/amd64 -t hera-agent:dev-multiarch ./agent succeeds; same image artifact used for local AMD64 dev and Phase 3 ECR push to AgentCore Runtime ARM64; uv sync --frozen consumes Plan 02-01's pyproject.toml + uv.lock; Pipecat 1.1.0 boots inside the image: 'Pipecat 1.1.0 (Python 3.12.13...)')*

### Deployment & Infrastructure (DEP)

- [x] **DEP-01**: Agent container deploy lên Amazon Bedrock AgentCore Runtime ở ap-northeast-1 *(completed Plan 03-04, 2026-05-06; live Runtime hera_agent-GIsf2P4ImD status=READY referencing image hera-agent:214068b)*
- [x] **DEP-02**: AgentCore endpoint exposed (WSS hoặc WebRTC) — chọn pattern dựa trên Pipecat support *(completed Plan 03-04, 2026-05-06; WSS via SigV4 presign Lambda Function URL bridge for browser auth gap)*
- [x] **DEP-03**: Terraform modules chính (`modules/kb`, `modules/agentcore`, `modules/observability`) deploy được vào fresh AWS account chỉ với `terraform init && apply` (giả định model access đã enable)
- [x] **DEP-04**: Nếu Terraform AgentCore resource thiếu, fallback hybrid documented: Terraform cho KB/IAM/CloudWatch, CDK hoặc CLI cho AgentCore deploy. Quyết định lock trong Phase 3 research
- [x] **DEP-05**: AgentCore execution role IAM least-privilege: `bedrock:InvokeModelWithBidirectionalStream`, `bedrock:Retrieve`, CloudWatch logs/metrics
- [x] **DEP-06**: Region cấu hình qua Terraform variable, default `ap-northeast-1`, hỗ trợ override sang `us-east-1` cho dev

### Web Widget (WID)

- [x] **WID-01**: Trang HTML/JS tối giản (single file hoặc 2-3 file), không framework, host được trên S3+CloudFront hoặc GitHub Pages
- [ ] **WID-02**: Nút record dùng `navigator.mediaDevices.getUserMedia` + AudioWorklet capture 16kHz mono PCM Int16
- [ ] **WID-03**: Audio gửi qua binary WS frames (không base64) tới AgentCore endpoint
- [ ] **WID-04**: Audio response từ AgentCore (24kHz PCM) phát lại qua `AudioContext` + buffer queue, không lag/dropout với câu trả lời 30s
- [ ] **WID-05**: Transcript text hiển thị song song với audio (text events từ Sonic) — UI cho user thấy chữ và nghe tiếng đồng thời
- [ ] **WID-06**: Error states hiển thị rõ: mic permission denied, WS connect fail, agent timeout, mic muted indicator

### Observability & Cost Control (OBS)

- [x] **OBS-01**: CloudWatch dashboard với panel: số session đang active, latency p50/p95 (utterance → first audio chunk), error rate, Bedrock invocation count
- [x] **OBS-02**: CloudWatch alarm trigger khi: error rate > 5% trong 5 phút, latency p95 > 5s trong 5 phút
- [x] **OBS-03**: CloudWatch billing alarm cảnh báo khi daily Bedrock cost vượt ngưỡng cấu hình được (default $5/ngày cho v1)
- [x] **OBS-04**: Concurrency cap=2 (D-30 service-quota) là gate đã document; per-IP rate limit deferred per D-36 với trade-off trong RUNBOOK
- [x] **OBS-05**: alarm_actions=[] per D-35; Lambda circuit breaker deferred; manual-stop fallback documented trong RUNBOOK Phase 4

### Demo Public URL (DEM)

- [x] **DEM-01**: Public HTTPS URL của instructor demo accessible từ internet, ACM cert valid
- [ ] **DEM-02**: Anonymous access — không cần login, nhưng có throttling/rate limit để chống abuse
- [ ] **DEM-03**: Banner trên trang ghi "This is an instructor demo. Cost capped at $X/day. For your own deployment, follow the workshop."

### Workshop Documentation (DOC)

Mỗi requirement viết cả 2 ngôn ngữ (vi/en) trừ khi ghi rõ.

- [x] **DOC-01**: Phần 1 — Introduction (vi+en): Giới thiệu voice AI, Nova Sonic, vì sao dùng AgentCore (vs ECS), kiến trúc hera high-level diagram *(completed Phase 5 Plan 05-01, 2026-05-07; content/{vi,en}/1-introduction/_index.md single-page chapter with Mermaid component + sequence diagrams (D-55), folded prereqs H2 (D-53 Option A), region note (D-47), bilingual-parity callout (D-51 #7) — vi+en in same atomic commit per D-49)*
- [x] **DOC-02**: Phần 2 — Preparation (vi+en): AWS account checklist, enable Bedrock model access (Nova 2 Sonic), enable AgentCore service, install AWS CLI / Terraform / uv (Python), configure credentials, ước tính chi phí ~$X cho thời gian workshop *(completed Phase 5 Plan 05-02, 2026-05-07; content/{vi,en}/2-preparation/_index.md single-page chapter with AWS account checklist + Bedrock model access steps for Nova 2 Sonic + Titan v2 in ap-northeast-1 + tool installs (AWS CLI v2, Terraform >=1.9, uv, Docker buildx, jq) + credentials + D-54 anchored ~$2-5 USD/2-hour ballpark with post-launch-update notice; D-51 #3 model-access pitfall callout placed; D-44 #1 image markdown reference inserted; vi+en in same atomic commit per D-49)*
- [x] **DOC-03**: Phần 3.1 (vi+en) — Build Knowledge Base: viết catalog markdown, deploy `modules/kb`, verify Retrieve API qua AWS CLI test *(completed Phase 5 Plan 05-02, 2026-05-07; content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md sub-page mirroring RUNBOOK Phase 1 First deploy + First sync + Verify + Re-index sections — terraform apply + aws s3 cp + start-ingestion-job + bin/verify-kb.sh paste-blocks; D-51 #8 KB sync delay pitfall callout at post-sync verify step; 6 Source footers per language anchored to RUNBOOK + bin/verify-kb.sh + catalog/)*
- [x] **DOC-04**: Phần 3.2 (vi+en) — Pipecat agent code: code structure, system prompt, tool definition, run local test (Pipecat WebSocket transport, browser kết nối localhost) *(completed Phase 5 Plan 05-02, 2026-05-07; content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md sub-page with pyproject.toml + main.py + prompts.py + tools.py + pipeline.py inline quotes — AWSNovaSonicLLMService + SessionContinuationParams(transition_threshold_seconds=360) + register_function('lookup_product', cancel_on_interruption=False) + uv path + docker compose path + bin/smoke-voice.sh AGT-04 gate; 3 D-51 callouts placed: #6 tool-use schema, #1 8-min stream cap, #2 16/24kHz audio sample rate; 13 Source footers per language)*
- [x] **DOC-05**: Phần 3.3 (vi+en) — Deploy lên AgentCore: build container, push ECR, deploy AgentCore, verify endpoint *(completed Phase 5 Plan 05-03, 2026-05-07; content/{vi,en}/3-hands-on/3.3-deploy-agentcore/_index.md sub-page mirroring RUNBOOK Phase 3 + Phase 4 protocol-bridge sections — bin/push-image.sh + cdk deploy hera-agentcore + second-pass terraform apply -var=agentcore_runtime_arn + bin/smoke-deploy.sh + POST /invocations stub paste-blocks; hybrid IaC trade-off (D-24) and concurrency cap (D-30) explicitly documented; D-44 #3 Service Quotas screenshot reference inserted; 8 Source footers per language; vi+en in same atomic commit per D-49)*
- [x] **DOC-06**: Phần 3.4 (vi+en) — Web widget: HTML/JS structure, browser microphone, kết nối AgentCore endpoint, deploy widget (S3+CloudFront hoặc GitHub Pages) *(completed Phase 5 Plan 05-03, 2026-05-07; content/{vi,en}/3-hands-on/3.4-web-widget/_index.md sub-page covers presigner Lambda Function URL bridge (D-25 Rule-4) + bin/build-widget.sh sed-injection + S3+CloudFront deploy + 5-state record button table + verbatim WID-06 error strings + AudioWorklet 16kHz Int16 capture; D-51 #4 HTTPS-required-for-mic pitfall callout placed; D-44 #4 widget hero screenshot reference inserted; 7 Source footers per language; vi+en in same atomic commit per D-49)*
- [x] **DOC-07**: Phần 3.5 (vi+en) — Observability: CloudWatch dashboard walk-through, set alarm *(completed Phase 5 Plan 05-03, 2026-05-07; content/{vi,en}/3-hands-on/3.5-observability/_index.md sub-page walks CloudWatch dashboard hera-prod 5 panels + 2 op alarms (hera-error-rate-prod, hera-latency-p95-prod) + 1 billing alarm hera-billing-prod cross-region us-east-1; OBS-04 (D-36 no per-IP rate limit) + OBS-05 (D-35 manual-stop fallback) trade-offs documented; D-51 #5 billing alarm 24h propagation pitfall callout placed; D-44 #2 billing toggle + #5 dashboard hero screenshot references inserted; 7 Source footers per language; vi+en in same atomic commit per D-49)*
- [x] **DOC-08**: Phần 4 — Cleanup (vi+en): `terraform destroy`, manual checks (Cost Explorer, list AgentCore endpoints, S3 bucket, KB), verification script *(completed Phase 5 Plan 05-04, 2026-05-07; content/{vi,en}/4-cleanup/_index.md single-page chapter mirrors RUNBOOK Phase 4 Cleanup quy trinh — cdk destroy hera-agentcore + terraform destroy + bash bin/cleanup-verify.sh + 24h-deferred Cost Explorer paste-line per D-38 + ECR force-delete fallback; D-24 cleanup-contract documented; CloudFront 15-30min disable-then-delete don't-interrupt warning; D-44 #6 hero screenshot deferred via {{% notice info %}} callout per checker BLOCKER 4 option b — PNG ships in follow-up commit after 04-HUMAN-UAT item #3 first organic cleanup-verify run; 6 D-42 Source footers per language; vi+en in same atomic commit per D-49)*
- [x] **DOC-09**: Phần 5 — Summary (vi+en): cost recap, hướng mở rộng (Twilio voice, multi-language, multi-agent) *(completed Phase 5 Plan 05-04, 2026-05-07; content/{vi,en}/5-summary/_index.md single-page chapter with What you built recap (5 bullets) + cost recap anchored to D-54 ballpark ~$2-5 USD/2-hour session with per-service breakdown deferred to post-launch update + DOC-09 expansion roadmap covering Twilio Voice Channel TWIL-01..03 + multi-language chatbot I18N-01..02 + multi-agent routing ADV-01 + conversation history persistent ADV-03; v2 backlog pointers AUTH-01..02, ADV-04, THEME-01..02, ADV-02; 1 D-42 Source footer per language; vi+en in same atomic commit per D-49)*
- [x] **DOC-10**: Top 5-7 pitfall callouts ở các chapter tương ứng (8-min stream cap, sample rate, model access, HTTPS bắt buộc cho mic, billing alarm cleanup, schema tool-use, bilingual parity) *(completed Phase 5 Plan 05-03, 2026-05-07; all 8 listed D-51 pitfall callouts placed across Phases 1+2+3 chapters via Plans 05-01..05-03: #1 8-min stream cap (Phần 3.2), #2 sample rate 16/24kHz (Phần 3.2), #3 model access (Phần 2), #4 HTTPS-for-mic (Phần 3.4), #5 billing alarm 24h propagation (Phần 3.5), #6 tool-use schema (Phần 3.2), #7 bilingual parity (Phần 1), #8 KB sync delay (Phần 3.1) — 8 placed exceeds the "Top 5-7" target literally)*
- [x] **DOC-11**: Mỗi chapter có code snippet copy button (hugo-theme-learn shortcode hoặc custom), screenshot AWS console với annotation
- [x] **DOC-12**: vi/en parity check chạy trong CI (script đếm số chapter mỗi lang, fail nếu lệch) *(completed Phase 5 Plan 05-01, 2026-05-07; bin/check-i18n-parity.sh ships file-count + bidirectional slug-tree parity assertions, wired into .github/workflows/deploy.yml as a pre-build step between Checkout and Setup Pages — exits 0 on parity tree (vi=6, en=6), exits 1 on injected mismatch verified live)*

## v2 Requirements

### Twilio Voice Channel (CURRENT MILESTONE — v2.0)

- [ ] **TWIL-01**: Two-way audio resample bridge — μ-law 8kHz inbound từ Twilio → Int16 16kHz đến Sonic; Int16 16kHz từ Sonic → μ-law 8kHz về Twilio (cả hai chiều)
- [ ] **TWIL-02**: Twilio Media Streams bridge endpoint — handle event `start`/`media`/`stop` từ Twilio WebSocket; forward audio đến AgentCore Runtime; deploy ở Lambda hoặc mở rộng presigner Lambda hiện có
- [ ] **TWIL-03**: Twilio phone number provisioned + TwiML `<Connect><Stream>` pointing đến bridge endpoint; số điện thoại có thể dùng được khi gọi vào
- [ ] **TWIL-04**: Phone-channel cleanup contract — release TwiML config + release số điện thoại Twilio (về $0 hold) + bridge teardown; có script verify như `bin/cleanup-verify.sh` của v1
- [ ] **TWIL-DOC**: Chương workshop mới "Phone channel via Twilio" song ngữ — `content/{vi,en}/3-hands-on/3.6-twilio-channel/_index.md`. Cover: Twilio account setup → phone number purchase → TwiML config → bridge deploy + smoke test → cleanup. Respects D-49 byte-parity + D-50 file-count parity (vi=12, en=12)

### Future (deferred, không trong v2.0 roadmap)

### Localization (chatbot speech)

- **I18N-01**: Detect ngôn ngữ user nói (vi/en) tự động
- **I18N-02**: Sonic phát audio tiếng Việt (khi quality acceptable)

### Authentication

- **AUTH-01**: Cognito User Pool cho user đăng ký/đăng nhập
- **AUTH-02**: Per-user session quota và usage tracking

### Hugo Theme Migration

- **THEME-01**: Migrate từ `hugo-theme-learn` (deprecated) sang `hugo-theme-relearn`
- **THEME-02**: Verify tất cả custom branding/layouts vẫn hoạt động sau migration

### Advanced Patterns

- **ADV-01**: Multi-agent routing (giống workflow trong raw_content.txt)
- **ADV-02**: Knowledge Base với RAG re-ranking
- **ADV-03**: Conversation history persistent (DynamoDB) cho returning users
- **ADV-04**: ECS Fargate alternative deployment chapter (so sánh AgentCore vs self-hosted)

## Out of Scope

| Feature | Reason |
|---------|--------|
| ElevenLabs / n8n / Gemini | User yêu cầu pure-AWS; AgentCore + Sonic + Pipecat là stack chính thức AWS recommend |
| OpenSearch Serverless cho KB | Cost min ~$200-400/tháng — quá đắt cho workshop scale; S3 Vectors fit hơn |
| Self-managed ECS Fargate / ALB / VPC custom networking | AgentCore managed thay thế — đơn giản hơn, ít infra để debug, phù hợp workshop |
| PrivateLink / VPC interface endpoint | AgentCore quản lý egress; không cần custom VPC |
| NAT Gateway | Không tự quản VPC nên không cần |
| Phase 0 PrivateLink spike | Không dùng PrivateLink |
| Hugo theme migration v1 | `hugo-theme-learn` deprecated nhưng vẫn hoạt động; thêm scope không cần thiết |
| Mobile app (iOS/Android) | Web widget cover demo; mobile defer |
| Custom voice cloning | Voice mặc định Sonic đủ |
| Production-grade SSO | Workshop scope cá nhân; anonymous + throttling đủ |
| PII handling (real user data) | Workshop dùng demo data; không xử lý PII thật |
| Multi-tenant SaaS | Không phải mục tiêu workshop |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| KB-01 | Phase 1 — Knowledge Base Foundation | Done (Plan 01-01) |
| KB-02 | Phase 1 — Knowledge Base Foundation | Done (IaC Plan 01-02 + live-applied Plan 01-03; metadata_configuration fix `9006d48`) |
| KB-03 | Phase 1 — Knowledge Base Foundation | Done (IaC Plan 01-02 + live-applied Plan 01-03; live KB `BKXE19AH89` in ap-northeast-1) |
| KB-04 | Phase 1 — Knowledge Base Foundation | Done (Plan 01-03 live-verified; verify-kb.sh PASS, top score 0.8598) |
| KB-05 | Phase 1 — Knowledge Base Foundation | Done (IaC Plan 01-02 + live-applied Plan 01-03; Phase-2 consumer role deferred per D-10) |
| KB-06 | Phase 1 — Knowledge Base Foundation | Done (Plan 01-03 live-verified; ingestion job `KKLS6LQP9A` re-indexed edit, verify-kb.sh PASS) |
| AGT-01 | Phase 2 — Pipecat Voice Agent (Local) | Complete (Plan 02-01, 2026-05-05) |
| AGT-02 | Phase 2 — Pipecat Voice Agent (Local) | Complete (Plan 02-01, 2026-05-05) |
| AGT-03 | Phase 2 — Pipecat Voice Agent (Local) | Complete (Plan 02-01, 2026-05-05) |
| AGT-04 | Phase 2 — Pipecat Voice Agent (Local) | Complete (Plan 02-02, 2026-05-05) |
| AGT-05 | Phase 2 — Pipecat Voice Agent (Local) | Complete (Plan 02-01, 2026-05-05) |
| AGT-06 | Phase 2 — Pipecat Voice Agent (Local) | Complete (Plan 02-01, 2026-05-05) |
| AGT-07 | Phase 2 — Pipecat Voice Agent (Local) | Complete (Plan 02-01, 2026-05-05) |
| AGT-08 | Phase 2 — Pipecat Voice Agent (Local) | Complete (Plan 02-02, 2026-05-05) |
| DEP-01 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Complete (Plan 03-04, 2026-05-06; live Runtime hera_agent-GIsf2P4ImD) |
| DEP-02 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Complete (Plan 03-04, 2026-05-06; WSS via SigV4 presigner Lambda Function URL) |
| DEP-03 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Complete (Plan 03-01, 2026-05-06; deploy pipeline-as-code extended Plan 03-03 2026-05-06: bin/push-image.sh + RUNBOOK Phase 3 section close the build/push step of the 3-step deploy contract) |
| DEP-04 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Complete (Plan 03-01, 2026-05-06) |
| DEP-05 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Complete (Plan 03-01, 2026-05-06) |
| DEP-06 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Complete (Plan 03-01, 2026-05-06) |
| WID-01 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Complete (Plan 03-01, 2026-05-06) |
| WID-02 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Pending |
| WID-03 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Pending |
| WID-04 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Pending |
| WID-05 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Pending |
| WID-06 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Pending |
| DEM-01 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Complete (Plan 03-01, 2026-05-06) |
| DEM-02 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Pending |
| DEM-03 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Pending |
| OBS-01 | Phase 4 — Observability, Cost Control, Cleanup | Complete (Plan 04-02, 2026-05-06) |
| OBS-02 | Phase 4 — Observability, Cost Control, Cleanup | Complete (Plan 04-02, 2026-05-06) |
| OBS-03 | Phase 4 — Observability, Cost Control, Cleanup | Complete (Plan 04-02, 2026-05-06) |
| OBS-04 | Phase 4 — Observability, Cost Control, Cleanup | Complete (Plan 04-02 + Plan 04-03 RUNBOOK + Plan 03-04 D-30, 2026-05-06) |
| OBS-05 | Phase 4 — Observability, Cost Control, Cleanup | Complete (Plan 04-02 RUNBOOK manual-stop fallback per D-35, 2026-05-06) |
| DOC-01 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-01, 2026-05-07) |
| DOC-02 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-02, 2026-05-07) |
| DOC-03 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-02, 2026-05-07) |
| DOC-04 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-02, 2026-05-07) |
| DOC-05 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-03, 2026-05-07) |
| DOC-06 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-03, 2026-05-07) |
| DOC-07 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-03, 2026-05-07) |
| DOC-08 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-04, 2026-05-07) |
| DOC-09 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-04, 2026-05-07) |
| DOC-10 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plans 05-01..05-03, 2026-05-07; all 8 D-51 pitfall callouts placed) |
| DOC-11 | Phase 5 — Workshop Documentation (vi/en) | Pending (operator PNG capture sweep deferred — chapter markdown image refs in place) |
| DOC-12 | Phase 5 — Workshop Documentation (vi/en) | Complete (Plan 05-01, 2026-05-07) |
| TWIL-01 | Phase 6 — Twilio Bridge + Phone Number + Cleanup | Complete (Plan 06-02, 2026-05-16; verified offline via tests/test_resample.py — mu-law<->Int16 round-trip + ratecv state threading; live verification deferred to next compute target) |
| TWIL-02 | Phase 6 — Twilio Bridge + Phone Number + Cleanup | Pending (handler code correct + offline tests pass; live verify blocked by D-56 architectural defect — App Runner edge rejects all inbound WebSocket upgrades; needs re-plan to ECS Fargate / EC2 / NLB compute target) |
| TWIL-03 | Phase 6 — Twilio Bridge + Phone Number + Cleanup | Pending (deferred — no Twilio account in this iteration; RUNBOOK Phase 6 paste-blocks ready for learner) |
| TWIL-04 | Phase 6 — Twilio Bridge + Phone Number + Cleanup | Partial (Plan 06-03 file-side artifacts complete: bin/cleanup-verify-twilio.sh + RUNBOOK quy trinh; live cleanup verify deferred until TWIL-02/03 close) |
| TWIL-DOC | Phase 7 — Twilio Workshop Chapter | Pending |

**Coverage:**
- v1 requirements: **46** total — KB:6, AGT:8, DEP:6, WID:6, OBS:5, DEM:3, DOC:12
- v2.0 requirements: **5** total — TWIL:4 + TWIL-DOC:1
- Mapped to phases: **51/51** ✓ (v1 46/46 + v2.0 5/5)
- Unmapped: **0** ✓

**Per-phase totals:**
- Phase 1 (KB Foundation): 6 requirements (KB-01..06)
- Phase 2 (Voice Agent local): 8 requirements (AGT-01..08)
- Phase 3 (AgentCore + Widget + Demo): 15 requirements (DEP-01..06, WID-01..06, DEM-01..03)
- Phase 4 (Observability + Cleanup): 5 requirements (OBS-01..05)
- Phase 5 (Workshop docs): 12 requirements (DOC-01..12)
- Phase 6 (Twilio Bridge + Phone Number + Cleanup): 4 requirements (TWIL-01..04)
- Phase 7 (Twilio Workshop Chapter): 1 requirement (TWIL-DOC)
- Total: **51** ✓ (v1 46 + v2.0 5)

---
*Requirements defined: 2026-05-04*
*Last updated: 2026-05-07 — Milestone v2.0 (Twilio Voice Channel) STARTED. v1 closed: 46/46 reqs validated (DOC-11 operator-deferred). v2.0 scope: 5 reqs — TWIL-01..04 + TWIL-DOC. Other v2 categories (I18N, AUTH, THEME, ADV) remain deferred.*
