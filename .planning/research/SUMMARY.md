# Tổng hợp nghiên cứu — Hera AWS Voice Agent Workshop

**Dự án:** Hera — AWS Voice Agent Workshop & Demo System
**Domain:** Voice AI agent AWS-native (speech-to-speech) + FCJ workshop song ngữ vi/en
**Ngày nghiên cứu:** 2026-05-04
**Tổng hợp bởi:** Synthesizer agent (sau khi PROJECT.md xác nhận pivot sang AgentCore)
**Độ tin cậy tổng:** MEDIUM-HIGH — core voice stack HIGH; AgentCore-specific details MEDIUM (xem phần câu hỏi mở)

---

## Tóm tắt điều hành

Hera là một hệ thống kép: (1) một voice chatbot AWS-native thật sự deploy được, dùng Apple Store làm use case demo, và (2) một FCJ workshop song ngữ vi/en hướng dẫn Cloud Clubs members tự deploy hệ thống đó trong AWS account của họ. Giá trị cốt lõi là con đường end-to-end — học viên tự deploy và nói chuyện được với bot qua trình duyệt — chứ không phải tính năng phong phú.

Stack được xác nhận dùng mô hình speech-to-speech Amazon Nova 2 Sonic (`amazon.nova-2-sonic-v1:0`) thông qua Bedrock bidirectional streaming, orchestrated bởi Pipecat 1.1.0 (Python 3.12). **Điểm quan trọng nhất của đợt nghiên cứu này là pivot compute**: thay vì tự quản ECS Fargate + ALB + VPC custom, hera sẽ deploy Pipecat agent vào **Amazon Bedrock AgentCore Runtime** — AWS managed runtime first-party cho Pipecat + Sonic. Điều này loại bỏ toàn bộ lớp networking (NAT, PrivateLink, security groups, ALB timeout config) khỏi phạm vi workshop, giảm đáng kể số tài nguyên học viên phải debug. AgentCore cung cấp endpoint (WSS hoặc WebRTC), session management, scaling, và CloudWatch observability tích hợp sẵn.

Rủi ro chính còn lại: (a) mức độ hỗ trợ AgentCore trong Terraform `~> 6.27` chưa xác nhận — có thể cần fallback hybrid Terraform + CDK/CLI; (b) pricing model của AgentCore chưa có tài liệu công khai rõ ràng; (c) AgentCore WebRTC (thêm tháng 3/2026) có thể giảm latency hơn nếu Pipecat transport hỗ trợ. Các rủi ro này phải được validate trong giai đoạn lập kế hoạch phase, không phải sau khi đã commit kiến trúc.

---

## Thẻ tham chiếu nhanh — Stack tổng quan

| Thành phần | Lựa chọn | Version / ID |
|-----------|----------|--------------|
| Voice model | Amazon Nova 2 Sonic | `amazon.nova-2-sonic-v1:0` |
| Orchestrator | Pipecat | `pipecat-ai==1.1.0`, extras `[aws-nova-sonic,silero,websocket]` |
| Python runtime | Python | 3.12 (>=3.11 required) |
| Package manager | uv | >=0.4 |
| Compute | **Bedrock AgentCore Runtime** | managed — ap-northeast-1 |
| Transport browser->agent | WSS hoặc WebRTC | AgentCore endpoint; WebRTC ưu tiên nếu Pipecat hỗ trợ |
| Audio in browser | 16 kHz mono PCM Int16 | AudioWorklet + getUserMedia |
| Audio out browser | 24 kHz mono PCM Int16 | AudioContext playback |
| Vector store | Amazon S3 Vectors | GA, ap-northeast-1 |
| Knowledge Base | Amazon Bedrock Knowledge Base | S3 Vectors backend |
| Embedding model | Titan Text Embeddings v2 | `amazon.titan-embed-text-v2:0`, 1024 dim float32 |
| IaC | Terraform | CLI >=1.9, `hashicorp/aws ~> 6.27` |
| IaC fallback | Terraform + AWS CDK hoặc CLI | Nếu AgentCore resource chưa đủ trong TF provider |
| Workshop theme | hugo-theme-learn | git submodule (giữ v1, không migrate sang relearn) |
| Hugo | Hugo extended | >=0.140 |
| Region prod | ap-northeast-1 Tokyo | Sonic + AgentCore + latency tốt từ VN |
| Region dev | us-east-1 | |
| Deployment infra | GitHub Pages | Existing Actions workflow |

