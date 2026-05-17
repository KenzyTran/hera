---
title: "Giới thiệu"
date: 2025-01-01
weight: 1
chapter: true
pre: "<b>1. </b>"
---

## Voice AI là gì

Voice agent là một dịch vụ AI vận hành theo dạng real-time bidirectional audio streaming: người dùng nói vào microphone, audio được stream lên model speech-to-speech, model phản hồi bằng audio, browser phát lại — tất cả diễn ra dưới một giây. Hera dùng Amazon Nova 2 Sonic, một foundation model speech-to-speech của Amazon Bedrock chạy ở `ap-northeast-1`, có khả năng tool-use để gọi Bedrock Knowledge Base trong cùng một stream.

## Vì sao chọn stack này

- **Amazon Nova 2 Sonic on Bedrock** (KHÔNG ElevenLabs / KHÔNG Gemini): pure-AWS, độ trễ thấp từ Việt Nam, billing theo phút, native tool-use cho Knowledge Base lookup.
- **Amazon Bedrock AgentCore Runtime** (KHÔNG ECS Fargate / KHÔNG Lambda): managed runtime, không VPC / ALB / NAT để debug, image ARM64, credential injection qua IMDSv2 — đơn giản hơn nhiều cho workshop scope.
- **Pipecat 1.1.0**: orchestrator chuẩn cho voice loops, có sẵn `AWSNovaSonicLLMService`, tự động xử lý 8-min Sonic stream cap (rotate stream ~120s trước cap).
- **S3 Vectors + Titan v2** (KHÔNG OpenSearch Serverless): cost-driven, khoảng $0.10/tháng cho catalog nhỏ vs $200-400/tháng nếu dùng OpenSearch Serverless.
- **Terraform `~> 6.27` + CDK Python cho AgentCore Runtime**: hybrid IaC (D-24). Terraform 6.x đã hỗ trợ native `s3_vectors_storage_configuration` cho `aws_bedrockagent_knowledge_base`, nhưng AgentCore Runtime chưa có resource Terraform first-party đầy đủ — CDK Python lấp khoảng trống đó cho đúng một stack.

## Kiến trúc tổng thể

![Kiến trúc Hera — Pipecat trên AgentCore Runtime + Bedrock Nova 2 Sonic + KB S3 Vectors](/images/architecture-aws.png)

Browser ghi audio 16 kHz Int16 mono qua AudioWorklet. CloudFront serve widget tĩnh (HTML/JS/CSS) từ S3. Presigner Lambda mint một URL WSS có chữ ký SigV4 sống ngắn (300s) vì browser không tự ký được WebSocket upgrade. AgentCore Runtime chạy Pipecat container, mở bidirectional stream tới Nova 2 Sonic, gọi Bedrock Knowledge Base qua `bedrock:Retrieve` khi Sonic phát tool_use, và stream audio 24 kHz về trình duyệt.

## Voice loop một-vòng

1. **User** click "record" trên widget và nói câu hỏi.
2. **Browser** → **Presigner Lambda**: `POST /` xin URL WSS có ký SigV4.
3. **Presigner Lambda** → **Browser**: trả `{"url": "wss://..."}` (TTL 300 s).
4. **Browser** → **AgentCore Runtime**: WSS upgrade qua URL vừa nhận; sau đó stream audio frame 16 kHz Int16 lên.
5. **AgentCore Runtime (Pipecat)** → **Nova 2 Sonic**: mở bidirectional stream, forward audio.
6. **Sonic** → **Runtime**: emit `tool_use(lookup_product)` khi nhận diện câu hỏi liên quan sản phẩm.
7. **Runtime** → **Bedrock KB** (`bedrock-agent-runtime.retrieve`): query top-3 chunks từ S3 Vectors.
8. **KB** → **Runtime**: trả về chunks (text + score + source).
9. **Runtime** → **Sonic**: gửi `tool_result` vào stream.
10. **Sonic** → **Runtime**: stream audio reply 24 kHz về.
11. **Runtime** → **Browser**: forward audio frames.
12. **Browser** → **User**: phát loa, kết thúc 1 turn (~3 s end-to-end).

