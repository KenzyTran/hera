# Hera — AWS Voice Agent Workshop & Demo System

## What This Is

Hera là một workshop FCJ (First Cloud Journey) song ngữ vi/en hướng dẫn người học tự xây dựng một voice AI chatbot trên hạ tầng AWS, đi kèm với một hệ thống demo Apple Store customer support hoạt động thật. Workshop bao gồm hai sản phẩm liên kết: (1) một Hugo workshop site (hugo-theme-learn) chứa tài liệu từng bước, và (2) source code Pipecat + IaC để học viên deploy lên **Amazon Bedrock AgentCore Runtime** trong AWS account của chính mình. Một URL public được instructor host làm demo phụ trợ (không production-grade).

## Core Value

**Một học viên Cloud Clubs đi qua workshop phải tự deploy thành công được voice chatbot trên AWS account của mình và nói chuyện được với nó qua trình duyệt.** Mọi thứ khác có thể thiếu, nhưng đường đi end-to-end này phải đi đến nơi.

## Current Milestone: v2.0 Twilio Voice Channel

**Goal:** Cho phép người học gọi điện thoại (PSTN dial-in) đến một số Twilio và nói chuyện với chatbot Hera đang chạy trên Bedrock AgentCore Runtime — song song với web widget hiện tại của v1, không thay thế.

**Target features:**
- TWIL-01: Twilio Media Streams bridge — μ-law 8kHz inbound ↔ Int16 16kHz cho Sonic (resample inbound + outbound)
- TWIL-02: Bridge layer (Lambda hoặc mở rộng presigner) cầm WebSocket Twilio ↔ AgentCore HTTP/WS protocol
- TWIL-03: Twilio phone number + TwiML pointing đến Media Streams endpoint
- TWIL-DOC: 1 chương workshop mới "Phone channel via Twilio" trong content/{vi,en}/ — không sửa các chương v1

**Key context:**
- Demo budget honored — Twilio paid per minute (~$0.013/phút inbound US/CA), giới hạn rủi ro chi phí
- Hệ thống AWS hiện tại không thay đổi — chỉ thêm bridge + chapter mới
- Web widget v1 vẫn giữ nguyên

### Validated

<!-- Đã có sẵn từ Hugo template baseline. -->

- ✓ Hugo multilingual scaffold (vi/en) — existing
- ✓ hugo-theme-learn integration qua git submodule — existing
- ✓ GitHub Actions workflow deploy Hugo site lên GitHub Pages — existing
- ✓ Custom AWS Cloud Clubs branding (logo, layouts/partials) — existing

<!-- Validated in Phase 1 (Knowledge Base Foundation) — 2026-05-05 -->
- ✓ Bedrock Knowledge Base dùng S3 Vectors + Titan v2 embeddings (1024-dim float32 cosine), chứa Apple product catalog + stock list (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4) — KB-01..KB-06; live KB `BKXE19AH89` in `ap-northeast-1`, validated end-to-end with `aws bedrock-agent-runtime retrieve` returning top score 0.86 for "iPhone 13 Pro Max stock"

<!-- Validated in Phase 2 (Pipecat Voice Agent — Local) — 2026-05-05 -->
- ✓ Pipecat 1.1.0 agent code (Python 3.12, FastAPI /ping + /ws) chạy local + container, kết nối Nova 2 Sonic + KB tool `lookup_product` end-to-end. AGT-01..AGT-08 validated; multi-arch container (linux/arm64+amd64) ready cho ECR; AGT-04 latency gate live (LATENCY_MS=0 < 3000ms); IAM consumer policy `hera-kb-retrieve-prod` shipped (D-22 deferred attachment to Phase 3).