**Reference architectures:**
- AWS blog: "Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1"
- `aws-samples/sample-nova-sonic-websocket-agentcore` — reference repo chính
- AWS blog: "Building intelligent AI voice agents with Pipecat and Amazon Bedrock" (Part 1+2) — lý thuyết ECS-based, dùng tham chiếu kỹ thuật

---

## Những gì đã thay đổi so với nghiên cứu ban đầu

Bốn researcher agents viết STACK.md / FEATURES.md / ARCHITECTURE.md / PITFALLS.md với giả định **ECS Fargate + ALB + VPC custom networking**. Sau đó PROJECT.md được viết lại với quyết định pivot sang **Amazon Bedrock AgentCore Runtime**. Bảng dưới liệt kê tác động:

| Nội dung trong file nghiên cứu | Trạng thái sau pivot | Ghi chú |
|-------------------------------|---------------------|---------|
| ECS Fargate (task def, autoscaling, ECR) | **THAY THẾ** bởi AgentCore Runtime | AgentCore quản lý compute |
| ALB (idle_timeout, stickiness, health check) | **LOẠI BỎ** | AgentCore cung cấp endpoint managed |
| VPC, subnets, NAT Gateway, Internet Gateway | **LOẠI BỎ** | AgentCore managed networking |
| VPC Interface Endpoints / PrivateLink | **LOẠI BỎ** | Không tự quản VPC |
| Security groups cho ECS tasks | **LOẠI BỎ** | |
| Phase 0 spike PrivateLink over bidi streaming | **LOẠI BỎ** | Không dùng PrivateLink |
| Shared-task vs per-session task pattern ECS | **LOẠI BỎ** | AgentCore quản lý session isolation |
| Per-session cost Fargate vCPU/GB/hr | **THAY ĐỔI** | AgentCore pricing chưa rõ — xem câu hỏi mở |
| ALB pitfalls 60s idle và health check loop | **KHÔNG CÒN ÁP DỤNG** | Không có ALB |
| VPC egress pitfall | **KHÔNG CÒN ÁP DỤNG** | Không tự quản networking |
| Terraform modules network/ ecs/ alb/ | **THAY THẾ** bởi module AgentCore | TF resource AgentCore cần verify |
| ECS task IAM role cho InvokeModelWithBidirectionalStream | **CÒN NHƯNG ĐỔI CONTEXT** | AgentCore execution role, không phải ECS task role |
| Hugo theme migration sang relearn | **GIỮ NGUYÊN defer v2** | PROJECT.md: giữ hugo-theme-learn cho v1 |
| Auth Cognito / WAF custom rules | **LOẠI BỎ** | Anonymous + AgentCore throttling + billing alarm |
| Public URL production-grade | **KHÔNG ÁP DỤNG** | Instructor demo phụ trợ; core value là học viên tự deploy |

**Nội dung còn hoàn toàn hợp lệ (không đổi):** Pipecat 1.1.0, Nova 2 Sonic, audio formats (16kHz in/24kHz out), tool-use, S3 Vectors + Bedrock KB + Titan v2, browser web widget (getUserMedia + AudioWorklet), Hugo + hugo-theme-learn, cost shape (Sonic dominates), use case Apple Store (3 SKUs), tất cả pitfalls workshop UX, KB ingestion delay, audio sample rate, model access enable, bilingual drift, code snippet copy issues, IAM wildcards.

---

## Key Findings

### 1. Stack

**Bất biến (locked, verified):**
- **Nova 2 Sonic** là lựa chọn duy nhất hợp lệ: S2S AWS-native, tool-use native, `InvokeModelWithBidirectionalStream`, available ap-northeast-1. Nova Sonic v1 đã EOL — chỉ dùng v2.
- **Pipecat 1.1.0** có `AWSNovaSonicLLMService` first-party + `WebsocketServerTransport` sẵn. AWS có reference repo `aws-samples/sample-nova-sonic-websocket-agentcore` dùng đúng pattern này.
- **S3 Vectors + Titan v2 (1024 dim float32)** locked vì cost: pennies/month vs OpenSearch Serverless $200-400/month. Dimension là one-way door sau khi tạo index — destroy/recreate mới đổi được.
- **Terraform `~> 6.27`** cần thiết để có `s3_vectors_storage_configuration` trong `aws_bedrockagent_knowledge_base`. `aws_s3vectors_vector_bucket` và `aws_s3vectors_index` là native Terraform resources.

