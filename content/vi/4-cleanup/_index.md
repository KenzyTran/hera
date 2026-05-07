---
title: "Dọn dẹp tài nguyên"
date: 2025-01-01
weight: 4
chapter: true
pre: "<b>4. </b>"
---

# Dọn dẹp tài nguyên

{{% notice warning %}}
**Đừng bỏ qua phần này.** AgentCore Runtime + Bedrock Knowledge Base + S3 Vectors
+ CloudFront tiếp tục tính phí (~$0.05/giờ trở lên) cho đến khi bạn tear down.
Thực hiện 3 bước bên dưới NGAY sau khi xong session, rồi kiểm tra Cost Explorer
24 giờ sau (D-38) để xác nhận $0 ongoing cost.
{{% /notice %}}

## Mục tiêu phần này

Tear down toàn bộ AWS resource mà workshop đã tạo (Phases 1-4) về $0 ongoing cost. Verify bằng `bin/cleanup-verify.sh` (19 read-only checks) ngay sau khi destroy, và confirm $0 ở Cost Explorer 24 giờ sau (do ingestion lag của Cost Explorer).

## Cleanup contract: thứ tự bắt buộc (D-24)

**CDK trước, Terraform sau.** AgentCore Runtime resource (do CDK quản lý) hold IAM exec role + log group + container image references mà Terraform tạo. Nếu bạn chạy `terraform destroy` trước, nó sẽ fail vì IAM role vẫn `InUse` bởi Runtime — bạn phải re-run sau khi `cdk destroy` mới sạch được.

Verify-only script (D-39): `bin/cleanup-verify.sh` chỉ READ, không destroy bất cứ thứ gì. Operator destroy; script chỉ verify. Đây là design choice cố tình — script không có quyền hủy nhầm resource đang chạy production.

Region pin: chạy `cdk destroy` + `terraform destroy` trong region bạn đã deploy (default `ap-northeast-1`). Nếu bạn deploy ở region khác, set `HERA_REGION` trước khi chạy `bin/cleanup-verify.sh`.

## Bước 1: cdk destroy hera-agentcore

```bash
(cd infra/cdk && uv run cdk destroy hera-agentcore --force)
```
*Source: RUNBOOK.md (Phase 4 Cleanup Step 1) — Phase 4 Plan 04-03*

CDK destroy AgentCore Runtime đầu tiên. Khi xong: IAM exec role unattached + log group flushed (24h retention) + container image references freed. Mất khoảng 30-60 giây. Sau bước này, Terraform có thể destroy IAM role mà không gặp `Role still in use` error.

## Bước 2: terraform destroy

```bash
(cd infra/envs/prod && terraform destroy -auto-approve)
```
*Source: RUNBOOK.md (Phase 4 Cleanup Step 2) — Phase 4 Plan 04-03*

`terraform destroy` tear down phần còn lại: Knowledge Base + S3 source bucket + S3 Vectors + IAM (5 roles + policies) + ECR repo + widget S3+CloudFront + observability dashboard + 3 alarms + presigner Lambda + Function URL.

{{% notice warning %}}
**CloudFront mất 15-30 phút disable-then-delete cycle. KHÔNG ngắt:** nếu bạn
Ctrl+C trong cycle này, distribution sẽ stuck ở `Enabled=false, Deployed=true`
và bạn phải re-run `terraform destroy` để hoàn tất. Cứ để chạy. CloudFront
trong AWS có quy trình propagate periodic — chấp nhận và đi pha cà phê.

*Source: RUNBOOK.md (Phase 4 Cleanup Step 2 warning) — Phase 4 Plan 04-03*
{{% /notice %}}

## Bước 3: bin/cleanup-verify.sh

```bash
bash bin/cleanup-verify.sh
```
*Source: bin/cleanup-verify.sh — Phase 4 Plan 04-03*

Script làm gì:

- 19 read-only AWS API calls cross các region/service: Knowledge Base, S3 source bucket, S3 Vectors index, AgentCore Runtime, ECR, widget S3 + CloudFront, IAM (5 roles + 1 policy), log groups, 3 alarms, 1 dashboard, presigner Lambda Function URL.
- Mỗi check increment `PASS_COUNT` hoặc `FAIL_COUNT`.
- Exit 0 nếu tất cả gone; exit 1 với hint block nếu có leftover.
- Helper-driven: `_check_gone` (alternation regex `ResourceNotFound|NoSuchEntity|NotFound|...`) + `_check_count_zero` (length(@) query).
- Windows-bash quirk: `MSYS_NO_PATHCONV=1` prefix trên log-group calls (PITFALL G.8 — Git Bash mangling path bắt đầu bằng `/`).

