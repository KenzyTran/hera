# Hera — AWS Voice Agent Workshop & Demo System

## What This Is

Hera là một workshop FCJ (First Cloud Journey) song ngữ vi/en hướng dẫn người học tự xây dựng một voice AI chatbot trên hạ tầng AWS, đi kèm với một hệ thống demo Apple Store customer support hoạt động thật. Workshop bao gồm hai sản phẩm liên kết: (1) một Hugo workshop site (hugo-theme-learn) chứa tài liệu từng bước, và (2) source code + Terraform IaC để học viên deploy được voice chatbot vào AWS account của chính mình.

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
- [ ] Voice loop end-to-end: browser microphone → WebSocket → Pipecat → Nova 2 Sonic → audio response phát lại trong browser
- [ ] Bedrock Knowledge Base dùng S3 Vectors làm vector store, chứa Apple product catalog + stock list (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4)
- [ ] Sonic gọi tool lookup vào Knowledge Base để trả lời câu hỏi sản phẩm (giống usecase trong raw_content.txt)
- [ ] Pipecat orchestrator container hóa, deploy trên ECS Fargate (ap-northeast-1 prod, us-east-1 dev)
- [ ] Web widget UI: trang HTML/JS tối giản với nút record, kết nối WebSocket tới Pipecat backend
- [ ] Terraform modules deploy được vào real AWS account: VPC, ECS, ALB/API Gateway, IAM, Bedrock KB, S3 Vectors, CloudWatch
- [ ] CloudWatch dashboards + alarms cơ bản: số session, latency p50/p95, error rate
- [ ] Public HTTPS endpoint (custom domain optional cho v1)

**Workshop docs (Hugo, vi + en):**
- [ ] Phần 1 — Introduction: voice AI là gì, Nova Sonic vs ElevenLabs, kiến trúc hera
- [ ] Phần 2 — Preparation: AWS account setup, enable Bedrock Nova 2 Sonic, install Terraform/AWS CLI
- [ ] Phần 3 — Hands-on: từng bước build (KB, Pipecat container, Terraform deploy, web widget) — mỗi bước có code snippet và screenshot
- [ ] Phần 4 — Cleanup: terraform destroy + verify không còn resource tốn tiền
- [ ] Phần 5 — Summary: cost breakdown, mở rộng hướng nào tiếp (Twilio, multi-language, RAG sâu hơn)

### Out of Scope (v1)

- **Twilio Voice integration** — deferred sang v2 (phone channel). v1 chỉ web widget. Lý do: scope kiểm soát, web widget đủ chứng minh end-to-end loop.
- **Mobile app (iOS/Android)** — không cần thiết cho workshop scope; web widget cover được demo
- **Multi-tenant auth/billing** — workshop là demo cá nhân, không phải SaaS
- **Tiếng Việt cho chatbot speech** — Nova Sonic mạnh nhất tiếng Anh; chatbot speech-only English. Workshop docs vẫn song ngữ vi/en
- **Custom voice cloning** — không cần thiết, dùng voice mặc định của Sonic
- **Production-grade auth (Cognito/SSO)** — v1 dùng API key đơn giản hoặc rate limit ở edge; SSO là việc của project sản xuất thật, không phải workshop
- **OpenSearch Serverless cho Knowledge Base** — đắt cho dataset nhỏ; dùng S3 Vectors thay thế
- **CDK** — user chọn Terraform; CDK không được dùng làm IaC chính
- **Gemini hoặc cross-cloud model** — locked vào AWS-native (Nova 2 Sonic)
- **N8n** — workshop trong raw_content.txt dùng n8n, hera thay bằng Pipecat + Bedrock native (đúng yêu cầu pure-AWS)

## Context

**Origin material:** `raw_content.txt` (~1680 dòng tiếng Việt) là transcript của một buổi hướng dẫn build voice chatbot dùng ElevenLabs + n8n + Google Gemini. Người dùng muốn re-implement cùng concept nhưng với stack AWS-native. raw_content được dùng làm tham chiếu use case (Apple Store support, knowledge base products, workflow agent routing) chứ không phải re-publish nguyên văn.