**Mới sau pivot (AgentCore):**
- Pipecat container deploy vào **Bedrock AgentCore Runtime** thay vì ECS. AWS có blog và sample repo `aws-samples/sample-nova-sonic-websocket-agentcore` cho pattern này.
- AgentCore WebRTC được thêm tháng 3/2026 — ưu tiên nếu Pipecat transport hỗ trợ; fallback WebSocket.
- Terraform resource cho AgentCore cần verify trong phase planning (xem câu hỏi mở).
- Module structure mới: `modules/knowledge_base`, `modules/agentcore`, `modules/iam`, `modules/observability`.

### 2. Features

**Phải có để voice loop hoạt động (P1):**
- Browser mic -> WSS/WebRTC -> Pipecat agent -> Nova Sonic -> audio playback (the loop)
- Record button 4-5 trạng thái: idle/connecting/listening/speaking/error
- Live transcript (user + agent text)
- Bedrock KB over S3 Vectors với 3 SKUs: Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4
- Tool `lookup_product(query)` gọi KB Retrieve API
- System prompt locking agent to Apple Store persona
- Server-side VAD + barge-in (native trong Nova Sonic, không cần Silero riêng)
- Mic permission denied error path
- HTTPS endpoint (AgentCore WSS managed — không cần tự tạo ACM/ALB)
- CloudWatch logs + 1 dashboard; graceful disconnect

**Phải có cho workshop docs (P1):**
- 5 chapters vi+en: Introduction / Preparation / Hands-on / Cleanup / Summary
- Architecture diagram AgentCore-based (không phải ECS)
- Prerequisites: AWS account, enable Nova 2 Sonic + AgentCore access
- Hands-on: KB + S3 Vectors -> Pipecat local test -> AgentCore deploy -> web widget
- Cleanup: terraform destroy + verify AgentCore endpoint / KB / S3 Vectors / Cost Explorer
- Cost estimate table (AgentCore pricing thay cho Fargate — pending câu hỏi mở)

**Defer sang v1.x sau khi core loop proven:**
- Source citations (RAG attribution chip), per-session cost guardrail, conversation reset, latency telemetry debug mode
- Troubleshooting/FAQ appendix, per-step verify callouts, success screencast

**Anti-features không build v1:**
- Twilio, mobile app, Cognito/SSO, custom voice cloning, OpenSearch Serverless, Vietnamese chatbot speech, multi-agent orchestration, DynamoDB transcript history, Bedrock Guardrails

### 3. Architecture (sau pivot AgentCore)

Luồng dữ liệu:

```
Browser (getUserMedia -> AudioWorklet -> PCM 16kHz Int16)
    |
    | WSS (hoặc WebRTC nếu Pipecat hỗ trợ)
    v
AgentCore Runtime Endpoint (managed AWS)
    |
    v
Pipecat agent container (trong AgentCore)
    |-> InvokeModelWithBidirectionalStream -> Nova 2 Sonic (Bedrock)
    |       |-> tool call lookup_product()
    |               |-> bedrock-agent-runtime:Retrieve -> Bedrock KB
    |                       |-> S3 Vectors index (Titan v2 embeddings)
    |-> PCM 24kHz -> WSS response -> Browser AudioContext playback
```

**Thành phần cần build:** Pipecat agent code Python 3.12 + container image, AgentCore Runtime resource + execution IAM role, Bedrock KB + S3 Vectors + S3 source bucket (Terraform), browser web widget (HTML/JS, AudioWorklet, WebSocket client), CloudWatch dashboards.

**Không còn cần build:** ALB, target group, ACM cert, VPC, subnets, NAT, PrivateLink, ECS cluster/service/task definition, ECR repo.

**Còn giữ nguyên từ ARCHITECTURE.md:** Latency budgets (voice loop <1s, tool loop <500ms), session continuity (AWSNovaSonicLLMService auto-handle 8-min Sonic cap), KB tool pattern (`@llm.function` -> `numberOfResults=3`), stateless sessions (không DynamoDB v1), static widget hosted riêng (GitHub Pages là option rõ ràng nhất), pattern no-static-creds (IAM role only).

