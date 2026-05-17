---
title: "Chuẩn bị"
date: 2025-01-01
weight: 2
chapter: true
pre: "<b>2. </b>"
---

### Chuẩn bị

# Chuẩn bị môi trường

Trong phần này bạn cấu hình một AWS account sạch để có thể deploy Hera trong Phần 3 mà không bị chặn ở các bước UI bắt buộc một lần (model access, billing alerts) hay các tool còn thiếu trên máy local.

## Mục tiêu

Kết thúc chương này bạn có: AWS account ready, model access đã enable cho Nova 2 Sonic + Titan v2, công cụ local đã cài (AWS CLI v2, Terraform, uv, Docker với buildx, jq), credentials đã configured, và một kỳ vọng chi phí cho session ~2 giờ.

## AWS Account checklist

- Bạn có AWS account riêng — không dùng tài khoản chia sẻ. Tránh chạy bằng root user; dùng IAM user hoặc IAM Identity Center identity.
- Quyền IAM cho phép create/destroy: Bedrock, AgentCore, ECR, S3, CloudFront, CloudWatch, IAM (cho deploy), Lambda. Đơn giản nhất cho workshop scope là `AdministratorAccess` cho IAM user của bạn (đây là demo cá nhân, không phải production).
- Region đích: `ap-northeast-1` (Tokyo). Workshop default per D-47. Nếu bạn ở khu vực khác, các region khác có Nova 2 Sonic + AgentCore là `us-east-1`, `us-west-2`, `eu-north-1` — đổi biến `region` trong `infra/envs/prod/terraform.tfvars` trước khi `terraform apply`.
- Billing Alerts đã được tick: AWS Console > Billing > Billing Preferences > "Receive Billing Alerts". Đây là per-account-one-time; mất ~15 phút sau khi tick để alarm bắt đầu nhận data — nếu không tick thì billing alarm sẽ ngồi ở `INSUFFICIENT_DATA` mãi mãi dù tài nguyên đã deploy.
- Khả năng chạy `aws sts get-caller-identity` trên máy local thành công (xem section "Cấu hình AWS credentials" bên dưới).

## Bật Bedrock model access (per-region, per-model)

AWS gates Bedrock foundation models per-account-per-region. Workshop dùng 3 model trong `ap-northeast-1`:

- `amazon.nova-sonic-v1:0` — Nova 2 Sonic, bidirectional speech-to-speech, dùng cho voice loop.
- `amazon.titan-embed-text-v2:0` — Titan Text Embeddings v2, dùng cho Knowledge Base embeddings (1024-dim float32 cosine).
- AgentCore Runtime không phải foundation model nhưng cần region hỗ trợ; `ap-northeast-1` đáp ứng cả ba.

Steps:

- Mở `https://console.aws.amazon.com/bedrock/` trong region `Asia Pacific (Tokyo) ap-northeast-1` (kiểm tra region selector ở góc trên bên phải).
- Click "Model access" → "Modify model access" → tick `Amazon Nova 2 Sonic` + `Amazon Titan Text Embeddings V2` → Submit. Mất ~1 phút để chuyển sang `Granted`.
- Verify bằng CLI:

```bash
aws bedrock list-foundation-models --region ap-northeast-1 \
  --query 'modelSummaries[?modelId==`amazon.titan-embed-text-v2:0`].modelLifecycle.status' \
  --output text
# Expect: ACTIVE
```

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-03*

Lặp lại với `amazon.nova-sonic-v1:0`. Output rỗng có nghĩa là model access chưa enable.

![Bedrock Console — Model access cho Amazon Nova 2 Sonic (ap-northeast-1)](/images/2-preparation/bedrock-model-access-nova-sonic.png)

![Bedrock Console — Model access cho Titan Text Embeddings V2 (ap-northeast-1)](/images/2-preparation/bedrock-model-access-titan-v2.png)

{{% notice warning %}}
**Bật Bedrock model access là per-region, per-model:** chưa enable thì `terraform apply` ở Phần 3.1 vẫn pass nhưng `aws bedrock-agent start-ingestion-job` sẽ fail với `AccessDeniedException` ở model ARN — báo lỗi xảy ra ở sync time chứ không ở apply time. Nếu bạn deploy sang region khác (`us-east-1`, `us-west-2`, `eu-north-1`), phải enable lại từng model ở region mới — IAM ở region cũ không carry over.

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-03*
{{% /notice %}}

## Cài AWS CLI v2

