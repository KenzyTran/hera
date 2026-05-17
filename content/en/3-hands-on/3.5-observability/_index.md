---
title: "3.5 Observability"
date: 2025-01-01
weight: 5
---

## Goal of this section

Deploy the CloudWatch dashboard `hera-prod` (5 panels) + 2 operational alarms + 1 billing alarm cross-region (us-east-1) so you can monitor traffic, latency, error rate, Bedrock cost, and estimated charges of your agent + widget. The observability module ships from `infra/modules/observability/` (4-file shape) — region default `ap-northeast-1` for every alarm/metric except the billing alarm (us-east-1 cross-region constraint).

## Pre-flight: create an AWS Budget with email alert (one-time)

The CloudWatch alarm created by Terraform is dashboard-only — it does not send email. To get a real notification when cost exceeds a threshold, create an **AWS Budget** with an email subscriber. Free tier covers the first 2 budgets.

![AWS Budgets — email alert when cost exceeds threshold (e.g. $5/month)](/images/3.5-observability/billing-alerts-toggle.png)

Steps:

1. Open `https://console.aws.amazon.com/billing/home#/budgets/overview`.
2. Click **Create budget** → choose **Customize (advanced)** → Budget type **Cost budget**.
3. Name the budget, e.g. `hera-monthly-cap`; Budget amount, e.g. `$5` (Monthly recurring).
4. Configure **alert thresholds**: e.g. "Actual cost ≥ 80% of budgeted" → Notification: your email.
5. Save. AWS sends an email the first time cost hits the 80% threshold.

*Source: RUNBOOK.md (Phase 4 Pre-flight) — Phase 4 Plan 04-02*

Note: budgets are per-AWS-account, not per-region. One budget covers every region. The Terraform CloudWatch alarm `hera-billing-prod` is still created alongside (dashboard-visible, no email) — the two layers complement each other.

## Step 1: terraform apply the observability module

```bash
RUNTIME_ARN=$(jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json)
(cd infra/envs/prod && terraform init -upgrade)
(cd infra/envs/prod && terraform apply -var="agentcore_runtime_arn=$RUNTIME_ARN")
```

*Source: RUNBOOK.md (Phase 4 Observability Apply) — Phase 4 Plan 04-02*

The `infra/modules/observability/` module ships in the 4-file shape (versions/variables/main/outputs) with `configuration_aliases=[aws.us_east_1]` so the billing alarm can be created in us-east-1 from an ap-northeast-1 prod root (the AWS/Billing namespace only emits metrics in us-east-1). The `agentcore_runtime_arn` var is pass-through so the `widget_presigner` Lambda env var stays correct (the D-25 4-step lifecycle is preserved — important: a `terraform apply` without `-var` reverts the ARN to the empty-string default and breaks the presigner).

Expected plan: 4 to add (1 dashboard + 3 alarms). Any in-place changes unrelated to the observability module (CloudFront `MinimumProtocolVersion` auto-bump TLSv1 -> TLSv1.2_2021, S3 bucket policy provider re-encoding) are benign drift — accept and continue.

## Step 2: open the dashboard and walk the 5 panels

```bash
(cd infra/envs/prod && terraform output -raw observability_dashboard_url)
```

*Source: RUNBOOK.md (Phase 4 Dashboard walkthrough) — Phase 4 Plan 04-02*

![CloudWatch Dashboard hera-prod — 5 panels populated](/images/3.5-observability/cloudwatch-dashboard-hera-prod.png)

Five panels (left-to-right, top-to-bottom):

| # | Panel | Metric | Visualization | Note |
|---|-------|--------|---------------|------|
| 1 | Active sessions | AgentCore `ActiveStreamingConnections` 1-min sum | singleValue | Updates live during a voice session |
| 2 | Latency p50 / p95 | AgentCore `Latency` end-to-end ms | timeSeries | extended_statistic p50 + p95 |
| 3 | Error rate | `100 * TotalErrors / Invocations` | timeSeries | metric_query arithmetic — returns 0 when no invocations |
| 4 | Bedrock invocations + tokens | `AWS/Bedrock` `Invocations` + `InputTokenCount` + `OutputTokenCount` for `amazon.nova-sonic-v1:0` | timeSeries | proxy for cost |
| 5 | Estimated charges | `AWS/Billing` `EstimatedCharges` `Currency=USD` | singleValue (us-east-1 cross-region) | updated every 6 hours |

"No data available" on a fresh dashboard is expected — fire a few voice sessions on the Section 3.4 widget URL to populate panels 1-4. The Bedrock cost panel takes up to 24h to start populating after the first invoke.

## Alarms (3 of them)

