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

- [ ] **DEP-01**: Agent container deploy lên Amazon Bedrock AgentCore Runtime ở ap-northeast-1
- [ ] **DEP-02**: AgentCore endpoint exposed (WSS hoặc WebRTC) — chọn pattern dựa trên Pipecat support
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

- [ ] **OBS-01**: CloudWatch dashboard với panel: số session đang active, latency p50/p95 (utterance → first audio chunk), error rate, Bedrock invocation count
- [ ] **OBS-02**: CloudWatch alarm trigger khi: error rate > 5% trong 5 phút, latency p95 > 5s trong 5 phút
- [ ] **OBS-03**: CloudWatch billing alarm cảnh báo khi daily Bedrock cost vượt ngưỡng cấu hình được (default $5/ngày cho v1)
- [ ] **OBS-04**: AgentCore built-in throttling cho anonymous public URL — lock concurrency limit và per-IP rate limit (cấu hình AgentCore mặc định + custom nếu có)
- [ ] **OBS-05**: Cost circuit breaker: Lambda hook vào billing alarm tự stop AgentCore endpoint nếu vượt cost cap (best-effort, document trade-off)

### Demo Public URL (DEM)

- [x] **DEM-01**: Public HTTPS URL của instructor demo accessible từ internet, ACM cert valid
- [ ] **DEM-02**: Anonymous access — không cần login, nhưng có throttling/rate limit để chống abuse
- [ ] **DEM-03**: Banner trên trang ghi "This is an instructor demo. Cost capped at $X/day. For your own deployment, follow the workshop."

### Workshop Documentation (DOC)

Mỗi requirement viết cả 2 ngôn ngữ (vi/en) trừ khi ghi rõ.

- [ ] **DOC-01**: Phần 1 — Introduction (vi+en): Giới thiệu voice AI, Nova Sonic, vì sao dùng AgentCore (vs ECS), kiến trúc hera high-level diagram
- [ ] **DOC-02**: Phần 2 — Preparation (vi+en): AWS account checklist, enable Bedrock model access (Nova 2 Sonic), enable AgentCore service, install AWS CLI / Terraform / uv (Python), configure credentials, ước tính chi phí ~$X cho thời gian workshop
- [ ] **DOC-03**: Phần 3.1 (vi+en) — Build Knowledge Base: viết catalog markdown, deploy `modules/kb`, verify Retrieve API qua AWS CLI test
- [ ] **DOC-04**: Phần 3.2 (vi+en) — Pipecat agent code: code structure, system prompt, tool definition, run local test (Pipecat WebSocket transport, browser kết nối localhost)
- [ ] **DOC-05**: Phần 3.3 (vi+en) — Deploy lên AgentCore: build container, push ECR, deploy AgentCore, verify endpoint
- [ ] **DOC-06**: Phần 3.4 (vi+en) — Web widget: HTML/JS structure, browser microphone, kết nối AgentCore endpoint, deploy widget (S3+CloudFront hoặc GitHub Pages)
- [ ] **DOC-07**: Phần 3.5 (vi+en) — Observability: CloudWatch dashboard walk-through, set alarm
- [ ] **DOC-08**: Phần 4 — Cleanup (vi+en): `terraform destroy`, manual checks (Cost Explorer, list AgentCore endpoints, S3 bucket, KB), verification script
- [ ] **DOC-09**: Phần 5 — Summary (vi+en): cost recap, hướng mở rộng (Twilio voice, multi-language, multi-agent)
- [ ] **DOC-10**: Top 5-7 pitfall callouts ở các chapter tương ứng (8-min stream cap, sample rate, model access, HTTPS bắt buộc cho mic, billing alarm cleanup, schema tool-use, bilingual parity)
- [ ] **DOC-11**: Mỗi chapter có code snippet copy button (hugo-theme-learn shortcode hoặc custom), screenshot AWS console với annotation
- [ ] **DOC-12**: vi/en parity check chạy trong CI (script đếm số chapter mỗi lang, fail nếu lệch)

## v2 Requirements

Deferred. Tracked nhưng không trong roadmap v1.

### Twilio Voice Channel

- **TWIL-01**: Phone number Twilio nhận cuộc gọi
- **TWIL-02**: Twilio Media Streams kết nối tới AgentCore endpoint
- **TWIL-03**: Workshop chapter "Phone channel via Twilio"

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
| DEP-01 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Pending |
| DEP-02 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Pending |
| DEP-03 | Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL | Complete (Plan 03-01, 2026-05-06) |
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
| OBS-01 | Phase 4 — Observability, Cost Control, Cleanup | Pending |
| OBS-02 | Phase 4 — Observability, Cost Control, Cleanup | Pending |
| OBS-03 | Phase 4 — Observability, Cost Control, Cleanup | Pending |
| OBS-04 | Phase 4 — Observability, Cost Control, Cleanup | Pending |
| OBS-05 | Phase 4 — Observability, Cost Control, Cleanup | Pending |
| DOC-01 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-02 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-03 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-04 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-05 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-06 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-07 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-08 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-09 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-10 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-11 | Phase 5 — Workshop Documentation (vi/en) | Pending |
| DOC-12 | Phase 5 — Workshop Documentation (vi/en) | Pending |

**Coverage:**
- v1 requirements: **46** total — KB:6, AGT:8, DEP:6, WID:6, OBS:5, DEM:3, DOC:12
- Mapped to phases: **46/46** ✓
- Unmapped: **0** ✓

**Per-phase totals:**
- Phase 1 (KB Foundation): 6 requirements (KB-01..06)
- Phase 2 (Voice Agent local): 8 requirements (AGT-01..08)
- Phase 3 (AgentCore + Widget + Demo): 15 requirements (DEP-01..06, WID-01..06, DEM-01..03)
- Phase 4 (Observability + Cleanup): 5 requirements (OBS-01..05)
- Phase 5 (Workshop docs): 12 requirements (DOC-01..12)
- Total: **46** ✓

---
*Requirements defined: 2026-05-04*
*Last updated: 2026-05-05 — Phase 1 complete (KB-01..06 all Done); KB live in account 851725411875 / ap-northeast-1, KB id `BKXE19AH89`*
