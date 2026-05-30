---
title: "3.1 Knowledge Base"
date: 2025-01-01
weight: 1
---

## Mục tiêu phần này

Deploy Bedrock Knowledge Base trên S3 Vectors với Titan v2 embeddings, ingest catalog Apple, verify được Retrieve API trả về document đúng cho query "iPhone 13 Pro Max stock". Sau bước này KB sẵn sàng cho Pipecat agent ở Phần 3.2 gọi qua tool `lookup_product`.

## Cấu trúc catalog

Apple catalog gồm 4 file markdown trong `catalog/`. Stock + price được inline trong từng file để chunks Retrieve trả về luôn co-locate stock với SKU name (D-03 Phase 1) — Sonic không phải join nhiều chunks để có câu trả lời.

```bash
ls catalog/
# apple-watch-s11.md  iphone-13-pro-max.md  macbook-pro-m4.md  store-policy.md
```

*Source: catalog/ — Phase 1 Plan 01-01*

## Bước 1: Deploy infra (Terraform)

Module `infra/modules/knowledge_base/` tạo S3 source bucket + S3 Vectors bucket + index + Bedrock KB + data source + KB service IAM role. Resource names cố định không có random suffix (D-12) — retry sau partial failure dùng `terraform destroy && terraform apply`, không phải `terraform import`.

```bash
cd infra/envs/prod
terraform init
terraform apply -target=module.knowledge_base
# Review the plan (about 9 resources). Type 'yes' to apply.
cd ../../..
```

*Source: RUNBOOK.md (First deploy) — Phase 1 Plan 01-02*

{{% notice warning %}}
**Vì sao có `-target=module.knowledge_base`?** Root `infra/envs/prod` gom toàn bộ module của dự án (KB, ECR, widget, IAM, presigner, observability...). Module `observability` cần **AgentCore Runtime ARN** — runtime này CHƯA tồn tại ở bước này (mãi Phần 3.3 mới tạo bằng `cdk deploy`). Nếu chạy `terraform apply` trần ngay bây giờ, observability sẽ fail với lỗi CloudWatch `Member must have length greater than or equal to 1` (dimension rỗng). `-target=module.knowledge_base` chỉ tạo KB cho phần này; các module còn lại được apply ở Phần 3.3 (foundation) và lần apply thứ hai (sau khi có runtime ARN). Terraform sẽ in cảnh báo vàng về `-target` — đúng dự kiến, không phải lỗi.
{{% /notice %}}

Hoàn tất trong ~30-60 giây. Outputs: `kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`. Cả 2 bucket lúc này đang rỗng — bước tiếp theo upload catalog content.

## Bước 2: Ingest catalog (manual sync)

`terraform apply` tạo KB nhưng KHÔNG auto-trigger ingestion (D-05, D-07). Bạn upload `catalog/*.md` vào S3 source bucket, rồi gọi `aws bedrock-agent start-ingestion-job` để KB embed + index. Job thường complete trong dưới một phút cho 4 document.

```bash
# 1. Resolve outputs from terraform state
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
SRC_BUCKET=$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)
REGION=ap-northeast-1

# 2. Upload all catalog markdown to the catalog/ prefix
aws s3 cp catalog/ "s3://${SRC_BUCKET}/catalog/" --recursive --exclude "*" --include "*.md"

# 3. Trigger the ingestion job
JOB_ID=$(aws bedrock-agent start-ingestion-job \
  --region "${REGION}" \
  --knowledge-base-id "${KB_ID}" \
  --data-source-id "${DS_ID}" \
  --description "first sync" \
  --query 'ingestionJob.ingestionJobId' \
  --output text)
echo "started ingestion job: ${JOB_ID}"

# 4. Poll until COMPLETE (or FAILED / STOPPED)
while true; do
  STATUS=$(aws bedrock-agent get-ingestion-job \
    --region "${REGION}" \
    --knowledge-base-id "${KB_ID}" \
    --data-source-id "${DS_ID}" \
    --ingestion-job-id "${JOB_ID}" \
    --query 'ingestionJob.status' \
    --output text)
  echo "status: ${STATUS}"
  case "${STATUS}" in
    COMPLETE|FAILED|STOPPED) break ;;
  esac
  sleep 5
done
```

