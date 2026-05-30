---
title: "3.5 Observability"
date: 2025-01-01
weight: 5
---

## Mục tiêu phần này

Deploy CloudWatch dashboard `hera-prod` (5 panels) + 2 op alarms + 1 billing alarm cross-region (us-east-1) để theo dõi traffic, latency, error rate, Bedrock cost, và estimated charges của agent + widget. Module observability ship `infra/modules/observability/` (4-file shape) — region default `ap-northeast-1` cho mọi alarm/metric trừ billing alarm (us-east-1 cross-region constraint).

## Pre-flight: tạo AWS Budget có email alert (one-time)

CloudWatch alarm trong Terraform chỉ hiện trên dashboard — không gửi email. Để có notification thực sự khi cost vượt ngưỡng, tạo **AWS Budget** với email subscriber. Free tier cho 2 budget đầu, không tốn phí.

![AWS Budgets — alert qua email khi cost vượt ngưỡng (vd $5/tháng)](/images/3.5-observability/billing-alerts-toggle.png)

Steps:

1. Mở `https://console.aws.amazon.com/billing/home#/budgets/overview`.
2. Click **Create budget** → chọn **Customize (advanced)** → Budget type **Cost budget**.
3. Tên budget: vd `hera-monthly-cap`; Budget amount: vd `$5` (Monthly recurring).
4. Configure **alert thresholds**: vd "Actual cost ≥ 80% of budgeted" → Notification: email anh.
5. Save. AWS sẽ gửi email lần đầu khi cost chạm 80% ngưỡng.

*Source: RUNBOOK.md (Phase 4 Pre-flight) — Phase 4 Plan 04-02*

Note: budget là per-AWS-account, không phải per-region. Một lần tạo là cover mọi region. Terraform CloudWatch alarm `hera-billing-prod` vẫn được tạo song song (dashboard-visible, không email) — 2 layer alarm bổ sung nhau.

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

## X-Ray Service Map (AWS-native trace)

AgentCore Runtime tự emit 1 span/WS session vào log group `aws/spans` khi anh enable CloudWatch Transaction Search + tracing delivery. Spans tự xuất hiện trong CloudWatch Trace Map (nguyên là X-Ray Service Map) — không cần code instrumentation thêm.

![CloudWatch Trace Map — node hera_agent.DEFAULT (BedrockAgentCore Runtime) nhận traffic từ Client](/images/3.5-observability/xray-service-map.jpeg)

Setup (one-time per account):

```bash
# 1. Enable Transaction Search (cho phép X-Ray spans ingest vào CloudWatch Logs)
aws logs put-resource-policy --policy-name TransactionSearchXRayAccess --policy-document '{
  "Version":"2012-10-17","Statement":[{
    "Sid":"TransactionSearchXRayAccess","Effect":"Allow",
    "Principal":{"Service":"xray.amazonaws.com"},
    "Action":"logs:PutLogEvents",
    "Resource":["arn:aws:logs:ap-northeast-1:<account-id>:log-group:aws/spans:*"]
  }]}'
aws xray update-trace-segment-destination --destination CloudWatchLogs --region ap-northeast-1

# 2. Bật trace delivery cho runtime (mỗi runtime 1 lần)
aws logs put-delivery-source --name hera-runtime-traces-source --log-type TRACES \
  --resource-arn arn:aws:bedrock-agentcore:ap-northeast-1:<account-id>:runtime/<runtime-id> \
  --region ap-northeast-1
aws logs put-delivery-destination --name hera-runtime-traces-destination \
  --delivery-destination-type XRAY --region ap-northeast-1
aws logs create-delivery --delivery-source-name hera-runtime-traces-source \
  --delivery-destination-arn arn:aws:logs:ap-northeast-1:<account-id>:delivery-destination:hera-runtime-traces-destination \
  --region ap-northeast-1

# 3. Bump indexing sampling lên 100% để mọi span đều search được trên console
aws xray update-indexing-rule --name Default --rule 'Probabilistic={DesiredSamplingPercentage=100}' --region ap-northeast-1
```

