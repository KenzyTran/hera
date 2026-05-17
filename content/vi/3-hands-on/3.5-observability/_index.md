---
title: "3.5 Observability"
date: 2025-01-01
weight: 5
---

## Mục tiêu phần này

Deploy CloudWatch dashboard `hera-prod` (5 panels) + 2 op alarms + 1 billing alarm cross-region (us-east-1) để theo dõi traffic, latency, error rate, Bedrock cost, và estimated charges của agent + widget. Module observability ship `infra/modules/observability/` (4-file shape) — region default `ap-northeast-1` cho mọi alarm/metric trừ billing alarm (us-east-1 cross-region constraint).

## Pre-flight: bật Receive Billing Alerts (one-time)

![CloudWatch Billing Preferences — Receive Billing Alerts toggle](/images/3.5-observability/billing-alerts-toggle.png)

Steps:

1. Mở `https://console.aws.amazon.com/billing/home#/preferences`.
2. Edit Alert preferences → tick "Receive CloudWatch Billing Alerts" → Save.
3. Wait ~15 phút để billing data start flowing vào CloudWatch.

*Source: RUNBOOK.md (Phase 4 Pre-flight) — Phase 4 Plan 04-02*

Note quan trọng: chưa tick → `terraform apply` vẫn pass và `hera-billing-prod` alarm vẫn được tạo, nhưng alarm sẽ ở `INSUFFICIENT_DATA` mãi (không phải bug). Đây là per-AWS-account toggle, không phải per-region. Một lần tick là xong cho mọi region/workshop session sau này.

## Bước 1: terraform apply observability module

```bash
RUNTIME_ARN=$(jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json)
(cd infra/envs/prod && terraform init -upgrade)
(cd infra/envs/prod && terraform apply -var="agentcore_runtime_arn=$RUNTIME_ARN")
```

*Source: RUNBOOK.md (Phase 4 Observability Apply) — Phase 4 Plan 04-02*

Module `infra/modules/observability/` ship 4-file shape (versions/variables/main/outputs) với `configuration_aliases=[aws.us_east_1]` để billing alarm có thể tạo ở us-east-1 từ ap-northeast-1 prod root (AWS/Billing namespace chỉ emit metric ở us-east-1). Var `agentcore_runtime_arn` pass-through giữ `widget_presigner` Lambda env var đúng (D-25 4-step lifecycle giữ nguyên — quan trọng vì terraform apply không -var sẽ revert ARN xuống empty-string default và break presigner).

Expected plan: 4 to add (1 dashboard + 3 alarms). In-place changes không liên quan (CloudFront `MinimumProtocolVersion` auto-bump TLSv1 -> TLSv1.2_2021, S3 bucket policy provider re-encoding) — benign drift, accept.

## Bước 2: Mở dashboard và walk-through 5 panels

```bash
(cd infra/envs/prod && terraform output -raw observability_dashboard_url)
```

*Source: RUNBOOK.md (Phase 4 Dashboard walkthrough) — Phase 4 Plan 04-02*

![CloudWatch Dashboard hera-prod — 5 panels populated](/images/3.5-observability/cloudwatch-dashboard-hera-prod.png)

5 panels (left-to-right, top-to-bottom):

| # | Panel | Metric | Visualization | Note |
|---|-------|--------|---------------|------|
| 1 | Active sessions | AgentCore `ActiveStreamingConnections` 1-min sum | singleValue | Updates live during voice session |
| 2 | Latency p50 / p95 | AgentCore `Latency` end-to-end ms | timeSeries | extended_statistic p50 + p95 |
| 3 | Error rate | `100 * TotalErrors / Invocations` | timeSeries | metric_query arithmetic — returns 0 khi no invocations |
| 4 | Bedrock invocations + tokens | `AWS/Bedrock` `Invocations` + `InputTokenCount` + `OutputTokenCount` cho `amazon.nova-sonic-v1:0` | timeSeries | proxy for cost |
| 5 | Estimated charges | `AWS/Billing` `EstimatedCharges` `Currency=USD` | singleValue (us-east-1 cross-region) | updated mỗi 6 giờ |