Workshop dùng AWS CLI v2 (v1 không hỗ trợ một số command `bedrock-agent*` mà ta dùng cho Phần 3.1).

```bash
aws --version
# Expect: aws-cli/2.x.x
```

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-01*

Nếu chưa có, làm theo: `https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html`.

## Cài Terraform >= 1.9

Phase 1 và Phase 2 IaC dùng `hashicorp/aws ~> 6.27` — Terraform CLI 1.9 trở lên đáp ứng được provider này.

```bash
terraform -version
# Expect: Terraform v1.9.x or newer
```

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-01*

Cài đặt: `https://developer.hashicorp.com/terraform/install`.

## Cài uv (Python package manager)

Workshop dùng `uv` exclusively — không dùng `pip`, không dùng `python3 ...` trực tiếp. `uv` quản lý Python 3.12 + lockfile cho project `agent/` và đảm bảo bạn install đúng version Pipecat 1.1.0 đã được test.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
# Expect: uv 0.10 or newer
```

*Source: agent/pyproject.toml — Phase 2 Plan 02-01*

## Cài Docker Desktop với buildx

Phần 3.3 build container multi-arch (`linux/arm64` + `linux/amd64`) qua `docker buildx`. AgentCore Runtime ARM64-only nên cần arm64 manifest để deploy; same image artifact vẫn chạy được trên local AMD64 dev machine. `buildx` bundled với Docker Desktop 20.10+ và Docker Engine 20.10+.

```bash
docker --version
docker buildx version
# Expect: docker buildx 0.x.x or newer
```

*Source: agent/Dockerfile — Phase 2 Plan 02-02*

## Cài jq

`jq` là JSON parser dùng cho `bin/verify-kb.sh` và một số paste-block trong Phần 3.1.

```bash
jq --version
# Install: winget install jqlang.jq (Windows)
#          brew install jq            (macOS)
#          apt-get install jq         (Debian/Ubuntu)
```

*Source: bin/verify-kb.sh — Phase 1 Plan 01-03*

## Cấu hình AWS credentials

Pipecat agent (Phần 3.2) đọc credentials qua boto3 default chain (env vars → `~/.aws` → IMDSv2). Cấu hình một trong hai cách:

```bash
# Long-lived IAM user access keys
aws configure

# Or short-lived SSO / IAM Identity Center
aws configure sso

# Verify resolution
aws sts get-caller-identity
# Expect: prints account ID + IAM ARN you will deploy into
```

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-01*

Nếu bạn dùng SSO, nhớ chạy `aws sso login` trước khi mỗi session — credentials short-lived sẽ expire sau ~1 giờ.

## Kỳ vọng chi phí

- Một buổi workshop khoảng 2 giờ (build + nói chuyện với agent + cleanup) ước tính tốn **~$2-5 USD** nếu bạn chạy Phần 4 Cleanup ngay sau khi xong. Số liệu chi tiết sẽ được cập nhật ở Phần 5 Summary.
- Hai nguồn chi phí chính: Bedrock Nova 2 Sonic streaming (tính theo phút conversation) + AgentCore Runtime (tính theo giây session active). KB + S3 Vectors + CloudFront ở quy mô workshop chỉ dưới một cent.
- **Quan trọng:** chạy Phần 4 Cleanup (cdk destroy → terraform destroy → `bin/cleanup-verify.sh`) ngay sau khi xong buổi để chi phí dừng lại. Cost Explorer cập nhật chậm 24 giờ — kiểm tra ngày hôm sau theo paste-line trong Phần 4.

{{% notice info %}}
**Số liệu chi phí sẽ cập nhật sau:** mức `~$2-5 USD cho buổi 2 tiếng` chỉ là ước tính khung. Số chi tiết theo từng service sẽ được bổ sung ở Phần 5 Summary sau khi rút data 24h từ Cost Explorer của 1 buổi workshop thực tế. Giá AWS thay đổi định kỳ — bookmark `https://aws.amazon.com/bedrock/pricing/` để check số mới nhất.
{{% /notice %}}

## Sẵn sàng vào Phần 3 Hands-on

Bạn đã có account + model access + tools + credentials + cost expectation. Tiếp theo:

- **Phần 3.1** deploy Bedrock Knowledge Base trên S3 Vectors và verify Retrieve API.
- **Phần 3.2** chạy Pipecat agent local để tool `lookup_product` gọi được KB vừa deploy.
- **Phần 3.3, 3.4, 3.5** deploy lên AgentCore Runtime + web widget + observability.
