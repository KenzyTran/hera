# Phase 4 Research — Observability, Cost Control, Cleanup

**Researched:** 2026-05-06
**Domain:** AgentCore HTTP protocol bridge + CloudWatch (dashboard / metric / billing alarm) + Cost Explorer + bash AWS-CLI cleanup verification
**Confidence:** HIGH for the protocol-bridge contract (verified against AWS docs + awslabs canonical sample); HIGH for AgentCore-emitted metrics inventory (verified against AWS docs); HIGH for Terraform alarm/dashboard shape (verified against terraform-provider-aws source); MEDIUM for the SC#2 closure smoke probe selection (one [needs-verification] flag noted); HIGH for cleanup-verify CLI commands (verified against AWS CLI reference).

## Executive summary

- **The "/invocations 404" gap is a one-line stub fix, not a refactor.** AgentCore's HTTP protocol contract explicitly allows `/invocations` (HTTP) AND `/ws` (WebSocket) to coexist on the same container at port 8080. The canonical awslabs sample `06-bi-directional-streaming/04-pipecat-sonic-ws/websocket/server.py` ships a stub `POST /invocations` that returns `{"agent": "...", "status": "running", "model": "..."}` and does the real bidi-streaming work on `/ws`. The Pipecat pipeline lifecycle stays per-WebSocket; `/invocations` does NOT need to bridge into the pipeline. This collapses Plan 04-01 into a ~10-line additive change in `agent/hera_agent/main.py` plus image rebuild + 1 cdk deploy.
- **AgentCore Runtime auto-emits a rich set of CloudWatch metrics** under namespace `AWS/Bedrock-AgentCore` (Invocations, Sessions, Throttles, Latency, SystemErrors, UserErrors, TotalErrors, **ActiveStreamingConnections** for WebSocket, plus CPUUsed-vCPUHours / MemoryUsed-GBHours). All five OBS-01 panels (active sessions, latency p50/p95, error rate, Bedrock invocation/cost) can be built **without any app-side PutMetricData** — keeping the agent code unchanged after Plan 04-01.
- **Bedrock model invocations live in the separate `AWS/Bedrock` namespace** (Invocations, InvocationLatency, InputTokenCount, OutputTokenCount, plus the newer TimeToFirstToken). This is a different namespace from AgentCore's, but the dashboard widget can mix both via `metrics: [["AWS/Bedrock-AgentCore", ...], ["AWS/Bedrock", ...]]`.
- **Billing alarms live ONLY in `us-east-1`.** Terraform needs a second `aws` provider alias scoped to `us-east-1`. There is also an account-level toggle ("Receive CloudWatch Billing Alerts" in Billing console → Billing Preferences) that an operator must enable manually before any data lands in `AWS/Billing` `EstimatedCharges`. **[needs-verification]** for this Hera AWS account `851725411875` — the planner should add a RUNBOOK pre-flight check or a one-time operator console click instruction.
- **`bin/cleanup-verify.sh` follows the `bin/verify-kb.sh` pattern verbatim.** Each resource has a documented `aws ... describe|get|list` call whose error name is `ResourceNotFoundException` / `NoSuchEntity` / `NoSuchBucket`. The bash idiom is: capture the call's stderr+stdout, grep for the expected error name → exit 0; if the call succeeds → exit 1 ("leftover detected"). Reuses `bin/verify-kb.sh --invert` mode for the KB itself.