### 4. Top 7 pitfalls (sau reconciliation voi AgentCore pivot)

| # | Pitfall | Muc do | Cach phong |
|---|---------|--------|------------|
| P1 | **Nova 2 Sonic 8-min session timeout** | P0 | `AWSNovaSonicLLMService` auto-reconnect la default; verify on; log `ModelTimeoutException` nhu known event |
| P2 | **Bedrock model access chua enable trong region** | P0 workshop blocker | Phan 2 PHAI co screenshot-step enable Nova 2 Sonic o ap-northeast-1 truoc khi bat ky code nao chay |
| P3 | **Audio sample rate mismatch** (browser 48kHz vs Sonic 16kHz in / 24kHz out) | P0 voice quality | Widget: `new AudioContext({ sampleRate: 16000 })`, downsample explicit; separate AudioContext 24kHz cho playback |
| P4 | **Tool-use schema mismatch** (Pipecat <-> Sonic JSON contract) | P1 | Flat parameters `{ query: string }`; test tool standalone truoc; log `ToolUseFrame`/`ToolResultFrame` |
| P5 | **KB sync delay** (doc indexed nhung chua queryable) | P1 workshop UX | Workshop step explicit: Wait 2-3 minutes after sync completes, voi verification command |
| P6 | **Bill bomb tu public endpoint** | P1 cost | AgentCore built-in throttling + CloudWatch billing alarm $5/day; cleanup chapter mandatory |
| P7 | **Cleanup khong du — learner bi tinh tien** | P0 workshop UX | Phan 4 la deliverable rieng: destroy + verify AgentCore endpoint / KB / S3 Vectors / log groups + Cost Explorer |

**Pitfalls khong con ap dung sau pivot:** PITFALLS.md #2 (ALB 60s idle timeout), #5 (ALB health check loop), #7 (VPC egress without NAT/endpoint).

**IAM context thay doi:** PITFALLS.md #6 ECS task IAM missing bidi action -> AgentCore execution role missing bidi action. Cung fix, khac context.

---

## De xuat thu tu build cho roadmap

### Phase 1 — Knowledge Base end-to-end
**Rationale:** KB la dependency cua Pipecat agent; ingestion co latency rieng nen tot hon discover som; test duoc hoan toan bang AWS CLI ma khong can compute.
**Deliverables:** S3 source bucket (Apple catalog markdown), S3 Vectors bucket + index, Bedrock KB, ingestion job, verify Retrieve tu CLI tra ve dung ket qua.
**Terraform:** modules/knowledge_base — S3 Vectors, KB, IAM KB service role.
**Pitfall can tranh:** S3 Vectors embedding dim lock-in (one-way door); KB sync delay (wait 2-3 min).

### Phase 2 — Pipecat agent code (local test, real Bedrock)
**Rationale:** Moi phut debug trong AgentCore runtime dat hon debug local. Get the container working end-to-end locally truoc.
**Deliverables:** Pipecat agent code voi AWSNovaSonicLLMService + lookup_product tool + Apple Store system prompt; local browser test qua real Bedrock + real KB.
**Stack:** pipecat-ai[aws-nova-sonic,silero,websocket], Python 3.12, uv.
**Pitfall can tranh:** Audio sample rate mismatch; tool-use schema mismatch; 8-min session cap.

### Phase 3 — AgentCore Runtime deploy
**Rationale:** Deploy container len AgentCore sau khi container da verified locally. Day la phan moi nhat voi nhieu unknowns nhat — can research spike.
**Deliverables:** AgentCore Runtime resource (Terraform hoac CDK/CLI hybrid); AgentCore execution IAM role; AgentCore WSS endpoint hoat dong; end-to-end voice loop tren real AWS.
**Terraform:** modules/agentcore, modules/iam; fallback hybrid Terraform + CDK/CLI neu TF provider chua du.
**Pitfall can tranh:** IAM execution role missing bidi action; AgentCore concurrency quota limit.
**Research flag (cao):** Terraform support level cho AgentCore; pricing; concurrency/quota; WebRTC vs WebSocket; exact deploy steps tu aws-samples/sample-nova-sonic-websocket-agentcore.

