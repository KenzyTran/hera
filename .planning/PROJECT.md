# Hera — AWS Voice Agent Workshop & Demo System

## What This Is

Hera là một workshop FCJ (First Cloud Journey) song ngữ vi/en hướng dẫn người học tự xây dựng một voice AI chatbot trên hạ tầng AWS, đi kèm với một hệ thống demo Apple Store customer support hoạt động thật. Workshop bao gồm hai sản phẩm liên kết: (1) một Hugo workshop site (hugo-theme-learn) chứa tài liệu từng bước, và (2) source code Pipecat + IaC để học viên deploy lên **Amazon Bedrock AgentCore Runtime** trong AWS account của chính mình. Một URL public được instructor host làm demo phụ trợ (không production-grade).

## Core Value

**Một học viên Cloud Clubs đi qua workshop phải tự deploy thành công được voice chatbot trên AWS account của mình và nói chuyện được với nó qua trình duyệt.** Mọi thứ khác có thể thiếu, nhưng đường đi end-to-end này phải đi đến nơi.

## Requirements

### Validated

<!-- Đã có sẵn từ Hugo template baseline. -->

- ✓ Hugo multilingual scaffold (vi/en) — existing
- ✓ hugo-theme-learn integration qua git submodule — existing
- ✓ GitHub Actions workflow deploy Hugo site lên GitHub Pages — existing
- ✓ Custom AWS Cloud Clubs branding (logo, layouts/partials) — existing

### Active

<!-- Phạm vi v1, tất cả là hypothesis cho đến khi ship. -->

**Hệ thống voice chatbot:**
- [ ] Voice loop end-to-end: browser microphone → AgentCore endpoint (WebSocket hoặc WebRTC) → Pipecat agent code → Nova 2 Sonic (Bedrock bidirectional) → audio response phát lại trong browser
- [ ] Bedrock Knowledge Base dùng S3 Vectors + Titan v2 embeddings, chứa Apple product catalog + stock list (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4)
- [ ] Sonic gọi tool `lookup_product()` vào Knowledge Base Retrieve API để trả lời câu hỏi sản phẩm
- [ ] Pipecat 1.1.0 agent code (Python ≥3.11) đóng gói container và deploy vào **Bedrock AgentCore Runtime** ở ap-northeast-1
- [ ] AgentCore Runtime chịu trách nhiệm session/connection/scaling/observability — KHÔNG tự quản ECS, ALB, VPC custom networking
- [ ] Web widget UI: trang HTML/JS tối giản với nút record, AudioWorklet 16kHz PCM Int16, kết nối tới AgentCore endpoint qua WSS (hoặc WebRTC nếu region hỗ trợ)
- [ ] IaC modules deploy được vào real AWS account: Bedrock KB (`s3_vectors_storage_configuration`), S3 Vectors bucket+index, AgentCore Runtime resource, IAM least-privilege roles, CloudWatch dashboards
- [ ] Ưu tiên Terraform `~> 6.27`; nếu Terraform chưa hỗ trợ AgentCore resource, fallback hybrid (Terraform cho KB/IAM/S3 + AWS CDK hoặc CLI cho AgentCore deploy)
- [ ] CloudWatch dashboards + alarms: số session, latency p50/p95, error rate, Bedrock cost
- [ ] URL public của instructor demo: anonymous access + AgentCore built-in throttling + CloudWatch billing alarm cắt session khi vượt ngưỡng
- [ ] Cleanup chapter có verification scripts: destroy stack + check Cost Explorer + verify không còn AgentCore endpoint / KB / S3 Vectors index chạy

**Workshop docs (Hugo, vi + en):**
- [ ] Phần 1 — Introduction: voice AI là gì, Nova Sonic vs ElevenLabs, vì sao dùng Bedrock AgentCore Runtime, kiến trúc hera
- [ ] Phần 2 — Preparation: AWS account setup, enable Bedrock Nova 2 Sonic + AgentCore model access, install Terraform + AWS CLI + uv (Python)
- [ ] Phần 3 — Hands-on: từng bước build (KB + S3 Vectors → Pipecat agent code local test → AgentCore deploy → web widget) — mỗi bước có code snippet và screenshot
- [ ] Phần 4 — Cleanup: tear down + verify Cost Explorer
- [ ] Phần 5 — Summary: cost breakdown, mở rộng hướng nào tiếp (Twilio, multi-language, multi-agent, RAG sâu hơn)