| Alarm name | Region | Threshold | Period | Action |
|------------|--------|-----------|--------|--------|
| `hera-error-rate-prod` | ap-northeast-1 | error rate > 5% | 5 min | alarm_actions=[] (D-35) |
| `hera-latency-p95-prod` | ap-northeast-1 | latency p95 > 5000ms | 5 min | alarm_actions=[] |
| `hera-billing-prod` | us-east-1 (cross-region) | EstimatedCharges > $5/day (D-29) | 6h | alarm_actions=[] |

*Source: infra/modules/observability/main.tf — Phase 4 Plan 04-02*

`alarm_actions=[]` per D-35 — no SNS topic, no email subscription, no Lambda hook auto-stop. Trade-off accepted: the instructor monitors the dashboard manually; the manual-stop fallback is in the section below.

Billing alarm cross-region constraint: the `AWS/Billing` namespace ONLY emits in us-east-1; the observability module uses provider alias `aws.us_east_1` to create the alarm in us-east-1 from a prod root running in ap-northeast-1. This is an AWS service constraint, not a trade-off.

{{% notice warning %}}
**The billing alarm has a 24h propagation lag:** even though `aws cloudwatch describe-alarms` returns the alarm immediately after apply, the `EstimatedCharges` metric can take 6-24 hours to start populating (AWS service constraint). During a 2-hour workshop session, the alarm will almost certainly stay in `INSUFFICIENT_DATA` for the whole session — this is NOT a bug. If you want to test it for real, deploy this morning and check tomorrow morning. Also: you must have ticked "Receive CloudWatch Billing Alerts" in the Pre-flight section above — if you didn't, the alarm sits in `INSUFFICIENT_DATA` forever.

*Source: RUNBOOK.md (Phase 4 Observability Pre-flight) — Phase 4 Plan 04-02*
{{% /notice %}}

## OBS-04 trade-off — no per-IP rate limit (D-36)

- The presigner Lambda Function URL is OPEN (no per-IP rate limit, no WAF rule).
- Effective rate-limit gate: AgentCore Runtime concurrency cap (default 10, instructor demo cap=2 per D-30 — see Section 3.3 Step 0). Abuse via cached URL replay → 503 from the runtime once the cap is hit.
- NOT shipped for v1 workshop:
  - AWS WAF rate-based rule on CloudFront (~$5/month base — out of demo budget per D-54).
  - DynamoDB token-bucket Lambda (added complexity for marginal benefit at the 2-session cap).
- Trade-off accepted: the presigner is open; AgentCore concurrency is the gate. For a v2 with real public traffic, add WAF or a token-bucket — explicitly out of scope per D-36.

*Source: RUNBOOK.md (Phase 4 OBS-04 trade-off) — Phase 4 Plan 04-02*

## OBS-05 trade-off — billing alarm manual-stop fallback (D-35)

