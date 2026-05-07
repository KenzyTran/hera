---
title: "Tổng kết"
date: 2025-01-01
weight: 5
chapter: true
pre: "<b>5. </b>"
---

# Tổng kết Workshop

Chúc mừng — bạn vừa deploy thành công một voice chatbot trên AWS account của mình và nói chuyện được với nó qua trình duyệt. Phần này cô đọng những gì bạn đã build, cost ballpark thực tế, và roadmap mở rộng cho v2.

## Bạn đã làm được gì

- Apple product catalog ingested vào Bedrock Knowledge Base trên S3 Vectors backend với Titan Text Embeddings v2 (1024-dim, float32, cosine).
- Pipecat 1.1.0 voice agent (Python 3.12) chạy local + container multi-arch (linux/arm64, linux/amd64) + deploy lên Amazon Bedrock AgentCore Runtime ở `ap-northeast-1`.
- Web widget HTML/JS deploy lên S3+CloudFront với presigner Lambda Function URL bridge cho SigV4 WebSocket auth (browser không tự sign WSS được).
- CloudWatch dashboard `hera-prod` với 5 panels + 2 operational alarms + 1 billing alarm cross-region (`us-east-1` AWS/Billing constraint).
- Cleanup quy trinh verified bằng `bin/cleanup-verify.sh` (19 read-only checks về $0 ongoing cost).

## Cost recap (D-54)

**Total cho 2-hour session với cleanup theo Phần 4: ballpark `~$2-5 USD`.** Không cleanup: thêm `~$5-15 USD/ngày` tùy AgentCore Runtime idle pattern và CloudFront request volume. Hai cost driver chính: Bedrock Nova 2 Sonic streaming (per active conversation minute) và AgentCore Runtime (per active session-second).

Per-service breakdown sẽ cập nhật post-launch sau khi instructor pull 24h Cost Explorer data từ một workshop session thực tế (04-HUMAN-UAT item #4 — paste-line ở Phần 4 cuối). Lúc đó bảng chi tiết per-service sẽ thay thế đoạn này — số instructor's actual spend là ground truth thay cho estimate.

*Source: D-54 ballpark + 04-HUMAN-UAT item #4 deferred — Phase 5 Plan 05-04*

**Caveats quan trọng:**

- AWS Free Tier reset hàng tháng — số trên giả định bạn còn free tier.
- Cost Explorer cập nhật sau 24 giờ — số tức thời cuối session có thể chưa reflect.
- AWS pricing thay đổi định kỳ; bookmark `https://aws.amazon.com/bedrock/pricing/` cho live numbers.

## Mở rộng (DOC-09)

Bạn đã có working voice loop. Đây là 4 hướng mở rộng phổ biến — đều DEFERRED v2 trong scope workshop hiện tại nhưng có roadmap và requirement IDs để bạn tự build tiếp.

### Twilio Voice Channel (TWIL-01..03 — v2)

Phone number Twilio nhận cuộc gọi → Twilio Media Streams kết nối tới AgentCore endpoint thay vì browser → workshop chapter "Phone channel via Twilio". Bridge Layer ở giữa: Twilio gửi μ-law 8kHz; Pipecat cần Int16 16kHz cho Sonic — phải resample inbound + outbound ở presigner hoặc một dedicated Lambda. Reference: `https://www.twilio.com/docs/voice/twiml/stream`.

### Multi-language chatbot (I18N-01..02 — v2)

Detect ngôn ngữ user nói (vi/en) tự động + Sonic phát audio tiếng Việt khi quality acceptable. Hiện Sonic-vi quality thấp hơn Sonic-en đáng kể (cập nhật 2026-Q1) — chờ AWS upgrade voice model trước khi v2. Workshop docs đã bilingual sẵn (DOC-12 parity gate); chỉ còn voice path là cần I18N work.

### Multi-agent routing (ADV-01 — v2)

Orchestrator agent route tới các specialized agent (sales, support, billing) theo intent từ Sonic tool-use. Mô hình tương tự `awslabs/agentcore-samples` workflow patterns. Cần thêm agent state (DynamoDB ADV-03 — conversation history persistent) để cross-agent context không bị mất khi switch.

### Conversation history persistent (ADV-03 — v2)

DynamoDB per-user session store cho returning users; v1 in-memory only (D-21 Phase 2 — `LLMContext` per WebSocket, free khi disconnect). v2 cần Cognito SSO (AUTH-01..02) để có user identity bind được session với, và DynamoDB table với TTL để auto-expire history sau N ngày.

## Các deferral khác (v2 backlog)

- Cognito SSO + per-user quota (AUTH-01..02 — workshop hiện tại anonymous + AgentCore concurrency cap=2 là gate).
- ECS Fargate alternative deployment chapter để compare AgentCore vs self-hosted (ADV-04).
- Hugo theme migration `hugo-theme-learn` → `hugo-theme-relearn` (THEME-01..02 — `hugo-theme-learn` deprecated upstream nhưng vẫn hoạt động cho v1).
- Custom domain + ACM cert thay cho `*.cloudfront.net` default (Phase 3 D-26 deferred — sẽ unlock TLSv1.2_2021 minimum thay vì TLSv1 auto-downgrade).
- Knowledge Base với RAG re-ranking (ADV-02 — extra Bedrock invocation per retrieve, trade-off latency vs precision).
- Bedrock Guardrails PII redaction (PROJECT.md Out of Scope v1 — workshop dùng demo data Apple catalog, không xử lý PII thật).

Tracking đầy đủ ở `.planning/REQUIREMENTS.md` § v2 Requirements.

## Cảm ơn

Workshop được build cho AWS Cloud Clubs Vietnam, mục tiêu giúp Cloud Clubs members tự deploy được voice chatbot trên AWS account của mình end-to-end — không phải xem demo, mà thực sự ship.

Reference architecture: AWS blog post "Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1" (`https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/`) là blueprint chính. Reference repo: `https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore`.

Issues / improvements: PR vào repo workshop trên GitHub (URL từ `config.toml` `baseURL`). Workshop là living doc — pricing drift, AWS service updates, và Pipecat version bump đều cần re-verify periodic.

## Tài liệu tham khảo

- `RUNBOOK.md` — operator runbook đầy đủ (paste-style ops; mỗi section workshop chapter có pointer tới đó).
- `.planning/PROJECT.md` — core value + locked stack rationale.
- `.planning/REQUIREMENTS.md` — 46 v1 requirements + v2 deferred backlog.
- `.planning/ROADMAP.md` — 5-phase plan + per-phase success criteria.
- AWS Bedrock pricing: `https://aws.amazon.com/bedrock/pricing/`.
- AgentCore Runtime docs: `https://docs.aws.amazon.com/bedrock-agentcore/`.
- Pipecat 1.1.0: `https://docs.pipecat.ai/`.