<!-- Validated in Phase 3 (AgentCore Deploy + Web Widget + Public Demo URL) — 2026-05-06 -->
- ✓ Container deployed to Amazon Bedrock AgentCore Runtime (`hera_agent-GIsf2P4ImD` in ap-northeast-1), web widget polished (Apple Store light theme, 5-state record button, 5 verbatim WID-06 error strings, 30s heartbeat), public CloudFront URL `https://dg0w939ktclw6.cloudfront.net` live with HSTS + nosniff. DEP-01..06, WID-01..06, DEM-01..03 validated. Rule-4 architectural deviation: Lambda widget_presigner mints SigV4-presigned WSS URLs (browsers can't sign WS upgrades directly).

<!-- Validated in Phase 4 (Observability, Cost Control, Cleanup) — 2026-05-06 -->
- ✓ Phase 3 SC#2 closed: `POST /invocations` static-envelope stub deployed; AgentCore data-plane invoke returns statusCode=200; AgentCore Runtime promoted to version=3 (image hera-agent:7e72b66 multi-arch). CloudWatch dashboard `hera-prod` live in ap-northeast-1 with 5 panels; 2 op alarms (error rate >5%/5min via metric_query arithmetic, latency p95 >5s/5min via extended_statistic) + 1 billing alarm in us-east-1 via second provider alias ($5/day cap, alarm_actions=[] per D-35). bin/cleanup-verify.sh ships 19 read-only resource checks (verify-only per D-39, no Cost Explorer per D-38). Zero new IAM. OBS-01..05 validated; 5 deferred-by-design items (browser smoke, billing-alerts toggle, workshop-close cleanup, 24h Cost Explorer paste, D-30 quota request) tracked in 04-HUMAN-UAT.md — none blocking.

<!-- Validated in Phase 5 (Workshop Documentation vi/en) — 2026-05-07 -->
- ✓ All 5 chapters published bilingual (vi+en) in `content/{vi,en}/`: Phần 1 Introduction (Mermaid component+sequence diagrams D-55), Phần 2 Preparation (AWS account + Bedrock model access + tooling), Phần 3 Hands-on (5 sub-pages 3.1 KB, 3.2 Pipecat Local, 3.3 AgentCore Deploy, 3.4 Web Widget, 3.5 Observability), Phần 4 Cleanup (3-step teardown + D-38 24h Cost Explorer paste), Phần 5 Summary (cost recap + v2 expansion roadmap). DOC-01..10 validated; DOC-12 parity gate live (`bin/check-i18n-parity.sh` exits 0; vi=11, en=11). Plan 05-05 closed 3 verification gaps: themes/hugo-theme-learn submodule registered (sha 3202533a, CR-01); 14 instructor literals redacted to `<your-*>` placeholders + resolution commands (CR-02); 30 Phần tokens renamed Chapter X / Section X.Y across content/en (WR-02). 4 human-verification items deferred (organic CI build, learner walkthrough, DOC-11 PNG sweep, WR-01 byte-parity drift decision) tracked in 05-HUMAN-UAT.md — none blocking the v1 milestone close. DOC-11 (annotated screenshots) stays Pending — operator-deferred sweep.

### Active

<!-- Phạm vi v1, tất cả là hypothesis cho đến khi ship. -->

**Workshop docs (Hugo, vi + en) — Phase 5 owns:**

- [ ] Phần 1 — Introduction: voice AI là gì, Nova Sonic vs ElevenLabs, vì sao dùng Bedrock AgentCore Runtime, kiến trúc hera
- [ ] Phần 2 — Preparation: AWS account setup, enable Bedrock Nova 2 Sonic + AgentCore model access, install Terraform + AWS CLI + uv (Python)
- [ ] Phần 3 — Hands-on: từng bước build (KB + S3 Vectors → Pipecat agent code local test → AgentCore deploy → web widget + observability) — mỗi bước có code snippet và screenshot
- [ ] Phần 4 — Cleanup: 3-step quy trinh (cdk destroy → terraform destroy → bin/cleanup-verify.sh) + 24h Cost Explorer $0 paste-line
- [ ] Phần 5 — Summary: cost breakdown, mở rộng hướng nào tiếp (Twilio, multi-language, multi-agent, RAG sâu hơn)

### Out of Scope (v1)

<!-- Twilio Voice integration: moved to ACTIVE in v2.0 (Current Milestone above). v1 was web-widget-only by design. -->
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
- **Channel v1**: chỉ Web widget. **v2 (Current Milestone)**: thêm Twilio PSTN channel song song
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
*Last updated: 2026-05-07 — Milestone v2.0 (Twilio Voice Channel) STARTED. v1 (Phases 1-5, 46/46 v1 reqs) complete and published as bilingual workshop blog. v2 scope: TWIL-01..03 + TWIL-DOC — phone dial-in via Twilio Media Streams bridged to existing AgentCore Runtime; web widget unchanged.*