**Primary recommendation:** Wave 1 = Plan 04-01 protocol-bridge solo (~10 LOC + 1 cdk deploy, closes Phase 3 SC#2). Wave 2 = Plan 04-02 observability (Terraform module observability/ + dashboard + 3 alarms) and Plan 04-03 cleanup-verify (bin/cleanup-verify.sh + RUNBOOK Phase 4 sections), parallel — file-disjoint except RUNBOOK heading sections.

## A. Protocol-bridge (Plan 04-01)

### Canonical reference repo

The CONTEXT path was approximately right but the actual repository name is `awslabs/agentcore-samples` (also mirrored as `awslabs/amazon-bedrock-agentcore-samples`). The Pipecat-on-AgentCore Sonic-WS sample directory is at:

```
01-tutorials/01-AgentCore-runtime/06-bi-directional-streaming/04-pipecat-sonic-ws/
├── client/
│   ├── client.py        # signing server (mints presigned wss:// URLs)
│   ├── index.html
│   └── src/app.js
└── websocket/
    ├── server.py        # FastAPI app — THIS IS THE REFERENCE
    └── requirements.txt
```

Authoritative URL: `https://github.com/awslabs/agentcore-samples/tree/main/01-tutorials/01-AgentCore-runtime/06-bi-directional-streaming/04-pipecat-sonic-ws`.

Sibling samples (for cross-reference): `01-bedrock-sonic-ws` (raw Sonic), `02-strands-ws` (Strands), `03-langchain-transcribe-polly-ws` (LangChain). All four follow the same FastAPI + IMDS-credential + `/ping` + `/invocations` + `/ws` shape.

### `/invocations` route shape — VERBATIM from canonical sample

Quoted directly from `websocket/server.py` in the awslabs Pipecat sample:

```python
@app.get("/ping")
async def ping():
    return JSONResponse({"status": "healthy"})


@app.post("/invocations")
async def invocations():
    return JSONResponse(
        {
            "agent": "pipecat-nova-sonic",
            "status": "running",
            "model": "amazon.nova-2-sonic-v1:0",
        }
    )


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    # ... full Pipecat pipeline construction ...
    runner = PipelineRunner(handle_sigint=False)
    await runner.run(task)
```

**Key insight (HIGH confidence):** The canonical sample treats `/invocations` as a **status stub** — it returns 200 with a JSON envelope describing the agent, but does NOT bridge into the Pipecat pipeline. The bidi voice loop runs entirely over `/ws`. AgentCore's HTTP protocol layer is satisfied as long as `/invocations` returns a 200 response that conforms to the `application/json` content type expectation. A presigned WSS connection then upgrades through `/ws` independently.

This means **Plan 04-01 does NOT need to refactor the Pipecat pipeline** — it is a purely additive route stub that closes the 404. The existing `/ws` path Phase 2 ships continues to handle the voice loop verbatim.

### AgentCore HTTP protocol contract — `/ping` + `/invocations` requirements

Source: AWS docs `runtime-http-protocol-contract.html` (verbatim quoted below).

**Container requirements:**
- **Host:** `0.0.0.0`
- **Port:** `8080`
- **Platform:** ARM64 (Hera ships multi-arch which satisfies this)

**Quote: "Both HTTP (`/invocations`) and WebSocket (`/ws`) endpoints can be deployed on the same container using port 8080, allowing a single agent implementation to support both traditional API interactions and real-time bidirectional streaming."**

**`/ping` (GET) requirements:**
- Content-Type: `application/json`
- HTTP Status: `200` for healthy
- Body: `{"status": "Healthy" | "HealthyBusy", "time_of_last_update": <unix_timestamp>}`
- Hera's existing `/ping` already satisfies this (Phase 2 baseline; quote: `{"status": "Healthy", "time_of_last_update": _BOOT_TIME}`).

**`/invocations` (POST) requirements:**
- Content-Type for request: `application/json`
- Example request body shape from docs: `{"prompt": "What's the weather today?"}`
- Response Content-Type: `application/json` (non-streaming) OR `text/event-stream` (SSE streaming)
- Response status: 200

**`/ws` (WebSocket) — Optional per docs.** Headers AgentCore injects on the WebSocket upgrade include `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id`. The /ws path is what Hera already uses for the voice loop.

**Headers AgentCore injects on `/invocations` requests** (from `API_InvokeAgentRuntime.html` Request Syntax):

```
POST /runtimes/{agentRuntimeArn}/invocations?accountId=...&qualifier=... HTTP/1.1
Content-Type: <contentType>
Accept: <accept>
X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: <runtimeSessionId>
X-Amzn-Bedrock-AgentCore-Runtime-User-Id: <runtimeUserId>
X-Amzn-Trace-Id: <traceId>
traceparent / tracestate / baggage  (W3C distributed tracing)
Mcp-Session-Id / Mcp-Protocol-Version  (only if MCP protocol)

<payload>  (binary, up to 100 MB)
```

For the Hera stub, none of these headers need to be parsed — the FastAPI handler can ignore them and return a fixed 200 JSON body.

### AgentCore data-plane invoke API — LATEST verb names + smoke-probe payload

Two sibling APIs exist in the `bedrock-agentcore` data plane (verified against `boto3` 1.42 docs and AWS CLI 2.34.38 reference):

| API | Use case | What it talks to |
|-----|----------|-------------------|
| `InvokeAgentRuntime` | Synchronous HTTP request/response (with optional SSE streaming) | Container's `POST /invocations` |
| `InvokeAgentRuntimeWithWebSocketStream` | Bidirectional WebSocket streaming | Container's WebSocket upgrade path |

The IAM action names mirror the API names: `bedrock-agentcore:InvokeAgentRuntime` and `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream`. Plan 03-04 already grants both on the presigner Lambda role (live, scoped to the runtime ARN).

**For the Phase 3 SC#2 closure smoke probe (D-34), use `InvokeAgentRuntime`** — the synchronous HTTP path. This is the cleanest single-shot 200 assertion against the live runtime that proves `/invocations` exists. Trying to use `InvokeAgentRuntimeWithWebSocketStream` for SC#2 closure would re-test the path Plan 03-04's `bin/_smoke_deploy_probe.py` already validated (SigV4 + WSS handshake) without actually proving the new HTTP route works.

**AWS CLI form** (verbatim from `aws bedrock-agentcore invoke-agent-runtime` reference):

```bash
aws bedrock-agentcore invoke-agent-runtime \
  --region ap-northeast-1 \
  --agent-runtime-arn "arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD" \
  --payload '{"prompt":"healthcheck"}' \
  --content-type application/json \
  --accept application/json \
  /tmp/agentcore-response.json
```

(The trailing positional `<outfile>` is mandatory — the response body is streamed to that file. `--payload` accepts a blob; for a small JSON literal it can be passed inline; for binary, `fileb://path/to/file` works.)

The smoke probe asserts:
- Exit code 0 from the CLI (transport succeeded).
- HTTP `statusCode` field in the parsed response = 200.
- `response` body is a JSON object with `"status": "running"` (matching the stub from Plan 04-01).

**[needs-verification]** Whether the live `bedrock-agentcore-control` IAM policy on the Hera operator's CLI credentials grants `bedrock-agentcore:InvokeAgentRuntime` outside the presigner Lambda's scoped policy. If the smoke is run under operator root credentials, this is moot. If under a non-root operator profile, Phase 4 RUNBOOK should document the IAM grant requirement.

### Pipeline lifecycle — recommendation

**Recommendation: do NOT bridge `/invocations` into the Pipecat pipeline.** Keep the existing per-WebSocket pipeline lifecycle (`/ws` → fresh `PipelineTask` per connection — Phase 2 D-21) intact. `/invocations` is a stub returning `{"agent": "hera-agent", "status": "running", "model": "amazon.nova-sonic-v2:0"}`.

**Rationale:**
1. The canonical awslabs Pipecat-on-AgentCore sample does exactly this — `/invocations` is a status endpoint, voice runs on `/ws`.
2. Pipecat's pipeline is designed around long-lived bidirectional transports (FastAPIWebsocketTransport). Forcing it into one-shot HTTP request/response semantics would require a significant refactor (synthetic frame source/sink, pipeline pump, response collector) for no functional gain — AgentCore already routes through to `/ws` on the same container.
3. Sonic's 8-min stream cap is irrelevant on `/invocations` — the stub returns synchronously in milliseconds.
4. Demo budget honored — no per-request pipeline construction overhead, no Sonic spend per `/invocations` call.

The widget continues to use the presign → WSS → `/ws` flow Plan 03-04 ships. AgentCore's data-plane health probes hit `/invocations` and get a fast 200; the actual voice loop rides `/ws` exactly as before.

## B. CloudWatch dashboard (OBS-01)

### AgentCore-emitted metrics inventory — namespace `AWS/Bedrock-AgentCore`

Source: AWS docs `observability-runtime-metrics.html` (verbatim quoted, 2026-05-06):

| Metric | Auto-emitted? | Dimensions | Unit | OBS-01 panel mapping |
|--------|--------------|-----------|------|--------------------|
| `Invocations` | YES | per resource (agent runtime) | Count | "Invocation count" panel |
| `Invocations (aggregated)` | YES | account-level | Count | (alternative to per-resource) |
| `Throttles` | YES | per resource | Count | (input to error-rate alarm) |
| `SystemErrors` | YES | per resource | Count | (input to error-rate alarm) |
| `UserErrors` | YES | per resource | Count | (input to error-rate alarm) |
| `TotalErrors` | YES | per resource | Count or % | "Error rate" panel (% of invocations) |
| `Latency` | YES | per resource | Milliseconds | "Latency p50 / p95" panel via `extended_statistic = "p50" / "p95"` |
| `Session Count` | YES | per resource | Count | "Active sessions" panel |
| `Sessions (aggregated)` | YES | account-level | Count | (alternative) |
| `ActiveStreamingConnections` | YES (WebSocket only — Hera uses WSS) | per agent | Count | Best fit for "active session count" — 1-min Sum is the meaningful stat |
| `InboundStreamingBytesProcessed` | YES (WebSocket only) | per agent | Bytes | Throughput panel (optional) |
| `OutboundStreamingBytesProcessed` | YES (WebSocket only) | per agent | Bytes | Throughput panel (optional) |
| `CPUUsed-vCPUHours` | YES (vended, 1-min resolution) | Service / Service+Resource / Service+Resource+Name | vCPU-Hours | Resource usage panel (optional) |
| `MemoryUsed-GBHours` | YES (vended, 1-min resolution) | Service / Service+Resource / Service+Resource+Name | GB-Hours | Resource usage panel (optional) |

**App-level PutMetric required: NO.** All five OBS-01 panels are buildable purely from auto-emitted metrics. The Hera agent code does NOT need any new instrumentation. (This honors the Plan 04-01 scope = agent/ + RUNBOOK.md only — no app-side metric writes.)

**Doc verbatim quote on Latency:** *"The total time elapsed between receiving the request and sending the final response token. Represents complete end-to-end processing time of the request."* For utterance-to-first-audio specifically, the Bedrock-side metric `TimeToFirstToken` (under `AWS/Bedrock` namespace, emitted by `InvokeModelWithBidirectionalStream`) is the closest match — see Bedrock metrics below.

### Bedrock metrics inventory — namespace `AWS/Bedrock`

Source: AWS docs `monitoring.html`, AWS blog "Improve operational visibility for inference workloads on Amazon Bedrock with new CloudWatch metrics for TTFT and Estimated Quota Consumption" (2026), and `monitoring-agents-cw-metrics.html`.

| Metric | Dimensions | OBS-01 mapping |
|--------|-----------|----------------|
| `Invocations` | `ModelId` | "Bedrock invocation count" panel — filter to `amazon.nova-sonic-v2:0` (or whatever the verified Sonic model id is at smoke time) |
| `InvocationLatency` | `ModelId` | (alternative latency panel; AgentCore's `Latency` covers end-to-end) |
| `InvocationClientErrors` | `ModelId` | (input to error-rate cross-check) |
| `InvocationThrottles` | `ModelId` | (input to error-rate cross-check) |
| `InputTokenCount` | `ModelId` | "Bedrock cost" proxy (token volume × per-token price) |
| `OutputTokenCount` | `ModelId` | "Bedrock cost" proxy (output tokens are the dominant cost on Sonic) |
| `TimeToFirstToken` | `ModelId` (streaming APIs only — `ConverseStream`, `InvokeModelWithResponseStream`) | Best fit for "utterance → first audio chunk latency" panel |

**[needs-verification]:** `TimeToFirstToken` doc says it is emitted for `ConverseStream` + `InvokeModelWithResponseStream`. Pipecat's `AWSNovaSonicLLMService` uses `InvokeModelWithBidirectionalStream` (the bidi-streaming API). It is unclear from public docs whether `TimeToFirstToken` is also emitted for the bidi-streaming variant. The dashboard should INCLUDE this metric panel — if the metric is empty in production, the planner can either swap to AgentCore's `Latency` p50/p95 or accept that latency-to-first-audio is best measured via app-side timing if needed (out of Plan 04-01 scope).

**Cost panel — true cost has 24h ingestion lag.** AWS Cost Explorer cost-by-service is the only authoritative source for "Bedrock cost", but it has a 24h lag and a $0.01/request fee. For the dashboard, the recommended pattern is:
- A "Token volume" panel (Bedrock InputTokenCount + OutputTokenCount summed over the period) as a near-real-time proxy.
- A separate dashboard text widget pointing the operator to the RUNBOOK 24h-deferred Cost Explorer paste-line for actual dollars.

### Latest `aws_cloudwatch_dashboard` shape (Terraform 6.27)

Source: terraform-provider-aws `cloudwatch_dashboard.html.markdown` + AWS docs `CloudWatch-Dashboard-Body-Structure.html`. Verified 2026-05-06.

The resource schema is unchanged from earlier major versions:

```hcl
resource "aws_cloudwatch_dashboard" "hera" {
  dashboard_name = "hera-overview-prod"
  dashboard_body = jsonencode({
    widgets = [
      # ... (see body below)
    ]
  })
}
```

`dashboard_body` is a string of JSON. `jsonencode()` is the standard idiom. The grid is 24 columns wide; widgets are positioned via `x`, `y`, `width`, `height`.

### Sample `dashboard_body` for OBS-01 (single value + line graph + cross-region billing)

```json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0, "y": 0, "width": 6, "height": 6,
      "properties": {
        "title": "Active sessions (1-min sum)",
        "metrics": [
          ["AWS/Bedrock-AgentCore", "ActiveStreamingConnections",
           "Resource", "arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD"]
        ],
        "view": "singleValue",
        "stat": "Sum",
        "period": 60,
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 6, "y": 0, "width": 12, "height": 6,
      "properties": {
        "title": "Latency p50 / p95",
        "metrics": [
          ["AWS/Bedrock-AgentCore", "Latency", "Resource",
           "arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD",
           {"stat": "p50", "label": "p50"}],
          ["...",                                           {"stat": "p95", "label": "p95"}]
        ],
        "view": "timeSeries",
        "period": 60,
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 6, "width": 12, "height": 6,
      "properties": {
        "title": "Error rate (TotalErrors / Invocations)",
        "metrics": [
          [{"expression": "100*m2/m1", "label": "Error rate %", "id": "e1"}],
          ["AWS/Bedrock-AgentCore", "Invocations", "Resource", "...", {"id": "m1", "visible": false}],
          ["AWS/Bedrock-AgentCore", "TotalErrors", "Resource", "...", {"id": "m2", "visible": false}]
        ],
        "view": "timeSeries",
        "period": 60,
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 6, "width": 12, "height": 6,
      "properties": {
        "title": "Bedrock invocations + token volume",
        "metrics": [
          ["AWS/Bedrock", "Invocations", "ModelId", "amazon.nova-sonic-v2:0"],
          [".", "InputTokenCount", ".", "."],
          [".", "OutputTokenCount", ".", "."]
        ],
        "view": "timeSeries",
        "period": 300,
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 12, "width": 24, "height": 6,
      "properties": {
        "title": "Estimated charges (USD, us-east-1, AWS/Billing)",
        "metrics": [
          ["AWS/Billing", "EstimatedCharges", "Currency", "USD"]
        ],
        "view": "timeSeries",
        "stat": "Maximum",
        "period": 21600,
        "region": "us-east-1"
      }
    }
  ]
}
```

**Cross-region widget pattern** — the `region` property at the **widget level** is what makes a single dashboard span multiple regions. The dashboard resource itself lives in one region (recommend `ap-northeast-1` to keep it co-located with the agent), but each widget can pull from a different region. The billing widget pulls from `us-east-1` because that's the only region `AWS/Billing` is published in (see Section C).

## C. CloudWatch alarms (OBS-02 + OBS-03)

### Operational alarm shapes (OBS-02)

Source: terraform-provider-aws `cloudwatch_metric_alarm.html.markdown` (verbatim, 2026-05-06).

**Error rate >5% over 5 min** — uses `metric_query` with arithmetic expression:

```hcl
resource "aws_cloudwatch_metric_alarm" "hera_error_rate" {
  alarm_name          = "hera-error-rate-prod"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5.0
  alarm_description   = "AgentCore error rate > 5% over 5 minutes"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e1"
    expression  = "IF(m1 > 0, 100*m2/m1, 0)"
    label       = "Error rate %"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Bedrock-AgentCore"
      period      = 300
      stat        = "Sum"
      dimensions  = { Resource = var.agentcore_runtime_arn }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "TotalErrors"
      namespace   = "AWS/Bedrock-AgentCore"
      period      = 300
      stat        = "Sum"
      dimensions  = { Resource = var.agentcore_runtime_arn }
    }
  }
}
```

**Latency p95 >5s over 5 min** — uses `extended_statistic`:

```hcl
resource "aws_cloudwatch_metric_alarm" "hera_latency_p95" {
  alarm_name          = "hera-latency-p95-prod"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5000           # milliseconds
  alarm_description   = "AgentCore p95 latency > 5s over 5 minutes"
  treat_missing_data  = "notBreaching"

  metric_name        = "Latency"
  namespace          = "AWS/Bedrock-AgentCore"
  period             = 300
  extended_statistic = "p95"
  dimensions         = { Resource = var.agentcore_runtime_arn }
}
```

**Notes from the doc verbatim:**
- *"You cannot create a metric alarm consisting of both `statistic` and `extended_statistic` parameters. You must choose one or the other."* — for latency p95 use `extended_statistic`; do NOT also set `statistic`.
- *"Specify exactly one `metric_query` to be `true` to use that `metric_query` result as the alarm."* — `return_data = true` on the expression, false (or omitted) on the inputs.
- *"If you specify at least one `metric_query`, you may not specify a `metric_name`, `namespace`, `period` or `statistic`."* — for the error-rate alarm, those fields move INTO the inner `metric { ... }` blocks.

`treat_missing_data` valid values: `missing`, `ignore`, `breaching`, `notBreaching`. Default is `missing`. Recommend `notBreaching` for both alarms — Hera is a sparse-traffic demo; alarming on missing data would create false positives.

`evaluation_periods = 1` with `period = 300` matches "over 5 minutes" verbatim. The alternative (`evaluation_periods = 5` with `period = 60`) is noisier on a low-traffic demo because each minute gets evaluated independently.

**No alarm actions.** Per D-35, neither alarm has an SNS topic action — they exist purely to display state on the dashboard. Leave `alarm_actions = []` (or omit the argument).

### Billing alarm shape (OBS-03)

Source: AWS docs `monitor_estimated_charges_with_cloudwatch.html` (verbatim) + Terraform pattern from `binbashar/terraform-aws-cost-billing-alarm`.

```hcl
# In infra/envs/prod/main.tf — declare the second provider alias:
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# In infra/modules/observability/main.tf — receive the aliased provider:
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.27"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "hera_billing" {
  provider = aws.us_east_1                # MUST be us-east-1

  alarm_name          = "hera-billing-prod"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5.0               # USD per D-29 banner copy
  alarm_description   = "Estimated AWS charges > $5/day cap"
  treat_missing_data  = "missing"

  metric_name = "EstimatedCharges"
  namespace   = "AWS/Billing"
  period      = 21600                     # 6 hours — minimum supported by AWS/Billing
  statistic   = "Maximum"
  dimensions  = { Currency = "USD" }
}
```

**Verbatim from AWS docs:** *"Billing metric data is stored in the US East (N. Virginia) Region and represents worldwide charges."* and the recommended period is 6 hours (21600 seconds) with statistic `Maximum`.

**Account-level "Receive Billing Alerts" toggle — REQUIRED, manual operator step.** Verbatim from the docs: *"Before you can create an alarm for your estimated charges, you must enable billing alerts."* The procedure:

1. Open Billing console → **Billing Preferences**.
2. Under **Alert preferences**, choose **Edit**.
3. Choose **Receive CloudWatch Billing Alerts**.
4. Choose **Save preferences**.

After enabling, AWS docs say *"it takes about 15 minutes before you can view billing data and set billing alarms."* The Terraform alarm resource will deploy successfully even without the toggle, but the alarm will sit in `INSUFFICIENT_DATA` state until billing data starts flowing.

**[needs-verification]** for account `851725411875` — the planner should add a RUNBOOK pre-flight check ("aws ce get-cost-and-usage returns rows" or just instruct operator: "Tick 'Receive CloudWatch Billing Alerts' once before deploy"). There is no AWS API to query the toggle's state programmatically.

### Dimensions on `AWS/Billing`

Verified from AWS docs:
- `Currency` (always `USD` for the per-account total in `EstimatedCharges`)
- `ServiceName` (optional — to alarm on per-service spend, e.g., `AmazonBedrock`)
- `LinkedAccount` (only meaningful for consolidated billing)

For the Hera $5/day cap, `Currency = "USD"` alone is correct — it covers worldwide spend across all services. A per-service `ServiceName=AmazonBedrock` alarm could be added later but is out of D-35 scope.

## D. cleanup-verify.sh patterns

### Per-resource read-only command + expected exit signal

Source: AWS CLI 2.34 reference, verified for each resource type 2026-05-06.

| Resource (D-37) | Read-only verify command | Expected error name (success = leftover gone) |
|------------------|--------------------------|------------------------------------------------|
| Bedrock KB `BKXE19AH89` | `aws bedrock-agent get-knowledge-base --knowledge-base-id BKXE19AH89 --region ap-northeast-1` | `ResourceNotFoundException` |
| KB data source | (covered by KB get above; data sources die when KB dies) | (n/a) |
| S3 Vectors index `hera-kb-index` | `aws s3vectors get-index --vector-bucket-name hera-kb-vectors-prod --index-name hera-kb-index --region ap-northeast-1` | `NotFoundException` or `ResourceNotFoundException` |
| S3 Vectors bucket `hera-kb-vectors-prod` | `aws s3vectors get-vector-bucket --vector-bucket-name hera-kb-vectors-prod --region ap-northeast-1` | `NotFoundException` |
| AgentCore Runtime `hera_agent-GIsf2P4ImD` | `aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id hera_agent-GIsf2P4ImD --region ap-northeast-1` | `ResourceNotFoundException` |
| CDK CFn stack `hera-agentcore` | `aws cloudformation describe-stacks --stack-name hera-agentcore --region ap-northeast-1` | `Stack with id hera-agentcore does not exist` (ValidationError) |
| CW log group `/aws/bedrock-agentcore/hera-agent` | `aws logs describe-log-groups --log-group-name-prefix /aws/bedrock-agentcore/hera-agent --region ap-northeast-1 --query 'logGroups | length(@)'` | Returns `0` (success) instead of `>0` |
| IAM role `hera-agentcore-exec-prod` | `aws iam get-role --role-name hera-agentcore-exec-prod` | `NoSuchEntity` |
| IAM role `hera-widget-presign-prod-exec` | `aws iam get-role --role-name hera-widget-presign-prod-exec` | `NoSuchEntity` |
| IAM policy `hera-kb-retrieve-prod` | `aws iam list-policies --scope Local --query "Policies[?PolicyName=='hera-kb-retrieve-prod'] | length(@)"` | Returns `0` |
| KB service role | `aws iam get-role --role-name <kb-service-role-name>` (resolve from `terraform output kb_service_role_name` if available, otherwise `hera-kb-service-prod` per D-12 naming) | `NoSuchEntity` |
| ECR repo `hera-agent` | `aws ecr describe-repositories --repository-names hera-agent --region ap-northeast-1` | `RepositoryNotFoundException` |
| CloudFront dist `E10K3B1L8PQ9EC` | `aws cloudfront get-distribution --id E10K3B1L8PQ9EC` | `NoSuchDistribution` |
| S3 widget bucket `hera-widget-prod` | `aws s3api head-bucket --bucket hera-widget-prod --region ap-northeast-1` | `Not Found` (404) — head-bucket exits 254 with stderr "Not Found" |
| S3 source/markdown bucket `hera-source-prod` (from `terraform output source_bucket_name`) | `aws s3api head-bucket --bucket <name> --region ap-northeast-1` | `Not Found` |
| Lambda `hera-widget-presign-prod` | `aws lambda get-function --function-name hera-widget-presign-prod --region ap-northeast-1` | `ResourceNotFoundException` |
| Lambda Function URL config | (covered by `get-function` — when function is gone, FU is gone) | (n/a) |
| CW log group `/aws/lambda/hera-widget-presign-prod` | `aws logs describe-log-groups --log-group-name-prefix /aws/lambda/hera-widget-presign-prod --query 'logGroups | length(@)'` | Returns `0` |
| Billing alarm `hera-billing-prod` | `aws cloudwatch describe-alarms --alarm-names hera-billing-prod --region us-east-1 --query 'MetricAlarms | length(@)'` | Returns `0` |
| Operational alarms (`hera-error-rate-prod`, `hera-latency-p95-prod`) | Same shape, `--region ap-northeast-1` | Returns `0` |
| Dashboard `hera-overview-prod` | `aws cloudwatch get-dashboard --dashboard-name hera-overview-prod --region ap-northeast-1` | `ResourceNotFound` |

### Bash idiom for "expect NotFound" (aligned with `bin/verify-kb.sh`)

The existing `bin/verify-kb.sh --invert` pattern (lines 85-91) shows the idiom:

```bash
RESP=$(aws bedrock-agent get-knowledge-base \
  --knowledge-base-id BKXE19AH89 --region ap-northeast-1 2>&1) || true

if echo "${RESP}" | grep -qiE 'ResourceNotFound|NoSuchEntity|NotFound|RepositoryNotFound|NoSuchDistribution|NoSuchBucket|does not exist'; then
  echo "OK: KB BKXE19AH89 is gone"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: KB BKXE19AH89 still exists"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
```

**Key elements:**
- `2>&1` to capture both stdout (success path) and stderr (error path) into the same variable.
- `|| true` so the bash `set -e` does not abort on the expected non-zero exit.
- `grep -qiE` for case-insensitive match against multiple known error names alternated with `|`.
- Counters at the end produce a clean PASS/FAIL summary (X/Y resources verified clean).

For the count-based checks (`describe-log-groups`, `describe-alarms`, `list-policies`), the inverse pattern works:

```bash
COUNT=$(aws logs describe-log-groups \
  --log-group-name-prefix /aws/bedrock-agentcore/hera-agent \
  --region ap-northeast-1 \
  --query 'logGroups | length(@)' --output text)

if [[ "${COUNT}" == "0" ]]; then
  echo "OK: log group /aws/bedrock-agentcore/hera-agent is gone"
else
  echo "FAIL: log group still has ${COUNT} matches"
fi
```

### CloudFront disable-then-delete window handling

Source: AWS docs `HowToDeleteDistribution.html` + community recommendations.

CloudFront's `delete-distribution` requires the distribution to be `Enabled = false` AND fully `Deployed`. The Terraform `aws_cloudfront_distribution` resource handles this automatically on destroy — it issues an UpdateDistribution to disable, polls `wait distribution-deployed` (15-30 min typical), then DeleteDistribution. The verify-script does NOT need to handle the in-between state — by the time the operator runs `terraform destroy && cleanup-verify.sh`, Terraform has already waited.

**Edge case:** if the operator interrupts `terraform destroy` mid-flight (Ctrl+C during the disable-wait), the distribution will be in `Enabled=false, Deployed=true` state but still present. `aws cloudfront get-distribution --id E10K3B1L8PQ9EC` will return 200 with the distribution body. The cleanup-verify will report this as "still exists" — correct outcome; the operator should re-run `terraform destroy`.

**Recommendation:** Document in RUNBOOK that `terraform destroy` may take 15-30 min on the CloudFront line; do not interrupt it. cleanup-verify.sh runs AFTER the destroy returns cleanly.

### AWS CLI v1 vs v2 differences

All commands above are AWS CLI v2 (the installed version per `bin/verify-kb.sh` checks). v1 is end-of-life as of mid-2024 and should not be supported. The `--query` JMESPath syntax `length(@)` is v2-stable.

Note from Plan 03-04: `MSYS_NO_PATHCONV=1` is required when passing log-group names starting with `/` through AWS CLI on Git Bash for Windows (the leading slash gets converted to a Windows path prefix). Add this env var prefix to log-group calls if running on Windows.

## E. Cost Explorer paste-line

### Verbatim `aws ce get-cost-and-usage` command

Source: AWS CLI 2.34 reference + AWS Cost Management docs (`ce-filtering.html`).

```bash
# Where TODAY is the destroy date and TODAY_PLUS_24H is the next day.
# --time-period uses inclusive Start, exclusive End (so single-day window).
aws ce get-cost-and-usage \
  --time-period "Start=$(date -u +%Y-%m-%d -d '-1 day'),End=$(date -u +%Y-%m-%d)" \
  --granularity DAILY \
  --metrics BlendedCost \
  --filter file://no-tax-credits.json \
  --region us-east-1 \
  | jq '.ResultsByTime[].Total.BlendedCost.Amount'
```

(`aws ce` is region-pinned to `us-east-1` because the Cost Explorer endpoint lives there. `--region us-east-1` is recommended for clarity; the CLI will auto-route there even if region is left default.)

`no-tax-credits.json`:

```json
{
  "Not": {
    "Dimensions": {
      "Key": "RECORD_TYPE",
      "Values": ["Tax", "Credit", "Refund"]
    }
  }
}
```

This filter excludes tax/credit/refund line items so the result reflects pure usage charges. `BlendedCost` (vs `UnblendedCost`) is the recommended metric for single-account verification — for an account not part of consolidated billing, the two values are identical, so it does not matter operationally; the docs and the binbashar reference module both default to `BlendedCost`.

**Time-period format:** `YYYY-MM-DD` (no timestamp suffix needed for daily granularity). Start is **inclusive**, End is **exclusive**. So to query "yesterday's spend", `Start=<yesterday>,End=<today>`.

### 24h ingestion lag + per-request fee — documented

- **Cost Explorer 24h ingestion lag:** Bills accrue throughout the day; Cost Explorer shows them with up to 24h lag. Running the paste-line immediately after `terraform destroy` returns stale data and creates UX confusion. RUNBOOK section heading: "Verify $0 ongoing cost (24h after destroy)".
- **Per-request fee:** `$0.01 per request` against the Cost Explorer API (verified against `aws.amazon.com/aws-cost-management/aws-cost-explorer/pricing/`, 2026-05-06). Each paginated page counts as a separate request. For a single-day single-metric query (no pagination), the fee is exactly $0.01. This is why D-38 keeps Cost Explorer OUT of `bin/cleanup-verify.sh` — the script could run repeatedly during an iteration cycle, and an instructor cohort of 30 learners running it 3x each = 90 × $0.01 = $0.90 needless spend.

## F. Project conventions

### Reusing `bin/push-image.sh` + `bin/smoke-deploy.sh` verbatim

`bin/push-image.sh` (already shipped Plan 03-03) — call signature for Plan 04-01:

```bash
# After Plan 04-01 source commits land, run:
bin/push-image.sh
# Outputs:  $ECR_URL:<git-sha>  e.g. .../hera-agent:abc1234
```

The script auto-resolves the git SHA via `git rev-parse --short HEAD` and pushes a multi-arch manifest. No new args needed.

`bin/smoke-deploy.sh` (already shipped Plan 03-04) is an 8-step orchestrator — but Plan 04-01 does NOT need to re-run all 8 steps. Plan 04-01's verify-gate is more focused:

1. Local docker run + curl POST (no AWS calls): `docker run --rm -p 8080:8080 hera-agent:<sha>` + `curl -fsS -X POST -H 'Content-Type: application/json' -d '{"prompt":"hi"}' http://localhost:8080/invocations` → expects 200 + JSON body.
2. `bin/push-image.sh` → ECR push.
3. `(cd infra/cdk && uv run cdk deploy hera-agentcore --context image_tag=<sha>)` → in-place version=3 update.
4. SC#2 closure smoke: `aws bedrock-agentcore invoke-agent-runtime --agent-runtime-arn <arn> --payload '{"prompt":"hi"}' /tmp/out.json` → assert exit 0 + parsed `statusCode`=200.

Plan 04-01 may add a small `bin/smoke-protocol-bridge.sh` paste-line OR extend `bin/smoke-deploy.sh` with a step 9 — planner picks based on simplicity.

### CDK in-place deploy shape

`cdk/agentcore/stack.py` (the canonical path is `infra/cdk/hera_agentcore/stack.py` — Glob shows the live file) reads `image_tag` from CDK context, NOT a CFn parameter. Verbatim from `bin/smoke-deploy.sh`:

```bash
(cd "$CDK_DIR" && uv run cdk deploy hera-agentcore \
  --context "image_tag=$GIT_SHA" \
  --outputs-file "$DIST_DIR/cdk-outputs.json" \
  --require-approval never)
```

This mutates the live CFn stack `hera-agentcore` in-place — same stack name, same logical IDs, only `ContainerUri` changes. CFn does an UPDATE_IN_PROGRESS → UPDATE_COMPLETE; the AgentCore runtime version increments from 2 to 3.

### FastAPI lifespan with mixed `/ws` + `/invocations`

The existing FastAPI `app = FastAPI(...)` does not declare a `lifespan` context manager. Adding `/invocations` route requires NO lifespan changes — both routes register on the same `app` instance, both share whatever startup state the app has at process start.

Plan 04-01 should NOT introduce a `lifespan=` argument. The boto3 default credential chain bridge (Plan 03-05) is per-WS-connection inside `build_llm()`; for the `/invocations` stub, no credential resolution is needed (the stub returns a static JSON envelope).

If a future plan needs lifespan (e.g., for a global AWSNovaSonicLLMService instance pool), it can be added without touching the route definitions. The awslabs sample does add a lifespan for IMDS credential refresh, but Hera's per-connection boto3-default-chain pattern (Plan 03-05) makes that unnecessary.

## G. Pitfalls

### G.1 — `/invocations` stub returning the wrong content-type

**Trap:** Returning a Pydantic model directly with `return MyModel(...)` instead of `JSONResponse({...})`. FastAPI's default response is `application/json` so this usually works, but AgentCore's HTTP layer may be picky about the `Content-Type` header value (`application/json` vs `application/json; charset=utf-8`).
**Mitigation:** Match the awslabs sample verbatim — use `JSONResponse({...})` from `fastapi.responses`.

### G.2 — CORS on `/invocations`

**Trap:** Adding `CORSMiddleware` to allow `*` origins on the FastAPI app would let any browser hit `/invocations`. AgentCore's data plane is the only legitimate caller; widening CORS adds attack surface.
**Mitigation:** Do NOT add CORSMiddleware. AgentCore's HTTP proxy strips Origin / handles cross-origin internally — the container does not see browser-origin requests directly. (Verified — the awslabs sample DOES add `CORSMiddleware(allow_origins=["*"])`, but that sample is meant to be locally testable; for AgentCore deploys, leaving it off is safer. Hera's existing main.py has no CORS config, which is correct.)

### G.3 — Billing-alerts toggle not enabled before alarm deploy

**Trap:** Terraform applies the billing alarm successfully, but the alarm sits in `INSUFFICIENT_DATA` forever because `AWS/Billing` `EstimatedCharges` is never published to CloudWatch in this account.
**Mitigation:** RUNBOOK pre-flight: tick "Receive CloudWatch Billing Alerts" in Billing Preferences ONCE per account before deploy. Document in Phase 4 RUNBOOK + verify section "Confirm dashboard billing widget shows non-empty data within 24h of deploy".

### G.4 — Wrong region on `aws_cloudwatch_metric_alarm` for billing

**Trap:** Forgetting the `provider = aws.us_east_1` argument on the billing alarm — it deploys to `ap-northeast-1` and never sees billing data.
**Mitigation:** Provider alias declaration in `main.tf` + `provider = aws.us_east_1` line on the resource. Confirm via `aws cloudwatch describe-alarms --alarm-names hera-billing-prod --region us-east-1` after apply.

### G.5 — CloudFront destroy interruption leaves a "zombie" distribution

**Trap:** Operator hits Ctrl+C during the 15-30 min CloudFront disable-then-delete cycle. The distribution stays in `Enabled=false, Deployed=true` and Terraform state thinks it is gone. cleanup-verify reports "still exists".
**Mitigation:** RUNBOOK: "DO NOT interrupt `terraform destroy` during the CloudFront line. Re-run if interrupted." cleanup-verify.sh exit message should hint "if CloudFront still exists, re-run terraform destroy — disable-then-delete cycle is 15-30 min".

### G.6 — ECR `imageTagMutability=IMMUTABLE` blocks `force_delete=false` cleanup

**Trap:** ECR repo has `force_delete=false` (Plan 03-01). Old image tags `:5e574b3`, `:5f21e36`, and the new Plan 04-01 SHA all sit in the repo. Terraform `destroy` of `aws_ecr_repository` fails with `RepositoryNotEmptyException`.
**Mitigation:** EITHER (a) operator runs `aws ecr batch-delete-image --repository-name hera-agent --image-ids imageTag=5e574b3 imageTag=5f21e36 imageTag=<new>` before `terraform destroy`, OR (b) the prod root sets `var.force_delete = true` before the destroy run. cleanup-verify.sh should detect "ECR repo still exists with N images" and surface this hint clearly.

### G.7 — `terraform destroy` ordering vs `cdk destroy`

**Trap:** Per D-24 the cleanup contract is `cdk destroy` FIRST, `terraform destroy` SECOND. If reversed, the AgentCore Runtime (CDK-owned) holds an active reference to the IAM exec role (TF-owned); TF's `aws_iam_role` destroy fails because policies are attached and the role is in use. Or the runtime ECR pull keeps spinning even though the repo is gone.
**Mitigation:** RUNBOOK + cleanup-verify.sh both reinforce the order. The script does NOT destroy — it only verifies. But its exit messages should hint "did you `cdk destroy hera-agentcore` first?" when a TF resource is still found AND the AgentCore Runtime is also still found.

### G.8 — `MSYS_NO_PATHCONV` on Git Bash

**Trap:** AWS CLI on Windows Git Bash mangles log group names starting with `/` (`/aws/bedrock-agentcore/hera-agent` → `C:/Program Files/Git/aws/bedrock-agentcore/hera-agent`). The `describe-log-groups --log-group-name-prefix` call returns no matches even though the group exists.
**Mitigation:** Prefix calls with `MSYS_NO_PATHCONV=1` when running on Windows. Document as a `# windows-bash:` note in cleanup-verify.sh comments.

### G.9 — boto3 SDK staleness

**Trap:** Some AWS Lambda Python runtimes ship a stale boto3 that does not yet know about `bedrock-agentcore` service. Plan 03-04's presigner uses `python3.12` runtime which does include modern boto3 — verified live. For Plan 04-01 there is no Lambda involved (the agent container ships its own boto3 via uv lock file, which already includes `aws-sdk-bedrock-runtime`). No mitigation needed for Plan 04-01.

### G.10 — Cost Explorer paste-line right after destroy returns stale $0

**Trap:** Operator runs the paste-line immediately after `terraform destroy && cleanup-verify.sh PASS`, sees `$0`, declares victory. 24h later the day's pre-destroy spend appears on the bill. Operator confused.
**Mitigation:** RUNBOOK section header MUST include "(24h after destroy)" — not optional. Section copy: "Cost Explorer has up to 24h ingestion lag. Run this paste-line tomorrow morning, not now."

## H. Wave structure recommendation

### File-disjoint analysis

| Plan | Files owned (write surface) | Conflict surface |
|------|----------------------------|-------------------|
| **04-01 protocol-bridge** | `agent/hera_agent/main.py` (add `/invocations` route stub), `RUNBOOK.md` (Phase 4 deploy + browser-test note section), live AWS state (image rebuild + cdk deploy version=3) | RUNBOOK headings only |
| **04-02 observability** | `infra/modules/observability/{versions,variables,main,outputs}.tf` (NEW module — dashboard + 3 alarms), `infra/envs/prod/main.tf` (one new module block + `provider "aws" { alias = "us_east_1" ... }`), `infra/envs/prod/outputs.tf` (dashboard URL), `RUNBOOK.md` (Phase 4 dashboard walkthrough section) | RUNBOOK headings only; `infra/envs/prod/main.tf` shared with 04-01 if 04-01 also needed TF — but 04-01 does NOT touch TF |
| **04-03 cleanup-verify** | `bin/cleanup-verify.sh` (NEW), `RUNBOOK.md` (Phase 4 cleanup quy trình + 24h Cost Explorer paste-line + manual-stop fallback sections) | RUNBOOK headings only |

**Conflict surface = RUNBOOK.md sections only.** Heading-disjoint sections per the Plan 02-03 pattern resolve this trivially: each plan owns named subsections under "## Phase 4" with no overlap. RUNBOOK can be edited in parallel as long as each plan's task targets a distinct heading range.

### Dependency analysis

- **04-02 observability** does NOT strictly depend on 04-01. The CloudWatch dashboard + alarms can deploy and start collecting data even if `/invocations` is still 404'ing — `Invocations` and `TotalErrors` will tick anyway. But the dashboard is more meaningful with real traffic, and the AGT-04-style end-to-end voice loop can't drive the metrics until 04-01 ships. So 04-02 AFTER 04-01 is cleaner from an instructor-demo perspective.
- **04-03 cleanup-verify** does NOT depend on 04-01 OR 04-02 being live — its job is to verify resources are GONE. It must, however, know about the resource list, which is fully specified by D-37 already. cleanup-verify can ship in any wave.

### Recommendation: 2 waves, 3 plans

**Wave 1 (BLOCKING — closes Phase 3 SC#2):**
- Plan 04-01 `agent-protocol-bridge` — solo. ~10 LOC + image push + 1 cdk deploy + 1 smoke probe.

**Wave 2 (parallel after Wave 1 PASSes):**
- Plan 04-02 `observability` — TF observability module + provider alias + dashboard + 3 alarms + RUNBOOK Phase 4 dashboard sections.
- Plan 04-03 `cleanup-verify` — `bin/cleanup-verify.sh` + RUNBOOK Phase 4 cleanup sections + 24h Cost Explorer paste-line.

**Why not single Wave with all three?** Plan 04-01 is the SC#2 closure and gates "what 'real traffic' actually looks like for the dashboard." If the planner ran them all in parallel and 04-01 hit a problem (e.g., the awslabs stub envelope is wrong for some reason and AgentCore wants something more), 04-02's dashboard would be deploying against a still-broken endpoint. Sequencing 04-01 first eliminates that risk. The cost is one extra wave, but Plan 04-01 is small (~10 LOC + 1 deploy) so the wave is fast.

**Alternative considered:** Single Wave 1 with all three. File-disjoint says yes. Risk says no. Picked sequence.

### Plan-count recommendation

**3 plans** (04-01 + 04-02 + 04-03), NOT 2. Rationale:
- 04-02 and 04-03 are clearly file-disjoint and can run in parallel (Wave 2). Merging them into a single plan would force serial work.
- 04-01 is its own beast — it's the SC#2-closure plan with a different scope (agent code vs TF infra) and a different risk profile (live cdk deploy vs pure TF apply).
- Coarse granularity = 1-3 plans per phase. 3 fits.

## Project Constraints (from CLAUDE.md)

- No emojis in any file (logs, code, docstrings, this RESEARCH.md).
- `uv` exclusively for Python — never `pip install`, never `python3 X`. Phase 4 has no new Python entry points but the agent container continues to use uv.
- Concise docstrings; sparing comments outside docstrings.
- No defensive try/except — root-cause discipline. Plan 04-01's `/invocations` handler should NOT have a try/except around the dictionary literal.
- Latest APIs as of NOW. The AgentCore data-plane API selection (`InvokeAgentRuntime` vs WebSocketStream variant) is a "latest" decision the research has confirmed.
- Locked stack — Bedrock AgentCore Runtime, Pipecat 1.1.0, S3 Vectors, Terraform `~> 6.27`, region `ap-northeast-1` prod / `us-east-1` dev. Plan 04-02 introduces `us-east-1` as a SECOND region for billing alarm only — this is documented as an AWS service constraint, not a deviation from the locked stack.
- Workshop / chatbot bilingual policy — Plan 04 is all English (chatbot stays English; workshop docs are Phase 5 work).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| OBS-01 | CloudWatch dashboard with active sessions, latency p50/p95, error rate, Bedrock invocation count | Section B — auto-emitted metrics inventory + dashboard JSON sample. All 5 panels buildable from auto metrics. |
| OBS-02 | CloudWatch alarms: error rate >5% / 5min, latency p95 >5s / 5min | Section C — `metric_query` arithmetic for error rate, `extended_statistic = "p95"` for latency. Verbatim Terraform shape. |
| OBS-03 | CloudWatch billing alarm at default $5/day | Section C — `provider = aws.us_east_1` + namespace `AWS/Billing` + dimension `Currency=USD` + 6h period. Account toggle is manual. |
| OBS-04 | Anonymous-public-URL abuse bounded — concurrency cap + per-IP rate limit | Per D-36, no IaC change — AgentCore concurrency cap=2 (operational quota) is the effective rate-limit. RUNBOOK documents trade-off. |
| OBS-05 | Cost circuit breaker (best-effort, document trade-off) | Per D-35, no SNS / Lambda hook — billing alarm + manual response procedure. RUNBOOK documents trade-off. |

(Plus the Wave-1 priority plan 04-01 protocol-bridge — closes Phase 3 SC#2, no new requirement ID; satisfies the deferred portion of DEP-02 and the live-loop portion of DEM-02.)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The "Receive CloudWatch Billing Alerts" toggle is NOT yet enabled on account 851725411875. | C, G.3 | Billing alarm sits INSUFFICIENT_DATA for 24h; dashboard billing widget empty. RUNBOOK pre-flight catches it. |
| A2 | Operator running the SC#2 closure smoke probe has IAM grant for `bedrock-agentcore:InvokeAgentRuntime` outside the presigner Lambda's policy. | A | Smoke fails with AccessDenied; planner adds an explicit IAM grant note to RUNBOOK. |
| A3 | `TimeToFirstToken` is emitted for the bidi-streaming Sonic API (`InvokeModelWithBidirectionalStream`), not just `ConverseStream` / `InvokeModelWithResponseStream`. | B | Dashboard panel for first-audio latency stays empty; planner falls back to AgentCore `Latency` p95. |
| A4 | The S3 Vectors `aws s3vectors` CLI commands return `NotFoundException` (not a different error name) when the index/bucket is gone. | D | cleanup-verify.sh grep pattern misses the right error — script reports "still exists" falsely. Add `NotFound` (without `Exception`) to the regex to cover both spellings. |
| A5 | The KB service role's exact name is `hera-kb-service-prod` (D-12 fixed-name pattern). | D | cleanup-verify call `aws iam get-role --role-name <wrong-name>` returns NoSuchEntity even though a different-named role still exists. Planner verifies the live name from `terraform state list` or by reading `infra/modules/knowledge_base/iam.tf`. |
| A6 | The agent container's existing FastAPI app accepts adding a `@app.post("/invocations")` route handler without lifespan changes. | A, F | Verified by reading agent/hera_agent/main.py — VERIFIED, no lifespan, simple add. NOT an assumption — promoted to verified fact. |

**A6 is verified**, removed from the assumptions list operationally; left in the table for traceability of the verification step.

## Open Questions

1. **Should Plan 04-01 also bump the agent's `/ping` to set `time_of_last_update` from a `health` global on each successful `/invocations` call?**
   - What we know: AgentCore's health probe accepts `Healthy` and `HealthyBusy`. Hera's current `/ping` returns a frozen-at-boot `time_of_last_update`.
   - What's unclear: Does AgentCore use `time_of_last_update` for any liveness logic (e.g., killing a stuck container)?
   - Recommendation: Leave as-is for Plan 04-01. Hera's /ping is already shipping; do not over-scope.

2. **For the operational alarms, use `evaluation_periods=1, period=300` or `evaluation_periods=5, period=60`?**
   - What we know: AWS docs default to `evaluation_periods=1` for billing-style alarms; community modules split.
   - What's unclear: Hera demo traffic is sparse — at 60s evaluation periods with `notBreaching` missing-data treatment, the alarms behave correctly but flip more often.
   - Recommendation: `evaluation_periods=1, period=300` — single evaluation window of 5 min matches REQ wording verbatim ("over 5 minutes"). Documented in Section C.

3. **Should the dashboard widget for "Bedrock cost" use Cost Explorer cross-region data sources, or stick to token-volume + manual paste-line?**
   - What we know: Cost Explorer has 24h lag and per-request fee. Token volume is real-time but proxy.
   - What's unclear: Whether dashboards even support Cost Explorer queries inline (likely no — CW dashboards take CW metrics, not CE queries).
   - Recommendation: Token-volume panel + dashboard text-widget pointing to RUNBOOK paste-line. Honors D-38.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Bash + AWS CLI v2 + jq | bin/cleanup-verify.sh, smoke probe | ✓ | per `bin/verify-kb.sh` preflight | — |
| Docker + buildx | Plan 04-01 image rebuild | ✓ | per `bin/push-image.sh` preflight | — |
| Terraform `~> 6.27` | Plan 04-02 observability module | ✓ | per `infra/modules/widget_presigner/versions.tf` lock | — |
| CDK Python (uv-managed) | Plan 04-01 cdk deploy in-place | ✓ | per `infra/cdk/` setup | — |
| boto3 (in agent container) | (no new use in Plan 04-01) | ✓ | per `agent/uv.lock` | — |
| `aws bedrock-agentcore` CLI verb | SC#2 closure smoke probe | ✓ | AWS CLI 2.34.38+ ships it | — |
| `aws s3vectors` CLI verb | cleanup-verify (S3 Vectors index/bucket) | ✓ | AWS CLI 2.x — verified by Plan 01-03 verify-kb.sh existence | — |
| Account-level "Receive Billing Alerts" toggle | OBS-03 billing alarm | ✗ [needs-verification] | — | Manual operator step in RUNBOOK pre-flight |
| `aws ce get-cost-and-usage` CLI | RUNBOOK 24h paste-line | ✓ (but $0.01/request fee) | — | — |

## Sources

### Primary (HIGH confidence)
- AgentCore HTTP protocol contract (verbatim) — https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-http-protocol-contract.html
- AgentCore service contract (protocol comparison table) — https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-service-contract.html
- AgentCore data-plane `InvokeAgentRuntime` API reference (verbatim Request/Response Syntax) — https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/API_InvokeAgentRuntime.html
- AgentCore observability runtime metrics (verbatim metrics list, namespace `AWS/Bedrock-AgentCore`) — https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-runtime-metrics.html
- Canonical Pipecat-on-AgentCore sample server.py (verbatim source code fetched from raw.githubusercontent.com) — https://github.com/awslabs/agentcore-samples/tree/main/01-tutorials/01-AgentCore-runtime/06-bi-directional-streaming/04-pipecat-sonic-ws
- AgentCore bidirectional streaming examples landing page — https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-bidirectional-streaming-examples.html
- CloudWatch billing alarm prerequisites (verbatim "Receive Billing Alerts" + us-east-1 constraint) — https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html
- terraform-provider-aws cloudwatch_metric_alarm resource doc (verbatim — fetched from GitHub raw markdown source) — https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm
- terraform-provider-aws cloudwatch_dashboard resource doc — https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard
- AWS CLI bedrock-agentcore-control get-agent-runtime — https://docs.aws.amazon.com/cli/latest/reference/bedrock-agentcore-control/get-agent-runtime.html
- AWS CLI bedrock-agentcore invoke-agent-runtime — https://docs.aws.amazon.com/cli/latest/reference/bedrock-agentcore/invoke-agent-runtime.html
- AWS CLI ce get-cost-and-usage — https://docs.aws.amazon.com/cli/latest/reference/ce/get-cost-and-usage.html
- AWS Cost Explorer pricing ($0.01/request) — https://aws.amazon.com/aws-cost-management/aws-cost-explorer/pricing/
- CloudFront delete-distribution prerequisites — https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/HowToDeleteDistribution.html
- Bedrock CloudWatch metrics namespace `AWS/Bedrock` (Invocations, InvocationLatency, etc.) — https://docs.aws.amazon.com/bedrock/latest/userguide/monitoring.html
- AWS blog: TimeToFirstToken metric for Bedrock — https://aws.amazon.com/blogs/machine-learning/improve-operational-visibility-for-inference-workloads-on-amazon-bedrock-with-new-cloudwatch-metrics-for-ttft-and-estimated-quota-consumption/

### Secondary (MEDIUM confidence)
- Pipecat-examples aws-agentcore-websocket deployment sample — https://github.com/pipecat-ai/pipecat-examples/tree/main/deployment/aws-agentcore-websocket
- Medium article — Demystifying the HTTP protocol contract for AgentCore Runtime (cross-verifies docs) — https://eashank16.medium.com/demystifying-the-http-protocol-contract-for-amazon-bedrock-agentcore-runtime-30ae130485b4
- binbashar/terraform-aws-cost-billing-alarm reference module — https://github.com/binbashar/terraform-aws-cost-billing-alarm
- AWS dev.to article — AgentCore Runtime Observability (Part 3) — https://dev.to/aws-heroes/amazon-bedrock-agentcore-runtime-part-3-agentcore-observability-f08
- AWS Cost Management — Filtering data — https://docs.aws.amazon.com/cost-management/latest/userguide/ce-filtering.html

### Tertiary (LOW confidence)
- (None used as primary support; all critical claims verified against HIGH sources.)

## Metadata

**Confidence breakdown:**
- Protocol-bridge contract + sample: HIGH — verified verbatim against AWS docs + raw.githubusercontent.com fetch of awslabs sample.
- AgentCore-emitted metrics inventory: HIGH — verified verbatim from AWS observability-runtime-metrics docs.
- Bedrock model metrics: HIGH — verified from AWS docs + 2026 AWS blog on TTFT.
- Terraform alarm/dashboard resource shape: HIGH — verified from terraform-provider-aws GitHub markdown source.
- SC#2 closure smoke probe selection (`InvokeAgentRuntime`): MEDIUM-HIGH — backed by API reference; one [needs-verification] on operator-side IAM permissions.
- Billing alarm region/toggle: HIGH — verified from AWS docs.
- cleanup-verify CLI commands: HIGH — verified per resource type from AWS CLI 2.34 reference.
- Wave-structure recommendation: HIGH (file-disjoint analysis) — assertions about RUNBOOK heading-disjoint pattern are project-internal facts.

**Research date:** 2026-05-06
**Valid until:** 2026-06-06 (30 days, stable APIs); valid as long as awslabs/agentcore-samples sample stays at this shape — re-verify if the sample directory restructures.