### Phase 4 — Web widget + public endpoint polish
**Rationale:** Tach browser issues (autoplay policy, AudioWorklet quirks) khoi backend issues; backend test duoc voi websocat truoc.
**Deliverables:** HTML/JS widget hoan chinh (AudioWorklet 16kHz, WebSocket client, playback 24kHz, 5 states, transcript, error paths); hosted GitHub Pages hoac S3+CF; HTTPS cho getUserMedia.
**Pitfall can tranh:** Audio sample rate; HTTPS requirement cho mic; browser autoplay policy; mixed content.

### Phase 5 — Observability, cost cap, cleanup verification
**Rationale:** Workshop phai day cach diagnose va confirm cleanup. Khong the ship ma thieu.
**Deliverables:** CloudWatch dashboards (session count, latency p50/p95, error rate, Bedrock cost); billing alarm $5/day; terraform destroy verified tren fresh account; cleanup chapter voi verification checklist.
**Pitfall can tranh:** Bill bomb; cleanup incomplete; CloudWatch logs retention khong set.

### Phase 6 — Workshop docs (Hugo content, vi + en)
**Rationale:** Chay song song tu Phase 2 tro di; content Hands-on trail real implementation mot phase.
**Deliverables:** 5 chapters vi + en; architecture diagram AgentCore-based; code snippets copy-clean; cost estimate table (sau khi co AgentCore pricing tu Phase 3); bilingual CI parity check.
**Pitfall can tranh:** Bilingual drift (CI parity check truoc khi content scale); code snippet copy issues; console UI drift; model access khong enable.

### Phase 7 — End-to-end smoke test tu fresh AWS account
**Rationale:** Moi workshop loi dau tien phat hien khi tester khac (khong phai tac gia) chay tu fresh account.
**Deliverables:** Fresh account walkthrough complete; cost verified; cleanup = $0 in Cost Explorer 24h after destroy; looks-done-but-isnt checklist passed.

### Ly do thu tu

- KB truoc vi la dependency cua moi thu va test duoc doc lap bang CLI
- Local Pipecat truoc AgentCore deploy vi feedback loop nhanh hon nhieu
- AgentCore deploy la Phase 3 vi co nhieu unknowns nhat — sau khi co working container
- Widget sau backend vi browser issues khong nen block backend validation
- Observability + cleanup truoc docs sign-off vi workshop khong the ship neu thieu
- Phase 0 PrivateLink spike da bi loai bo — AgentCore managed networking remove rui ro do

### Research flags

**Can /gsd-research-phase trong phase planning:**
- **Phase 3 (AgentCore deploy):** Terraform provider support level cho AgentCore resources; pricing model; exact Pipecat Pipeline -> AgentCore steps; concurrency/quota; WebRTC vs WebSocket decision.
- **Phase 5 (Observability):** AgentCore built-in CloudWatch traces — exact metric names, dimensions.

**Pattern well-documented, skip research-phase:**
- Phase 1 (KB), Phase 2 (Pipecat local), Phase 4 (Widget), Phase 6 (Hugo docs) — all have established patterns and official docs.

---

## Danh gia do tin cay

| Linh vuc | Do tin cay | Ghi chu |
|----------|-----------|---------|
| Nova 2 Sonic (model ID, regions, audio format, tool-use) | HIGH | AWS Bedrock model card + docs verified 2026-05-04 |
| Pipecat 1.1.0 (version, AWSNovaSonicLLMService) | HIGH | PyPI + Pipecat docs verified |
| S3 Vectors + Bedrock KB + Titan v2 | HIGH | AWS GA announcement + docs + Terraform registry verified |
| Terraform hashicorp/aws ~> 6.27 cho S3 Vectors + KB | MEDIUM-HIGH | GitHub PR/issue confirmed; resource pages exist |
| Browser widget pattern (AudioWorklet, WebSocket) | HIGH | Web standards + multiple production references |
| Hugo + hugo-theme-learn integration | HIGH | Existing scaffolded repo confirmed |
| **AgentCore Runtime — Terraform support** | LOW-MEDIUM | Chua verify; can spike trong phase planning |
| **AgentCore Runtime — pricing model** | LOW | Khong tim thay tai lieu cong khai ro rang |
| **AgentCore Runtime — Pipecat deploy exact steps** | MEDIUM | AWS blog + aws-samples repo ton tai nhung chua verify chi tiet |
| **AgentCore WebRTC — Pipecat transport support** | MEDIUM | AgentCore WebRTC confirmed March 2026; Pipecat support chua verify |
| **AgentCore concurrency/quota limits** | LOW | Region-specific, chua co tai lieu cong khai |
| Workshop pitfalls (Sonic 8min, audio format, model access, KB delay) | HIGH | AWS docs + Pipecat issues + production guides |
| Cost shape (Sonic dominates variable cost) | HIGH | Sonic pricing verified; AgentCore fixed cost = cau hoi mo |

