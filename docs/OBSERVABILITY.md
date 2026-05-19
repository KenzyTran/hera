# Hera — Observability & Tracing Operations Guide

Tổng hợp các nơi xem log + trace + cách quản lý OpenAI API key cho tracing.

---

## Trace Stack — Where to View

| Layer | Nơi | Mô tả |
|---|---|---|
| Container app logs | `/aws/bedrock-agentcore/hera-agent` | Pipecat events, Sonic stream raw bytes, VAD, tool dispatch, errors |
| Bedrock model invocations | `/aws/bedrock/invocations` | Mỗi InvokeModel call (Titan embed query/response, token count) |
| Lambda presigner | `/aws/lambda/hera-widget-presign-prod` | Mỗi presign URL request |
| AgentCore service spans | `aws/spans` | 1 span/WS session với session.id + latency (root-level only) |
| **Langfuse traces** | https://cloud.langfuse.com | Waterfall trace per WS session: hera-voice-session → lookup_product → kb_retrieve (KB Retrieve + S3 Vectors). Includes LLM cost tracking, session view, prompt versioning. |
| CloudWatch Dashboard | https://ap-northeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=hera-prod | Active sessions, latency p95, error rate, Sonic token, billing |
| X-Ray Service Map | https://ap-northeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#xray:service-map/map | Topology + latency averages |
| S3 catalog access | `s3://hera-kb-source-prod/access-logs/` | KB ingest reads on source markdown |

---

## Langfuse Keys — Setup

Tracing via Langfuse SDK dùng 3 env vars để upload spans lên `cloud.langfuse.com`. Keys được bake vào AgentCore Runtime tại thời điểm `cdk deploy` (KHÔNG patch sau bằng `update-agent-runtime` — config-only update không recycle container nên patch không có tác dụng).

### Lấy keys từ Langfuse Cloud

1. https://cloud.langfuse.com → Sign up (free tier 50k events/month)
2. Create project → đặt tên (hera-voice-agent)
3. Project Settings → API Keys → Create new API keys
4. Copy `pk-lf-...` (public) + `sk-lf-...` (secret) — secret chỉ hiện 1 lần
5. Host: `https://cloud.langfuse.com` (EU) hoặc `https://us.cloud.langfuse.com` (US)

### Lưu keys vào `.env.langfuse` (gitignored)

```bash
# Tạo file ở repo root (KHÔNG commit).
cat > .env.langfuse <<'EOF'
export LANGFUSE_PUBLIC_KEY=pk-lf-...
export LANGFUSE_SECRET_KEY=sk-lf-...
export LANGFUSE_HOST=https://cloud.langfuse.com
EOF
```

### Set keys lên runtime — chỉ qua `cdk deploy`

```bash
source .env.langfuse
(cd infra/envs/prod && terraform output -json > terraform-outputs.json)
(cd infra/cdk && cdk deploy hera-agentcore \
  --context image_tag=$(git rev-parse --short HEAD) \
  --outputs-file ../../dist/cdk-outputs.json \
  --require-approval never)
```

CDK đọc 3 env var (`LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST`) từ shell và bake vào CFn `EnvironmentVariables` của runtime. Container restart trong ~20s và đọc keys mới ngay. RUNBOOK Phase 3 Step 3 là single source of truth cho lệnh deploy đầy đủ.

### Disable tracing

Mở shell mới (không source `.env.langfuse`) rồi re-deploy. CDK thấy 3 env var rỗng → skip không set vào CFn. Code trong `main.py` / `tools.py` no-op SDK wrappers khi `LANGFUSE_SECRET_KEY` không có.

### Verify tracing đã active

```bash
# 1. Config plane: keys có trong runtime
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id <runtime-id> --region ap-northeast-1 \
  --query 'environmentVariables.LANGFUSE_SECRET_KEY' --output text | head -c 10
# Trả "sk-lf-..." = OK config plane.

# 2. Container đã pickup + SDK init thành công
aws logs filter-log-events \
  --log-group-name /aws/bedrock-agentcore/hera-agent \
  --start-time $(($(date +%s)*1000 - 300000)) \
  --region ap-northeast-1 \
  --filter-pattern '"Langfuse client initialized"' \
  --query 'events[-1].message' --output text
# Trả ".. Langfuse client initialized: ... auth_check=True" = container đã ship traces được.

# 3. Trace thật xuất hiện ở UI
# Mở https://cloud.langfuse.com -> project -> Traces, refresh sau khi /ws session đóng.
```

### Đừng làm

- KHÔNG set `OTEL_SDK_DISABLED=true` trong env vars của runtime. Biến này tắt OpenTelemetry toàn cục, mà Langfuse SDK chạy trên OTel — trace sẽ không bao giờ rời container dù `auth_check=True`. Container log sẽ in `OTEL_SDK_DISABLED is set. Langfuse tracing will be disabled and no traces will appear in the UI.` Nếu thấy log đó, mở `infra/cdk/hera_agentcore/stack.py` và xác nhận `OTEL_SDK_DISABLED` không nằm trong `env_vars` dict, rồi re-deploy.
- KHÔNG patch keys bằng `aws bedrock-agentcore-control update-agent-runtime` sau khi deploy. Config-only update KHÔNG recycle container; container đang chạy giữ env vars cũ tới khi natural recycle (có thể hàng giờ). Luôn re-deploy qua CDK.

---

## Quick Commands

```bash
# Tail container log (live)
aws logs tail /aws/bedrock-agentcore/hera-agent --since 5m --follow --region ap-northeast-1

# Tail Bedrock invocations (Titan embed + future Sonic logs)
aws logs tail /aws/bedrock/invocations --since 5m --follow --region ap-northeast-1

# Inspect AgentCore root spans (JSON OTel format)
aws logs filter-log-events --log-group-name aws/spans \
  --start-time $(($(date +%s)*1000 - 600000)) --region ap-northeast-1 \
  --query 'events[*].message' --output text | python -m json.tool

# Get current runtime image tag
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id hera_agent-SCPFxK4PDa --region ap-northeast-1 \
  --query 'agentRuntimeArtifact.containerConfiguration.containerUri' --output text
```

---

## Security Notes

- `LANGFUSE_SECRET_KEY` là **secret**. Không bao giờ commit vào git. Không paste vào shared chat.
- Keys store encrypted at rest trong AgentCore Runtime env vars.
- Nội dung trace (query text, kb_id, chunks count) upload lên Langfuse cloud. Với demo Apple Store: không nhạy cảm. Với prod thật: cân nhắc self-host Langfuse (Docker / k8s) để data stay in-account.
- Rotate key bằng cách re-run update command với secret mới.
- Disable nhanh: drop `LANGFUSE_SECRET_KEY` env var → container next-restart tự skip tracing wrappers.
