---
title: "Hera — Workshop Voice Agent trên AWS"
date: 2025-01-01
weight: 0
---

# Hera — Workshop Voice Agent trên AWS

### Giới thiệu

Hera là workshop FCJ (First Cloud Journey) hướng dẫn bạn deploy một voice AI chatbot trên AWS account của chính mình, nói chuyện với nó qua trình duyệt, và dọn dẹp về $0 ngay sau session. Stack thuần AWS: Amazon Nova 2 Sonic làm voice model, Amazon Bedrock AgentCore Runtime làm compute managed, S3 Vectors + Titan v2 làm knowledge base, Pipecat 1.1.0 làm orchestrator.

| Thông tin | Chi tiết |
|-----------|----------|
| Thời gian | ~3-4 giờ hands-on |
| Cấp độ | Intermediate |
| Chi phí | ~$2-5 USD nếu dọn dẹp theo Phần 4 |
| Region mặc định | ap-northeast-1 |

### Yêu cầu

- AWS Account (IAM user quyền Administrator, không dùng root).
- Kiến thức cơ bản AWS CLI / IAM / Terraform / Docker.
- Máy local có AWS CLI v2, Terraform >= 1.9, Docker Desktop (multi-arch buildx), uv (Python package manager), jq.
- Khả năng đọc tiếng Anh ở mức cơ bản (chatbot speech là tiếng Anh; documentation song ngữ vi/en).

### Nội dung

{{% children depth="1" %}}