**Do tin cay tong:** MEDIUM-HIGH cho core voice stack; MEDIUM cho AgentCore specifics.

---

## Cau hoi mo cho phase planning

Phai resolve truoc khi commit implementation details trong phase plan:

1. **Terraform AgentCore resource:** hashicorp/aws ~> 6.27 co native resource cho AgentCore Runtime chua? Gap cu the la gi — CDK construct, AWS CLI via null_resource, hay provider version khac?

2. **AgentCore pricing model:** Per-invocation? Per-session-minute? Free tier? Can so cu the cho cost estimate trong workshop Chapter 5.

3. **Pipecat Pipeline -> AgentCore exact deploy steps:** aws-samples/sample-nova-sonic-websocket-agentcore dung pattern gi — containerized Pipecat code, entry point cu the, environment variables, secrets injection?

4. **AgentCore concurrency / quota per account:** Default concurrent sessions la bao nhieu? Can request quota increase truoc demo day khong?

5. **AgentCore WebRTC + Pipecat transport:** pipecat-ai[aws-nova-sonic] co WebRTC transport compatible voi AgentCore WebRTC endpoint (March 2026) khong, hay van phai dung WebSocket?

6. **AgentCore Bedrock KB tool helper:** AgentCore co helper san cho KB Retrieve integration khong, hay van wire manually qua @llm.function() + bedrock-agent-runtime:Retrieve nhu pattern ECS?

7. **Static widget hosting:** Widget host o dau khi khong con serve tu Pipecat container qua ALB? GitHub Pages (da co Actions workflow) la option ro rang nhat — can verify CORS voi AgentCore WSS endpoint.

---

## Nguon tham khao

### Primary — HIGH confidence
- AWS blog: "Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1" — blueprint chinh cho AgentCore compute pattern
- aws-samples/sample-nova-sonic-websocket-agentcore — reference repo (WebSocket + AgentCore + tool use)
- AWS blog: "Building intelligent AI voice agents with Pipecat and Amazon Bedrock — Part 1+2" — Sonic technical details (ECS-based; ly thuyet)
- AWS Bedrock model card amazon.nova-2-sonic-v1:0 — model ID, regions, audio formats
- Pipecat docs AWSNovaSonicLLMService — service API, session continuation, tools
- AWS docs S3 Vectors + Bedrock KB integration — dimension lock-in, float32 requirement
- AWS docs Bedrock model access enablement — account-level gate (separate from IAM)
- Terraform registry: aws_s3vectors_vector_bucket, aws_s3vectors_index, aws_bedrockagent_knowledge_base

### Secondary — MEDIUM confidence
- AgentCore WebRTC announcement (March 2026) — tinh nang moi, it production reference
- Pipecat GitHub issues #2010 (tool-use regression), #1875 (latency) — canh bao edge cases fragile
- Nova Sonic pricing references — verify trong AWS Calculator truoc khi publish workshop cost table

### Context tu research files (ECS-era, dung cho ly thuyet)
- STACK.md — ECS Fargate/ALB config (khong apply truc tiep sau pivot; audio/KB ly thuyet huu ich)
- ARCHITECTURE.md — data flow diagrams, session model, latency budgets (valid cho voice loop concepts)
- FEATURES.md — full feature taxonomy, FCJ format conventions (fully valid, khong doi)
- PITFALLS.md — 25 pitfalls: #1, #3, #4, #8-#16, #17, #19-#25 van ap dung; #2, #5, #7 khong con ap dung sau pivot

---

*Nghien cuu hoan tat: 2026-05-04*
*Pivot sang AgentCore applied: 2026-05-04*
*San sang cho roadmap: co — voi note AgentCore open questions phai resolve trong Phase 3 planning*
