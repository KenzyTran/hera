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
| **OpenAI Agents traces** | https://platform.openai.com/traces | Waterfall trace: session → kb_retrieve span (KB Retrieve + S3 Vectors) |
| CloudWatch Dashboard | https://ap-northeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=hera-prod | Active sessions, latency p95, error rate, Sonic token, billing |
| X-Ray Service Map | https://ap-northeast-1.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#xray:service-map/map | Topology + latency averages |
| S3 catalog access | `s3://hera-kb-source-prod/access-logs/` | KB ingest reads on source markdown |

---

## OpenAI API Key — Setup

Tracing via OpenAI Agents SDK dùng OPENAI_API_KEY để upload spans lên `platform.openai.com/traces`. Key được set ở env var của AgentCore Runtime container.

### Set / rotate key

```bash
# Replace sk-... with your real key
NEW_KEY="sk-proj-..."

aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id hera_agent-SCPFxK4PDa \
  --region ap-northeast-1 \
  --agent-runtime-artifact "containerConfiguration={containerUri=851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent:CURRENT_TAG}" \
  --role-arn arn:aws:iam::851725411875:role/hera-agentcore-exec-prod \
  --network-configuration networkMode=PUBLIC \
  --protocol-configuration serverProtocol=HTTP \
  --environment-variables "HERA_LOG_GROUP=/aws/bedrock-agentcore/hera-agent,AWS_REGION=ap-northeast-1,HERA_KB_ID=BKXE19AH89,OTEL_SDK_DISABLED=true,OPENAI_API_KEY=$NEW_KEY"
```

Lưu ý:
- `CURRENT_TAG` = git SHA của image đang chạy. Xem bằng:
  ```bash
  aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id hera_agent-SCPFxK4PDa --region ap-northeast-1 \
    --query 'agentRuntimeArtifact.containerConfiguration.containerUri' --output text
  ```
- Toàn bộ env vars phải pass lại (update là REPLACE chứ không MERGE). Nếu quên 1 var nào, container sẽ mất nó.
- Runtime sẽ `UPDATING` → `READY` trong ~30s.

### Disable tracing (remove key)

```bash
# Same command above but drop OPENAI_API_KEY from --environment-variables
aws bedrock-agentcore-control update-agent-runtime ... \
  --environment-variables "HERA_LOG_GROUP=/aws/bedrock-agentcore/hera-agent,AWS_REGION=ap-northeast-1,HERA_KB_ID=BKXE19AH89,OTEL_SDK_DISABLED=true"
```

Code sẽ tự skip `trace()` + `custom_span()` wrappers khi env var không có (kiểm tra `OPENAI_API_KEY` lúc startup).

### Verify key is set

```bash
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id hera_agent-SCPFxK4PDa --region ap-northeast-1 \
  --query 'environmentVariables.OPENAI_API_KEY' --output text | head -c 12
```

Trả về `sk-proj-Hoc` (11 ký tự đầu) = key đang set. Trả `None` = chưa set.

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

- OPENAI_API_KEY là **secret**. Không bao giờ commit vào git. Không paste vào shared chat.
- Key được store encrypted at rest trong AgentCore Runtime env vars.
- Nội dung trace (query text, KB chunk text) upload lên OpenAI. Với demo Apple Store: không nhạy cảm. Với prod thật: xem lại quyền tracing trước.
- Rotate key định kỳ bằng cách re-run update command với key mới.
- Disable nhanh nếu cần: drop env var → container next-restart tự skip tracing wrappers.