*Source: RUNBOOK.md (First sync) — Phase 1 Plan 01-03*

Lưu ý hai CLI surface khác nhau (Pitfall J từ RUNBOOK): `aws bedrock-agent` là build-time control plane (KBs, agents, ingestion jobs). `aws bedrock-agent-runtime` là runtime data plane (Retrieve, RetrieveAndGenerate). Sync dùng `bedrock-agent`; verify ở Bước 3 dùng `bedrock-agent-runtime`.

## Bước 3: Verify Retrieve API

Sau khi ingestion job báo `COMPLETE`, vectors đã được ghi nhưng có thể chưa queryable ngay — chạy `bin/verify-kb.sh` để poll Retrieve API tới khi top score vượt threshold 0.4.

```bash
bin/verify-kb.sh
```

*Source: bin/verify-kb.sh — Phase 1 Plan 01-03*

Output cuối cùng khi success:

```
OK: 3 results returned, top score 0.78 >= threshold 0.4
```

Script poll mỗi 15 giây tới 20 lần (5 phút tổng) để absorb post-sync propagation lag. Tại KB của bạn (`<your-kb-id>` — resolve qua `terraform -chdir=infra/envs/prod output -raw kb_id`), top score đo được phụ thuộc môi trường nhưng thường nằm trong khoảng `0.80-0.90` cho query mặc định "iPhone 13 Pro Max stock". Score chính xác phụ thuộc embedding seed và Bedrock model version snapshot tại thời điểm sync.

{{% notice warning %}}
**KB sync delay sau ingestion:** sau khi ingestion job báo `COMPLETE`, vectors đã được ghi nhưng có thể mất thêm 2-3 phút để Bedrock KB Retrieve API trả về chúng. Đây là behavior AWS đã document, không phải bug. `bin/verify-kb.sh` poll tới 5 phút để cover delay này. Nếu sau 5 phút vẫn empty results, kiểm tra:

- `inclusion_prefixes = ["catalog/"]` trong data source khớp với prefix bạn upload (`s3://<bucket>/catalog/`).
- Ingestion job thực sự `COMPLETE` (không phải `FAILED`):
  `aws bedrock-agent list-ingestion-jobs --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" --region "${REGION}"`.
- Bedrock model access cho `amazon.titan-embed-text-v2:0` đã enable trong region (Phần 2). Empty results sau khi job COMPLETE thường là model access miss ở region khác.

*Source: bin/verify-kb.sh — Phase 1 Plan 01-03*
{{% /notice %}}

## Bước 4: Re-index sau khi sửa catalog

Khi stock count hoặc price thay đổi, sửa file `catalog/*.md` tại chỗ, upload lại, rồi gọi cùng `start-ingestion-job` command. Bedrock KB phát hiện document đã đổi và incrementally re-embed chỉ phần diff (D-06) — không cần delete và re-upload toàn bộ catalog.

```bash
# Edit the file
$EDITOR catalog/iphone-13-pro-max.md

# Re-upload (overwrites the S3 object)
SRC_BUCKET=$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)
aws s3 cp catalog/iphone-13-pro-max.md "s3://${SRC_BUCKET}/catalog/iphone-13-pro-max.md"

# Re-run the ingestion job (same command as First sync)
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
aws bedrock-agent start-ingestion-job \
  --region ap-northeast-1 \
  --knowledge-base-id "${KB_ID}" \
  --data-source-id "${DS_ID}" \
  --description "re-index after editing iphone-13-pro-max.md"

# Wait for status COMPLETE, then run verify (covers propagation)
bin/verify-kb.sh
```

*Source: RUNBOOK.md (Re-index) — Phase 1 Plan 01-03*

Bedrock KB ingestion là incremental — chỉ document đã sửa được re-embed; chi phí dưới một cent ở scale workshop.

## Tiếp theo

KB đã sẵn sàng và queryable. Phần 3.2 sẽ chạy Pipecat agent local; tool `lookup_product` trong agent gọi `aws bedrock-agent-runtime retrieve` ở chính KB này — bạn đã có `kb_id` từ `terraform output -raw kb_id` để export thành env var `HERA_KB_ID` cho agent.