## Region mặc định

Mặc định trong workshop là `ap-northeast-1` (Tokyo) cho mọi snippet, mọi screenshot, mọi `--region` flag. Lý do: độ trễ tới Việt Nam thấp nhất, đồng thời Nova 2 Sonic + AgentCore Runtime + Bedrock Knowledge Base + S3 Vectors đều có sẵn trong region này. Nếu bạn ở khu vực khác, các region cũng hỗ trợ Nova 2 Sonic + AgentCore là `us-east-1`, `us-west-2`, `eu-north-1`. Đổi bằng cách sửa biến `region` trong `infra/envs/prod/terraform.tfvars` (Phần 3.1 sẽ chỉ cụ thể).

## Yêu cầu trước khi bắt đầu

### AWS Account

- Bạn cần một AWS Account. Nếu chưa có, [tạo tại đây](https://aws.amazon.com/free/).
- Sử dụng IAM user với quyền Administrator (workshop scope, không production); không dùng root account.

### Kiến thức cần có

- Hiểu biết cơ bản về AWS Console + IAM.
- Kiến thức cơ bản networking (VPC, subnet) và Terraform / Docker.

### Công cụ chính

| Tool | Mô tả |
|------|-------|
| AWS CLI v2 | Command line interface |
| Terraform >= 1.9 | IaC primary |
| uv | Python package manager (KHÔNG dùng pip) |
| Docker Desktop | Multi-arch buildx |
| jq | JSON parser |
| Browser | Chrome/Firefox/Safari (HTTPS bắt buộc cho microphone) |

Phần 2 Preparation có installer paste-blocks chi tiết cho từng nền tảng.

{{% notice warning %}}
**Chi phí:** Workshop có thể phát sinh chi phí nhỏ (~$2-5 USD cho 2-giờ session). Nhớ chạy Phần 4 Cleanup để tear down về $0 ngay sau session.
{{% /notice %}}

## Quy ước workshop

- Snippet mã nguồn ghi rõ source dưới dạng `*Source: <repo-relative-path> — Phase X Plan XX-XX*` (D-42). Nếu có drift, grep footer là re-paste lại được.
- Screenshot AWS Console được chụp với annotation (red box + arrow + label) tại các choke point bắt buộc dùng UI (D-44 — Bedrock model access, Billing Alerts toggle, AgentCore quota request).
- Chatbot speech là tiếng Anh (Sonic mạnh nhất ở en); workshop documentation song ngữ vi/en.
- Code và log không có emoji (giữ grep/diff sạch trên các terminal và công cụ render khác nhau).
- Phần 4 Cleanup là bắt buộc — nếu không dọn, AgentCore Runtime + Bedrock KB tiếp tục tính phí theo giờ active.

{{% notice warning %}}
**Quy ước song ngữ vi/en (DOC-12):** mọi PR sửa workshop content phải commit vi+en cùng lúc.
CI chạy `bin/check-i18n-parity.sh` trước khi build Hugo — nếu `content/vi` và
`content/en` lệch số file `_index.md`, build fail. Quy ước này tránh trạng thái
"chương đã có tiếng Việt nhưng tiếng Anh chưa kịp dịch" trong production.

*Source: bin/check-i18n-parity.sh — Phase 5 Plan 05-01*
{{% /notice %}}

## Tham khảo

- AWS blog: [Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/) — blueprint architecture nguyên bản cho Hera.
- Reference repo: [aws-samples/sample-nova-sonic-websocket-agentcore](https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore) — bidirectional streaming + WebSocket + auth + tool use.
- Hugo theme: [hugo-theme-learn](https://learn.netlify.app/en/) (theme deprecated upstream nhưng vẫn hoạt động cho v1; migration sang relearn deferred sang v2).