Expected output (success):

```
----------------------------------------
cleanup-verify: 19/19 resource checks passed
OK: all phase 1/2/3/4 resources gone
```

{{% notice info %}}
**Hero screenshot deferred:** the all-green PASS terminal capture for
`bin/cleanup-verify.sh` will land in a follow-up commit after the
post-workshop-close verification sweep (04-HUMAN-UAT item #3 — first
organic cleanup-verify run against actually-torn-down state). Until
then this section ships text-only; the script exit-0 + the success
block above are the canonical evidence.
{{% /notice %}}

## Nếu cleanup-verify FAIL

Nguyên nhân thường gặp (RUNBOOK Phase 4):

- Step 1 / Step 2 đảo ngược (D-24 — CDK phải destroy trước Terraform).
- `terraform destroy` bị ngắt giữa CloudFront 15-30 phút cycle — re-run lại.
- ECR repo còn images (default `force_delete=false`) — fallback xóa images thủ công:

  ```bash
  aws ecr batch-delete-image --repository-name hera-agent \
    --image-ids imageTag=<tag1> imageTag=<tag2> \
    --region ap-northeast-1
  ```
  *Source: RUNBOOK.md (Phase 4 ECR fallback) — Phase 4 Plan 04-03*

- Hoặc set `var.force_delete = true` trong `infra/envs/prod` rồi re-run `terraform destroy`.

Sau khi clear root cause, re-run `bash bin/cleanup-verify.sh` cho đến khi 19/19 PASS.

## Verify $0 ongoing cost (24h sau destroy — D-38)

Cost Explorer có ingestion lag tới 24 giờ. Chạy paste-line này NGÀY MAI sau khi destroy, không phải bây giờ. Số tức thời cuối session sẽ chưa show — đây là AWS service constraint, không phải bug.

Mỗi Cost Explorer API call là $0.01. Chạy 1 lần là OK; nếu instructor chạy 90 lần across cohort thì tốn $0.90 — vì vậy paste-line sống ở chapter này như một follow-up cá nhân (operator-driven), không phải auto-run từ script.

```bash
# Replace YYYY-MM-DD with the actual destroy date.
DESTROY_DATE=YYYY-MM-DD
NEXT_DAY=$(date -d "${DESTROY_DATE} +1 day" +%Y-%m-%d 2>/dev/null || \
           date -j -v+1d -f "%Y-%m-%d" "${DESTROY_DATE}" +"%Y-%m-%d")

cat > /tmp/no-tax-credits.json <<'JSON'
{
  "Not": {
    "Dimensions": {
      "Key": "RECORD_TYPE",
      "Values": ["Tax", "Credit", "Refund"]
    }
  }
}
JSON

aws ce get-cost-and-usage \
  --time-period "Start=${DESTROY_DATE},End=${NEXT_DAY}" \
  --granularity DAILY \
  --metrics BlendedCost \
  --filter file:///tmp/no-tax-credits.json \
  --region us-east-1 \
  | jq '.ResultsByTime[].Total.BlendedCost.Amount'
```
*Source: RUNBOOK.md (Phase 4 Verify $0 ongoing cost) — Phase 4 Plan 04-03*

Expected output: `"0"` hoặc `"0.0000000000"` (string). Anything non-zero indicates một billable resource leftover — re-run `bin/cleanup-verify.sh` và investigate (CloudFront stuck-disable, KB ingestion job hanging, hoặc ECR images chưa xóa là 3 nguyên nhân thường thấy nhất).

Note quan trọng: Cost Explorer region-pinned `us-east-1` bất kể bạn deploy ở region nào; flag `--region us-east-1` ở trên là cho clarity (CLI cũng auto-route nếu không pass).

## Tiếp theo

AWS account của bạn về $0 ongoing cost. Phần 5 cô đọng cost recap + roadmap mở rộng (Twilio voice, multi-language, multi-agent routing) — những hướng v2 mà bạn có thể tự build tiếp trên foundation đã có.