### Out of Scope (v1)

- **Twilio Voice integration** — deferred sang v2 (phone channel). v1 chỉ web widget. Lý do: scope kiểm soát, web widget đủ chứng minh end-to-end loop
- **Mobile app (iOS/Android)** — không cần thiết cho workshop scope; web widget cover được demo
- **Multi-tenant auth/billing** — workshop là demo cá nhân, không phải SaaS
- **Tiếng Việt cho chatbot speech** — Nova Sonic mạnh nhất tiếng Anh; chatbot speech-only English. Workshop docs vẫn song ngữ vi/en
- **Custom voice cloning** — không cần thiết, dùng voice mặc định của Sonic
- **Production-grade auth (Cognito/SSO)** — v1 dùng anonymous + AgentCore throttling + cost cap; SSO là việc của project sản xuất thật
- **OpenSearch Serverless cho Knowledge Base** — đắt cho dataset nhỏ; dùng S3 Vectors thay thế
- **Self-managed ECS Fargate / ALB / VPC custom networking** — thay bằng AgentCore Runtime managed (đơn giản hơn, ít infra để debug, phù hợp scope workshop). Nếu sau này muốn full control sẽ revisit ở v2
- **PrivateLink / VPC interface endpoints** — không cần với AgentCore managed; egress quản lý bởi service
- **Phase 0 spike PrivateLink** — bỏ vì không dùng PrivateLink
- **NAT Gateway** — bỏ vì không tự quản VPC
- **Hugo theme migration sang relearn** — `hugo-theme-learn` đã deprecated nhưng vẫn hoạt động; migrate lên `hugo-theme-relearn` defer sang v2
- **Gemini hoặc cross-cloud model** — locked vào AWS-native (Nova 2 Sonic)
- **N8n** — workshop trong raw_content.txt dùng n8n, hera thay bằng Pipecat + AgentCore native (đúng yêu cầu pure-AWS)

## Context

**Origin material:** `raw_content.txt` (~1680 dòng tiếng Việt) là transcript của một buổi hướng dẫn build voice chatbot dùng ElevenLabs + n8n + Google Gemini. Người dùng muốn re-implement cùng concept nhưng với stack AWS-native. raw_content được dùng làm tham chiếu use case (Apple Store support, knowledge base products, workflow agent routing) chứ không phải re-publish nguyên văn.