"No data available" trên fresh dashboard là expected — fire vài voice session ở widget URL Phần 3.4 để populate panel 1-4. Bedrock cost panel mất tới 24h để start populate sau invoke đầu tiên.

## Alarms (3 cái)

| Alarm name | Region | Threshold | Period | Action |
|------------|--------|-----------|--------|--------|
| `hera-error-rate-prod` | ap-northeast-1 | error rate > 5% | 5 min | alarm_actions=[] (D-35) |
| `hera-latency-p95-prod` | ap-northeast-1 | latency p95 > 5000ms | 5 min | alarm_actions=[] |
| `hera-billing-prod` | us-east-1 (cross-region) | EstimatedCharges > $5/day (D-29) | 6h | alarm_actions=[] |

*Source: infra/modules/observability/main.tf — Phase 4 Plan 04-02*

`alarm_actions=[]` per D-35 — không SNS topic, không email subscription, không Lambda hook auto-stop. Trade-off accepted: instructor monitor dashboard tay; manual-stop fallback ở section dưới.

Billing alarm cross-region constraint: `AWS/Billing` namespace CHỈ emit ở us-east-1; observability module dùng provider alias `aws.us_east_1` để tạo alarm ở us-east-1 từ prod root chạy ở ap-northeast-1. Đây là AWS service constraint, không phải tradeoff.

{{% notice warning %}}
**Billing alarm có 24h propagation lag:** dù `aws cloudwatch describe-alarms` trả về alarm ngay sau apply, `EstimatedCharges` metric có thể mất 6-24 giờ để start populate (AWS service constraint). Trong workshop session 2 giờ, alarm gần như chắc chắn ở `INSUFFICIENT_DATA` đến hết session — KHÔNG phải bug. Nếu bạn cần test thực tế, deploy sáng nay rồi check sáng mai. Đồng thời: bạn phải đã tick "Receive CloudWatch Billing Alerts" ở Pre-flight section trên — chưa tick thì alarm `INSUFFICIENT_DATA` mãi mãi.

*Source: RUNBOOK.md (Phase 4 Observability Pre-flight) — Phase 4 Plan 04-02*
{{% /notice %}}

## OBS-04 trade-off — không có per-IP rate limit (D-36)

- Presigner Lambda Function URL OPEN (không per-IP rate limit, không WAF rule).
- Effective rate-limit gate: AgentCore Runtime concurrency cap (default 10, instructor demo cap=2 D-30 — Phần 3.3 Bước 0). Abuse via cached URL replay → 503 từ runtime sau khi cap hit.
- KHÔNG ship cho v1 workshop:
  - AWS WAF rate-based rule trên CloudFront (~$5/tháng base — out of demo budget per D-54).
  - DynamoDB token-bucket Lambda (added complexity for marginal benefit at 2-session cap).
- Trade-off accepted: presigner open; AgentCore concurrency là gate. v2 với real public traffic → add WAF hoặc token-bucket — explicitly out of scope per D-36.

*Source: RUNBOOK.md (Phase 4 OBS-04 trade-off) — Phase 4 Plan 04-02*

## OBS-05 trade-off — billing alarm manual-stop fallback (D-35)

Khi alarm transitions to ALARM state (visible trên dashboard billing panel + via `aws cloudwatch describe-alarms`), respond MANUAL — không có SNS hook auto-stop:

```bash
# Resolve <your-runtime-id> first:
#   jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json
# (or read from cdk deploy output captured in Section 3.3 Step 4)
aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id <your-runtime-id> \
  --region ap-northeast-1 \
  --status STOPPED

# Or via CDK destroy (full teardown of just AgentCore):
(cd infra/cdk && uv run cdk destroy hera-agentcore --force)
```

*Source: RUNBOOK.md (Phase 4 OBS-05 trade-off) — Phase 4 Plan 04-02*

Trade-off accepted — instructor monitor dashboard tay, không out-of-band notification. v2 với real public traffic → add SNS topic + email subscription + (optional) Lambda hook để automate — explicitly out of scope per D-35.

## Live evidence (instructor reference)

