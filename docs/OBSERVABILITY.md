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

Tracing via Langfuse SDK dùng 3 env vars để upload spans lên `cloud.langfuse.com`. Keys set ở env var của AgentCore Runtime container.

### Lấy keys từ Langfuse Cloud

1. https://cloud.langfuse.com → Sign up (free tier 50k events/month)
2. Create project → đặt tên
3. Project Settings → API Keys → Create new API keys
4. Copy `pk-lf-...` (public) + `sk-lf-...` (secret) — secret chỉ hiện 1 lần
5. Host: `https://cloud.langfuse.com` (EU) hoặc `https://us.cloud.langfuse.com` (US)

### Set / rotate keys

```bash
# Replace with real values
PUB="pk-lf-..."
SEC="sk-lf-..."
HOST="https://cloud.langfuse.com"

aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id hera_agent-SCPFxK4PDa \
  --region ap-northeast-1 \
  --agent-runtime-artifact "containerConfiguration={containerUri=851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent:CURRENT_TAG}" \
  --role-arn arn:aws:iam::851725411875:role/hera-agentcore-exec-prod \
  --network-configuration networkMode=PUBLIC \
  --protocol-configuration serverProtocol=HTTP \
  --environment-variables "HERA_LOG_GROUP=/aws/bedrock-agentcore/hera-agent,AWS_REGION=ap-northeast-1,HERA_KB_ID=BKXE19AH89,OTEL_SDK_DISABLED=true,LANGFUSE_PUBLIC_KEY=$PUB,LANGFUSE_SECRET_KEY=$SEC,LANGFUSE_HOST=$HOST"
```

Lưu ý:
- `CURRENT_TAG` = git SHA của image đang chạy. Xem bằng:
  ```bash
  aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id hera_agent-SCPFxK4PDa --region ap-northeast-1 \
    --query 'agentRuntimeArtifact.containerConfiguration.containerUri' --output text
  ```
- Update là REPLACE chứ không MERGE — toàn bộ env vars phải pass lại.
- Runtime `UPDATING` → `READY` trong ~30s.

### Disable tracing (remove keys)

```bash
# Drop LANGFUSE_* from --environment-variables
aws bedrock-agentcore-control update-agent-runtime ... \
  --environment-variables "HERA_LOG_GROUP=/aws/bedrock-agentcore/hera-agent,AWS_REGION=ap-northeast-1,HERA_KB_ID=BKXE19AH89,OTEL_SDK_DISABLED=true"
```

Code tự skip Langfuse wrappers khi `LANGFUSE_SECRET_KEY` không có.

### Verify keys are set

```bash
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id hera_agent-SCPFxK4PDa --region ap-northeast-1 \
  --query 'environmentVariables.LANGFUSE_SECRET_KEY' --output text | head -c 10
```

Trả `sk-lf-efc4` = key đang set. Trả `None` = chưa set.

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