**Reference architectures:**
- [Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/) — blueprint chính cho hera
- [aws-samples/sample-nova-sonic-websocket-agentcore](https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore) — reference repo (bidirectional streaming + WebSocket + auth + tool use)
- [Building intelligent AI voice agents with Pipecat and Amazon Bedrock — Part 1+2](https://aws.amazon.com/blogs/machine-learning/building-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock-part-1/) — bài blog gốc user gửi (kiến trúc ECS-based, dùng làm tham khảo lý thuyết)

**Existing code state:** Repo bắt đầu với Hugo workshop template chuẩn FCJ — `config.toml`, `layouts/`, `themes/` (git submodule pointing to hugo-theme-learn), `content/{vi,en}/` scaffold rỗng, `i18n/` translation strings, `.github/workflows/` cho GitHub Pages deploy, custom AWS Cloud Clubs branding trong `layouts/partials/`. Nhiệm vụ là điền nội dung workshop vào và thêm source code + IaC cho hệ thống demo song song.

**Audience:** Sinh viên / member AWS Cloud Clubs muốn học voice AI trên AWS, đã quen AWS basic (account, IAM, console) nhưng có thể chưa biết Bedrock/Pipecat/Terraform/AgentCore.

**Verified facts:**
- Nova 2 Sonic available trong: us-east-1, us-west-2, ap-northeast-1, eu-north-1 per [AWS Bedrock model regions docs](https://docs.aws.amazon.com/bedrock/latest/userguide/models-regions.html)
- Nova Sonic v1 đã EOL 2026 — dùng Nova 2 Sonic
- AgentCore Runtime có ở 9 region (incl. ap-northeast-1, us-east-1, us-west-2) — overlap với Sonic regions OK
- AgentCore WebRTC support thêm tháng 3/2026 — latency thấp hơn WebSocket cho browser, ưu tiên dùng nếu Pipecat hỗ trợ
- Bedrock Knowledge Base hỗ trợ S3 Vectors làm vector store backend
- Pipecat có `AWSNovaSonicLLMService` first-party + WebSocket transport sẵn
- AgentCore + Pipecat là **first-party deployment pattern** từ AWS (có aws-samples repo riêng)

## Constraints

- **Tech stack**: AWS-native — yêu cầu rõ ràng từ user "hạ tầng phải được xây dựng trên AWS"
- **Voice model**: Amazon Nova 2 Sonic (Bedrock S2S) — locked
- **Vector store**: S3 Vectors — locked (cost-driven cho workshop scale)
- **Orchestrator framework**: Pipecat (Python ≥3.11) — first-party Sonic integration, có sample chính thức cho AgentCore
- **Compute**: Amazon Bedrock AgentCore Runtime — managed, ít infra để debug, simpler workshop
- **IaC**: Terraform `~> 6.27` ưu tiên; fallback hybrid với CDK hoặc CLI nếu Terraform AgentCore resource chưa đủ tính năng (verify trong research/plan phase)
- **Region**: ap-northeast-1 production (latency tốt nhất từ VN, có cả Sonic + AgentCore), us-east-1 dev/test
- **Workshop format**: FCJ-compatible — hugo-theme-learn, vi/en bilingual, content/{vi,en}/ structure đã định sẵn
- **Channel v1**: chỉ Web widget; Twilio defer sang milestone sau
- **Ngôn ngữ chatbot**: chỉ tiếng Anh
- **Ngôn ngữ workshop**: song ngữ vi/en
- **Account requirements**: học viên cần AWS account với Bedrock Nova 2 Sonic + AgentCore Runtime enabled (workshop docs phải hướng dẫn enable model access và service)
- **Compliance**: workshop scope cá nhân/giáo dục, không xử lý PII thật của user thật

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Nova 2 Sonic làm voice model | Bedrock-native S2S, low latency, tool-use cho KB lookup, đúng yêu cầu pure-AWS | — Pending |
| Pipecat làm orchestrator | Open-source framework có first-party AWS Nova Sonic service; AWS có sample AgentCore + Pipecat repo | — Pending |
| **Bedrock AgentCore Runtime cho compute** | Managed runtime, ít Terraform/infra, deploy nhanh, là first-party pattern AWS recommend cho Pipecat + Sonic. Đổi từ ECS Fargate sau khi user yêu cầu xem xét AgentCore | — Pending |
| S3 Vectors thay OpenSearch Serverless | Cost: OSS min ~$200-400/tháng; S3 Vectors tính theo volume thực, fit small catalog | — Pending |
| Terraform ưu tiên, CDK fallback nếu cần | User preference Terraform; nhưng AgentCore resource trong Terraform có thể chưa hoàn chỉnh — fallback hybrid | — Pending |
| ap-northeast-1 (Tokyo) cho prod | Region có cả Sonic + AgentCore + latency tốt từ VN; ap-southeast-1 không có Sonic | — Pending |
| Web widget trước, Twilio sau | v1 cần chứng minh voice loop; Twilio thêm complexity (phone number, billing) phù hợp v2 | — Pending |
| Giữ Hugo workshop template existing | User xác nhận "It's the starting point"; baseline tốt cho FCJ format | ✓ |
| Giữ `hugo-theme-learn` cho v1 (không migrate) | Theme đã deprecated nhưng đang hoạt động; migration thêm scope không cần thiết. Defer v2 | — Pending |
| Chatbot tiếng Anh, docs song ngữ | Sonic mạnh nhất ở en; docs vi/en để Cloud Clubs VN tiếp cận được | — Pending |
| Public URL anonymous + AgentCore throttling + cost cap | Không SSO/Cognito (workshop scope); rely vào AgentCore built-in throttle + CloudWatch billing alarm | — Pending |
| Bỏ PrivateLink + NAT + VPC custom | Không tự quản network với AgentCore managed; đơn giản hóa workshop, giảm cost | — Pending |
| Bỏ Phase 0 spike | PrivateLink uncertainty không còn vì không dùng | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-04 after initialization (revised: AgentCore over ECS, no NAT/PrivateLink, instructor demo public URL)*