- Dashboard URL: resolve qua `terraform -chdir=infra/envs/prod output -raw observability_dashboard_url` (hoặc `aws cloudwatch get-dashboard --dashboard-name hera-prod --query DashboardArn --output text` rồi build console URL `https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=hera-prod`).
- Free tier: 1 dashboard + 10 alarms = $0/tháng (instructor verified Phase 4 Plan 04-02).
- Bedrock cost panel mất tới 24h start populate sau invoke đầu — fresh "No data available" là expected.
- Instructor's billing alarm sit `INSUFFICIENT_DATA` đến khi RESEARCH A1 toggle tick (carried trong 04-HUMAN-UAT.md item #2).

## Tuỳ chọn nâng cao: Langfuse waterfall trace

CloudWatch dashboard + alarm cover được latency/error/cost ở mức metric, nhưng không cho thấy **waterfall trace** cho từng voice session (session → tool call → KB Retrieve → S3 Vectors). Phần này thêm Langfuse (free tier 50k events/tháng) để có UI per-session.

Không bắt buộc — workshop core hoàn chỉnh ngay cả khi skip phần này.

### Bước 1: Tạo Langfuse project + lấy API keys

1. Sign up tại `https://cloud.langfuse.com/` (Google/GitHub/email).
2. Create new project → đặt tên (vd `hera-voice-agent`) → chọn region:
   - EU: `https://cloud.langfuse.com`
   - US: `https://us.cloud.langfuse.com` (latency gần `ap-northeast-1` hơn)
3. Project Settings → API Keys → Create new API keys → copy:
   - `LANGFUSE_PUBLIC_KEY=pk-lf-...`
   - `LANGFUSE_SECRET_KEY=sk-lf-...` (chỉ hiện 1 lần — lưu lại)

### Bước 2: Set 3 env vars trên AgentCore Runtime

```bash
PUB="pk-lf-..."
SEC="sk-lf-..."
HOST="https://cloud.langfuse.com"   # hoặc US endpoint

IMG=$(aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id <your-runtime-id> --region ap-northeast-1 \
  --query 'agentRuntimeArtifact.containerConfiguration.containerUri' --output text)

aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id <your-runtime-id> \
  --region ap-northeast-1 \
  --agent-runtime-artifact "containerConfiguration={containerUri=$IMG}" \
  --role-arn arn:aws:iam::<your-account-id>:role/hera-agentcore-exec-prod \
  --network-configuration networkMode=PUBLIC \
  --protocol-configuration serverProtocol=HTTP \
  --environment-variables "HERA_LOG_GROUP=/aws/bedrock-agentcore/hera-agent,AWS_REGION=ap-northeast-1,HERA_KB_ID=BKXE19AH89,LANGFUSE_PUBLIC_KEY=$PUB,LANGFUSE_SECRET_KEY=$SEC,LANGFUSE_HOST=$HOST"
```

Lưu ý: `update-agent-runtime` là REPLACE chứ không MERGE — phải pass lại tất cả env vars hiện có cộng thêm 3 Langfuse vars. Runtime sẽ `UPDATING` → `READY` trong ~30 giây.

### Bước 3: Test 1 round voice → xem trace

1. Mở widget CloudFront URL → click record → hỏi "Do you have MacBook Pro?".
2. Vào `https://cloud.langfuse.com/` → project → **Tracing** (sidebar trái).
3. Sẽ thấy 1 trace mới với hierarchy:
   ```
   hera-voice-session  (root, metadata: session_id)
   |__ lookup_product  (function span, input=query, output=N chunks)
       |__ kb_retrieve  (custom span, metadata: kb_id, threshold)
   ```

### Disable / rotate keys

- Disable: drop `LANGFUSE_*` khỏi `--environment-variables` (chạy lại update với env list không có Langfuse).
- Rotate: tạo key mới ở Langfuse Settings, chạy lại update với key mới.

Code agent tự skip Langfuse wrappers khi `LANGFUSE_SECRET_KEY` không có — không break voice loop khi tắt trace.

*Source: docs/OBSERVABILITY.md — out-of-band ops doc*

## Tiếp theo

Deploy đầy đủ + observability đã chạy. Phần 4 Cleanup sẽ tear down toàn bộ stack về $0 (cdk destroy → terraform destroy → `bin/cleanup-verify.sh` 19 read-only check) + 24h-deferred Cost Explorer paste-line để verify $0 ongoing cost.