**Reference architecture:** [AWS blog — Building intelligent AI voice agents with Pipecat and Amazon Bedrock](https://aws.amazon.com/blogs/machine-learning/building-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock-part-1/) là blueprint chính cho hera.

**Existing code state:** Repo bắt đầu với Hugo workshop template chuẩn FCJ — `config.toml`, `layouts/`, `themes/` (git submodule pointing to hugo-theme-learn), `content/{vi,en}/` scaffold rỗng, `i18n/` translation strings, `.github/workflows/` cho GitHub Pages deploy, custom AWS Cloud Clubs branding trong `layouts/partials/`. Nhiệm vụ là điền nội dung workshop vào và thêm source code + IaC cho hệ thống demo song song.

**Audience:** Sinh viên / member AWS Cloud Clubs muốn học voice AI trên AWS, đã quen AWS basic (account, IAM, console) nhưng có thể chưa biết Bedrock/Pipecat/Terraform.

**Verified facts:**
- Nova 2 Sonic available trong: us-east-1, us-west-2, ap-northeast-1 (Tokyo), eu-north-1 (Stockholm) per [AWS docs — Model support by region](https://docs.aws.amazon.com/bedrock/latest/userguide/models-regions.html)
- Nova Sonic v1 đã EOL 2026 — dùng Nova 2 Sonic
- Bedrock Knowledge Base hỗ trợ S3 Vectors làm vector store backend
- Pipecat có sẵn integration cho Nova Sonic bidirectional và Twilio Media Streams

## Constraints

- **Tech stack**: AWS-native — yêu cầu rõ ràng từ user "hạ tầng phải được xây dựng trên AWS"
- **Voice model**: Amazon Nova 2 Sonic (Bedrock S2S) — locked
- **Vector store**: S3 Vectors — locked (cost-driven cho workshop scale)
- **Orchestrator**: Pipecat (Python framework, open-source) — phù hợp với Sonic bidirectional streaming và scale-out qua container
- **Compute**: ECS Fargate — Pipecat cần persistent process per session, Lambda không phù hợp
- **IaC**: Terraform — user preference; modules phải tự đứng được trong real AWS account
- **Region**: ap-northeast-1 production (latency tốt nhất từ VN có Sonic), us-east-1 dev/test
- **Workshop format**: FCJ-compatible — hugo-theme-learn, vi/en bilingual, content/{vi,en}/ structure đã định sẵn
- **Channel v1**: chỉ Web widget; Twilio defer sang milestone sau
- **Ngôn ngữ chatbot**: chỉ tiếng Anh
- **Ngôn ngữ workshop**: song ngữ vi/en
- **Account requirements**: học viên cần AWS account với Bedrock Nova 2 Sonic enabled (workshop docs phải hướng dẫn enable model access)
- **Compliance**: workshop scope cá nhân/giáo dục, không xử lý PII thật của user thật

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Nova 2 Sonic làm voice model | Bedrock-native S2S, low latency, tool-use cho KB lookup, đúng yêu cầu pure-AWS | — Pending |
| Pipecat làm orchestrator | Open-source framework có sẵn integration với Nova Sonic + Twilio; matches AWS reference blog | — Pending |
| ECS Fargate cho compute | Pipecat session là long-running WebSocket process — Lambda không fit, Fargate đơn giản hơn EKS cho workshop | — Pending |
| S3 Vectors thay OpenSearch Serverless | Cost: OSS có min ~$200-400/tháng; S3 Vectors tính theo volume thực, fit small catalog | — Pending |
| Terraform thay CDK/SAM | User preference; cộng đồng AWS lớn, declarative, dễ teach trong workshop | — Pending |
| ap-northeast-1 (Tokyo) cho prod | Region có Sonic + latency tốt nhất từ VN; ap-southeast-1 (Singapore) không có Sonic | — Pending |
| Web widget trước, Twilio sau | v1 cần chứng minh voice loop; Twilio thêm complexity (phone number, billing) phù hợp v2 | — Pending |
| Giữ Hugo workshop template existing | User xác nhận "It's the starting point"; baseline tốt cho FCJ format | ✓ |
| Chatbot tiếng Anh, docs song ngữ | Sonic mạnh nhất ở en; docs vi/en để Cloud Clubs VN tiếp cận được | — Pending |

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
*Last updated: 2026-05-04 after initialization*