Sau ~1 phút khi anh test 1 voice round, mở [CloudWatch Trace Map console](https://ap-northeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#xray:service-map/map) → thấy node `hera_agent.DEFAULT` với traffic + latency averages. Click node → "View traces" để xem từng span (name `AgentCore.Runtime.Invoke`, attribute `session.id`, `latency_ms`, `http.response.status_code`).

Lưu ý: AgentCore chỉ emit **root span** mỗi session, không có nested child span cho KB Retrieve / Sonic bidi. Nếu cần waterfall sâu hơn, dùng Langfuse phía dưới.

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

### Bước 2: Set Langfuse keys + redeploy runtime (cdk deploy)

Key Langfuse được **bake vào container lúc `cdk deploy`** (CDK đọc `LANGFUSE_*` từ shell env). Đây là điểm dễ sai nhất: **đừng** dùng `aws bedrock-agentcore-control update-agent-runtime` để set key — đó là config-only update, **không recycle container**, nên tracing sẽ KHÔNG bật dù env var đã đổi. Phải export key rồi `cdk deploy` lại để container khởi động lại kèm key.

```bash
# 1. Export 3 key vào shell hiện tại (hoặc lưu vào file .env.langfuse rồi `source .env.langfuse`)
export LANGFUSE_PUBLIC_KEY="pk-lf-..."
export LANGFUSE_SECRET_KEY="sk-lf-..."
export LANGFUSE_HOST="https://cloud.langfuse.com"   # hoặc US endpoint

# 2. Redeploy runtime — CDK bake key vào container env; container restart kèm key.
#    Dùng cùng image tag (git SHA hiện tại); chỉ env vars thay đổi, runtime ARN giữ nguyên.
(cd infra/envs/prod && terraform output -json > terraform-outputs.json)
(cd infra/cdk && uv run cdk deploy hera-agentcore \
  --context image_tag=$(git rev-parse --short HEAD) \
  --outputs-file ../../dist/cdk-outputs.json \
  --require-approval never)
```

Xác nhận container đã nuốt key (log init in 1 lần mỗi instance):

```bash
aws logs filter-log-events --log-group-name /aws/bedrock-agentcore/hera-agent \
  --start-time $(($(date +%s)*1000 - 300000)) --region ap-northeast-1 \
  --filter-pattern "Tracing enabled" --query 'events[-1].message' --output text
# Mong đợi: ...Tracing enabled: Pipecat OTEL -> Langfuse (...)
```

{{% notice warning %}}
**Git Bash trên Windows:** lệnh AWS có tham số bắt đầu bằng `/` (như `/aws/bedrock-agentcore/...`) bị Git Bash đổi thành đường dẫn Windows → lỗi `InvalidParameterException`. Thêm `MSYS_NO_PATHCONV=1` trước lệnh: `MSYS_NO_PATHCONV=1 aws logs filter-log-events ...`. PowerShell không bị lỗi này.
{{% /notice %}}

### Bước 3: Test 1 round voice → xem trace

1. Mở widget CloudFront URL → click record → hỏi **câu cụ thể về sản phẩm** để kích hoạt tool, ví dụ "Do you have iPhone 13 Pro Max in stock?". (Câu chào chung chung sẽ không gọi `lookup_product` → không có span tool.)
2. Nói xong → **đóng hẳn tab** (span `conversation` chỉ đóng khi phiên kết thúc) → đợi **~30-60 giây** (Langfuse free tier có ingest lag).
3. Vào `https://cloud.langfuse.com/` → project → **Tracing** (sidebar trái). Bạn sẽ thấy **2 trace** cho cùng một cuộc hội thoại:
   ```
   conversation        (Trace Name: conversation)
   └─ turn (xN)
   lookup_product      (Trace Name: lookup_product)
   └─ kb_retrieve       (input: query, output: {chunks, chars})
   ```
4. Để xem chúng **gộp thành một cuộc hội thoại** (theo `session_id`), mở tab **Sessions** thay vì Tracing.

![Langfuse Tracing — trace conversation + lookup_product/kb_retrieve theo session](/images/3.5-observability/langfuse-trace-view.png)

{{% notice info %}}
**Vì sao là 2 trace, không phải 1 waterfall lồng nhau?** Pipecat dispatch tool handler ngoài OTel context của turn span, nên `lookup_product` thành trace gốc riêng thay vì span con của `conversation`. Code agent gắn `langfuse.session.id` lên cả hai để tab **Sessions** gom chúng lại đúng một cuộc hội thoại. Ngoài ra trace chỉ hiện đầy đủ sau khi phiên đóng (span gốc `conversation` đóng lúc teardown) cộng ingest lag — đừng sốt ruột nếu vài giây đầu chưa thấy.
{{% /notice %}}

### Disable / rotate keys

- **Disable:** deploy lại mà **không** export `LANGFUSE_SECRET_KEY` (mở shell mới, hoặc `unset LANGFUSE_SECRET_KEY` rồi chạy lại `cdk deploy` ở Bước 2). CDK bỏ key khỏi container env → container restart không tracing.
- **Rotate:** tạo key mới ở Langfuse Settings, export key mới, chạy lại `cdk deploy` ở Bước 2.

Code agent tự skip Langfuse wrappers khi `LANGFUSE_SECRET_KEY` không có — không break voice loop khi tắt trace.

*Source: docs/OBSERVABILITY.md — out-of-band ops doc*

## Tiếp theo

Deploy đầy đủ + observability đã chạy. Phần 4 Cleanup sẽ tear down toàn bộ stack về $0 (cdk destroy → terraform destroy → `bin/cleanup-verify.sh` 19 read-only check) + 24h-deferred Cost Explorer paste-line để verify $0 ongoing cost.