When the alarm transitions to ALARM state (visible on the dashboard's billing panel + via `aws cloudwatch describe-alarms`), respond manually — there is no SNS auto-stop hook:

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

Trade-off accepted — the instructor monitors the dashboard manually with no out-of-band notification. For a v2 with real public traffic, add an SNS topic + email subscription + (optional) Lambda hook to automate this — explicitly out of scope per D-35.

## Live evidence (instructor reference)

- Dashboard URL: resolve via `terraform -chdir=infra/envs/prod output -raw observability_dashboard_url` (or `aws cloudwatch get-dashboard --dashboard-name hera-prod --query DashboardArn --output text` then construct the console URL `https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=hera-prod`).
- Free tier: 1 dashboard + 10 alarms = $0/month (instructor verified in Phase 4 Plan 04-02).
- The Bedrock cost panel takes up to 24h to start populating after the first invoke — a fresh "No data available" is expected.
- The instructor's billing alarm sits in `INSUFFICIENT_DATA` until the RESEARCH A1 toggle is ticked (carried in 04-HUMAN-UAT.md item #2).

## X-Ray Service Map (AWS-native trace)

AgentCore Runtime emits one span per WS session into the `aws/spans` log group when you enable CloudWatch Transaction Search + tracing delivery. The spans show up in the CloudWatch Trace Map (formerly X-Ray Service Map) automatically — no application instrumentation required.

![CloudWatch Trace Map — node hera_agent.DEFAULT (BedrockAgentCore Runtime) receiving traffic from Client](/images/3.5-observability/xray-service-map.jpeg)

Setup (one-time per account):

```bash
# 1. Enable Transaction Search (lets X-Ray spans ingest into CloudWatch Logs)
aws logs put-resource-policy --policy-name TransactionSearchXRayAccess --policy-document '{
  "Version":"2012-10-17","Statement":[{
    "Sid":"TransactionSearchXRayAccess","Effect":"Allow",
    "Principal":{"Service":"xray.amazonaws.com"},
    "Action":"logs:PutLogEvents",
    "Resource":["arn:aws:logs:ap-northeast-1:<account-id>:log-group:aws/spans:*"]
  }]}'
aws xray update-trace-segment-destination --destination CloudWatchLogs --region ap-northeast-1

# 2. Enable trace delivery for the runtime (once per runtime)
aws logs put-delivery-source --name hera-runtime-traces-source --log-type TRACES \
  --resource-arn arn:aws:bedrock-agentcore:ap-northeast-1:<account-id>:runtime/<runtime-id> \
  --region ap-northeast-1
aws logs put-delivery-destination --name hera-runtime-traces-destination \
  --delivery-destination-type XRAY --region ap-northeast-1
aws logs create-delivery --delivery-source-name hera-runtime-traces-source \
  --delivery-destination-arn arn:aws:logs:ap-northeast-1:<account-id>:delivery-destination:hera-runtime-traces-destination \
  --region ap-northeast-1

# 3. Bump indexing sampling to 100% so every span is searchable in the console
aws xray update-indexing-rule --name Default --rule 'Probabilistic={DesiredSamplingPercentage=100}' --region ap-northeast-1
```

After ~1 minute of testing one voice round, open the [CloudWatch Trace Map console](https://ap-northeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#xray:service-map/map) → you'll see the `hera_agent.DEFAULT` node with traffic and latency averages. Click the node → "View traces" to inspect individual spans (name `AgentCore.Runtime.Invoke`, attributes `session.id`, `latency_ms`, `http.response.status_code`).

Note: AgentCore only emits the **root span** per session — no nested child spans for KB Retrieve / Sonic bidi. For a deeper waterfall, use Langfuse below.

## Optional advanced: Langfuse waterfall trace

The CloudWatch dashboard + alarms cover latency/error/cost at the metric level but do not give you a **waterfall trace** per voice session (session → tool call → KB Retrieve → S3 Vectors). This section adds Langfuse (free tier, 50k events/month) for per-session UI.

Optional — the workshop core is complete even if you skip this.

### Step 1: Create a Langfuse project and grab API keys

1. Sign up at `https://cloud.langfuse.com/` (Google/GitHub/email).
2. Create a new project → give it a name (e.g. `hera-voice-agent`) → pick the region:
   - EU: `https://cloud.langfuse.com`
   - US: `https://us.cloud.langfuse.com` (lower latency from `ap-northeast-1`)
3. Project Settings → API Keys → Create new API keys → copy:
   - `LANGFUSE_PUBLIC_KEY=pk-lf-...`
   - `LANGFUSE_SECRET_KEY=sk-lf-...` (shown only once — store it)

### Step 2: Set the 3 env vars on AgentCore Runtime

```bash
PUB="pk-lf-..."
SEC="sk-lf-..."
HOST="https://cloud.langfuse.com"   # or the US endpoint

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

Note: `update-agent-runtime` is REPLACE, not MERGE — you must repeat all existing env vars together with the 3 new Langfuse vars. The runtime transitions `UPDATING` → `READY` in about 30 seconds.

### Step 3: Test one voice round and view the trace

1. Open the widget CloudFront URL → click record → ask "Do you have MacBook Pro?".
2. Open `https://cloud.langfuse.com/` → your project → **Tracing** (left sidebar).
3. You will see a new trace with this hierarchy:
   ```
   hera-voice-session  (root, metadata: session_id)
   |__ lookup_product  (function span, input=query, output=N chunks)
       |__ kb_retrieve  (custom span, metadata: kb_id, threshold)
   ```

![Langfuse Tracing — waterfall trace hera-voice-session with the kb_retrieve span](/images/3.5-observability/langfuse-trace-view.png)

### Disable / rotate keys

- Disable: drop the `LANGFUSE_*` vars from `--environment-variables` (re-run update without them).
- Rotate: create a new key in Langfuse Settings, re-run update with the new key.

The agent code skips the Langfuse wrappers when `LANGFUSE_SECRET_KEY` is unset — turning tracing off never breaks the voice loop.

*Source: docs/OBSERVABILITY.md — out-of-band ops doc*

## What's next

Deploy is complete and observability is running. Section 4 Cleanup tears the whole stack down to $0 (cdk destroy → terraform destroy → `bin/cleanup-verify.sh` with 19 read-only checks) + a 24h-deferred Cost Explorer paste-line so you can verify $0 ongoing cost.
