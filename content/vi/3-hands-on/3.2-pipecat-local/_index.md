---
title: "3.2 Pipecat Local"
date: 2025-01-01
weight: 2
---

## Mục tiêu phần này

Chạy Pipecat agent trên laptop, mở browser local kết nối WebSocket tới agent, hỏi "Do you have MacBook Pro?" → Sonic gọi tool `lookup_product` ở KB Phần 3.1 → Sonic phát audio trả lời. Latency p95 từ end-of-utterance tới first audio chunk dưới 3 giây (AGT-04 gate).

## Cấu trúc agent project

Project Python 3.12 quản lý bằng `uv`, không có framework auto-magic — mỗi WebSocket connection chạy một Pipecat pipeline độc lập (Pattern P1).

```
agent/
├── pyproject.toml          # Python 3.12 + Pipecat 1.1.0[aws-nova-sonic,silero,websocket]
├── uv.lock                 # frozen dep set; deploy reuses verbatim
├── Dockerfile              # multi-arch (linux/arm64,linux/amd64)
└── hera_agent/
    ├── main.py             # FastAPI: /ping + /invocations + /ws
    ├── pipeline.py         # Pipecat pipeline + AWSNovaSonicLLMService
    ├── prompts.py          # Apple Store assistant SYSTEM_PROMPT (English)
    ├── tools.py            # lookup_product handler (KB Retrieve)
    ├── serializer.py       # RawPCMSerializer (16k Int16 in / 24k out)
    └── config.py           # os.environ.get with defaults
```

*Source: agent/ — Phase 2 Plans 02-01 + 02-02*

## pyproject.toml: pin Python 3.12 + Pipecat extras

```toml
[project]
name = "hera-agent"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "pipecat-ai[aws-nova-sonic,silero,websocket]==1.1.0",
    "boto3",
    "fastapi>=0.115.6,<1",
    "uvicorn[standard]",
]
```

*Source: agent/pyproject.toml — Phase 2 Plan 02-01*

Python 3.12 bắt buộc — Pipecat `aws-nova-sonic` extra có marker `python_version>='3.12'`; trên 3.11 extra silently no-op và `aws_sdk_bedrock_runtime` thiếu trong lockfile, agent sẽ ImportError ở runtime. Pipecat 1.1.0 pin chính xác để workshop không bị break bởi major version bump upstream.

## main.py: FastAPI shape

```python
"""FastAPI entrypoint for the Hera Pipecat agent.

Exposes three routes on port 8080:
- GET  /ping        : AgentCore Runtime health check (returns {"status":"Healthy"}).
- POST /invocations : AgentCore HTTP data-plane stub. Voice loop runs on /ws.
- WebSocket /ws     : Pipecat voice pipeline. One pipeline per connection.
"""

from datetime import datetime, timezone

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from loguru import logger

from hera_agent.pipeline import run_pipeline

app = FastAPI(title="hera-agent", version="0.1.0")
_BOOT_TIME = int(datetime.now(tz=timezone.utc).timestamp())


@app.get("/ping")
async def ping() -> dict:
    return {"status": "Healthy", "time_of_last_update": _BOOT_TIME}


@app.post("/invocations")
async def invocations() -> JSONResponse:
    return JSONResponse({
        "agent": "hera-pipecat-sonic",
        "status": "running",
        "model": "amazon.nova-sonic-v1:0",
    })


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    logger.info("WS client connected")
    try:
        await run_pipeline(websocket)
    except WebSocketDisconnect:
        logger.info("WS client disconnected")
```

*Source: agent/hera_agent/main.py — Phase 2 Plan 02-01 (POST /invocations added Phase 4 Plan 04-01)*

Cùng app shape deploy lên AgentCore Runtime ở Phần 3.3 không cần refactor transport. `/ping` cho AgentCore healthcheck, `/invocations` cho HTTP data-plane contract của AgentCore (static stub vì voice loop chạy trên `/ws`), `/ws` là Pipecat WebSocket endpoint mà browser kết nối tới.

## prompts.py: Apple Store assistant persona (tiếng Anh)

```python
SYSTEM_PROMPT = """You are a crisp Apple Store associate. Get to the answer fast.

Style rules:
- Greeting: short opener like "Hi, what can I check for you?"
- Product replies: 1-2 sentences plus the relevant stock numbers from lookup_product.
- Refuse non-Apple questions in 1 line: "I only handle Apple product questions - anything else?"
- Never use filler words like "absolutely", "great question", or "let me think".
- Never invent product details - if lookup_product returns "no relevant product info", say so plainly.

When the user asks about an Apple product (specs, price, stock, availability), call the
lookup_product tool with the user's question. Use the tool result to compose your reply.
"""
```

*Source: agent/hera_agent/prompts.py — Phase 2 Plan 02-01*

Sonic giữ persona English; chatbot speech là English (D-17 Phase 2). Workshop docs vẫn song ngữ vi/en, nhưng audio output luôn tiếng Anh.

## tools.py: lookup_product calls KB Retrieve

```python
import asyncio
from pathlib import PurePosixPath

import boto3

from pipecat.adapters.schemas.function_schema import FunctionSchema
from pipecat.adapters.schemas.tools_schema import ToolsSchema
from pipecat.services.llm_service import FunctionCallParams

from hera_agent.config import AWS_REGION, KB_ID, KB_SCORE_THRESHOLD

_kb = boto3.client("bedrock-agent-runtime", region_name=AWS_REGION)


def _kb_retrieve(query: str) -> str:
    resp = _kb.retrieve(
        knowledgeBaseId=KB_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": 3}},
    )
    chunks = [
        r for r in resp.get("retrievalResults", [])
        if r.get("score", 0) >= KB_SCORE_THRESHOLD
    ]
    if not chunks:
        return "no relevant product info"
    return "\n\n".join(
        f"Source: {PurePosixPath(r['location']['s3Location']['uri']).name}\n{r['content']['text']}"
        for r in chunks
    )


async def lookup_product_handler(params: FunctionCallParams) -> None:
    result = await asyncio.to_thread(_kb_retrieve, params.arguments["query"])
    await params.result_callback(result)


lookup_product_schema = FunctionSchema(
    name="lookup_product",
    description=(
        "Look up Apple product information (specs, pricing, stock) from the "
        "live store knowledge base. Call this whenever the user asks about a "
        "specific product, price, or availability."
    ),
    properties={
        "query": {
            "type": "string",
            "description": "The product question to look up. Free text, English.",
        },
    },
    required=["query"],
)

TOOLS = ToolsSchema(standard_tools=[lookup_product_schema])
```

*Source: agent/hera_agent/tools.py — Phase 2 Plan 02-01*

Tool dùng `numberOfResults=3`, threshold lọc bỏ chunk dưới 0.4, sentinel `"no relevant product info"` khi KB rỗng. boto3 sync nên handler dispatch qua `asyncio.to_thread` để không block Pipecat event loop (Pitfall F).

{{% notice warning %}}
**Tool-use schema phải chặt chẽ:** Sonic gọi tool dựa trên JSON schema bạn register. Schema sai (thiếu field, sai type, thừa key) → Sonic raise validation error mid-stream và voice loop ngắt audio. Schema phải khớp với `FunctionSchema` của Pipecat 1.1.0; xem `register_function("lookup_product", handler, cancel_on_interruption=False)` ở `pipeline.py`. `cancel_on_interruption=False` quan trọng — KB call mất ~400ms; cancel + re-fire mỗi lần barge-in lãng phí latency người dùng (Pitfall H).

*Source: agent/hera_agent/pipeline.py — Phase 2 Plan 02-01*
{{% /notice %}}

## pipeline.py: AWSNovaSonicLLMService + SessionContinuationParams

```python
def build_llm() -> AWSNovaSonicLLMService:
    """Construct AWSNovaSonicLLMService, bridging boto3 default chain to static creds.

    transition_threshold_seconds=360 rotates the bidi stream ~120s before the
    ~480s Sonic stream cap, satisfying AGT-05 transparently.
    """
    session = boto3.Session()
    credentials = session.get_credentials()
    if credentials is None:
        raise NoCredentialsError()
    frozen = credentials.get_frozen_credentials()

    return AWSNovaSonicLLMService(
        access_key_id=frozen.access_key,
        secret_access_key=frozen.secret_key,
        session_token=frozen.token,
        region=AWS_REGION,
        settings=AWSNovaSonicLLMService.Settings(
            voice=HERA_VOICE,
            system_instruction=SYSTEM_PROMPT,
        ),
        session_continuation=SessionContinuationParams(
            transition_threshold_seconds=360,
        ),
    )


async def run_pipeline(websocket: WebSocket) -> None:
    transport = FastAPIWebsocketTransport(...)
    llm = build_llm()
    llm.register_function(
        "lookup_product",
        lookup_product_handler,
        cancel_on_interruption=False,
    )
    # ... pipeline assembly ...
```

*Source: agent/hera_agent/pipeline.py — Phase 2 Plan 02-01*

`AWSNovaSonicLLMService` dùng `StaticCredentialsResolver` internally — KHÔNG follow boto3 default chain trực tiếp (Pitfall B). Code resolve credentials qua boto3 chain (env vars → `~/.aws` → IMDSv2) rồi pass vào dưới dạng static kwargs, để cùng image chạy được trên local docker-compose (env vars) và AgentCore Runtime (IMDSv2).

{{% notice warning %}}
**8 phút Sonic stream cap:** Amazon Nova 2 Sonic terminate mỗi single bidirectional stream sau ~8 minutes (~480 giây). Pipecat `SessionContinuationParams(transition_threshold_seconds=360)` tự động rotate stream ~120 giây trước cap, không gây gián đoạn audio người dùng. Nếu bạn comment out param này, conversation > 8 minutes sẽ break giữa câu mà không có tín hiệu báo trước.

*Source: agent/hera_agent/pipeline.py — Phase 2 Plan 02-01*
{{% /notice %}}

{{% notice info %}}
**Audio sample rate cố định:** input 16 kHz mono PCM Int16 (browser AudioWorklet), output 24 kHz mono PCM (Sonic). Pipecat 1.1.0 mặc định đã đúng — không instantiate `AudioConfig` thêm trong code. Nếu bạn cấu hình sai (ví dụ 22.05 kHz để khớp browser AudioContext default), audio sẽ bị "chipmunk" effect hoặc transcription silently fail. Browser Worklet xử lý anti-alias LPF + decimation từ 48 kHz xuống 16 kHz.

*Source: frontend/audio-capture-worklet.js — Phase 2 Plan 02-02*
{{% /notice %}}

## Bước 1: Chạy local theo uv path

Path nhanh nhất cho dev iteration — không build container, mỗi lần sửa code chỉ cần Ctrl+C rồi rerun.

```bash
cd agent
cp .env.example .env
# Edit .env:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, HERA_KB_ID
#   (optional AWS_SESSION_TOKEN if your creds are short-lived)

uv sync --frozen
uv run python -m hera_agent.main
# starts uvicorn on http://localhost:8080
# /ping -> {"status":"Healthy", ...}
# /ws   -> Pipecat WebSocket endpoint
```

*Source: bin/run-agent-local.sh — Phase 2 Plan 02-01*

Resolve `HERA_KB_ID` từ `terraform -chdir=infra/envs/prod output -raw kb_id` (KB id từ Phần 3.1). Region default `ap-northeast-1` qua env `AWS_REGION`.

## Bước 2: Chạy local theo Docker compose path

Path mirror Phase 3 deploy — same image artifact (multi-arch buildx) sẽ được push lên ECR cho AgentCore Runtime.

```bash
docker compose up
# agent     -> http://localhost:8080
# frontend  -> http://localhost:8000
```

*Source: docker-compose.yml — Phase 2 Plan 02-02*

`docker-compose.yml` dùng env-var REQUIRED-syntax `${VAR:?msg}` cho `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `HERA_KB_ID` — nếu thiếu, container fail-fast với message rõ ràng trước khi start. Region default `ap-northeast-1` qua `AWS_REGION:-ap-northeast-1`.

## Bước 3: Smoke test latency (AGT-04 gate)

`bin/smoke-voice.sh` brings up docker-compose stack, mở WebSocket tới `ws://localhost:8080/ws`, send 1 giây synthetic 16 kHz Int16 silence, đo first inbound binary frame. Exit 0 chỉ khi `LATENCY_MS < 3000`.

```bash
bash bin/smoke-voice.sh
# probe brings up docker compose stack, opens WS to ws://localhost:8080/ws,
# sends 1s of synthetic 16 kHz Int16 silence, awaits first inbound binary frame
# OK: AGT-04 latency gate passed
```

*Source: bin/smoke-voice.sh — Phase 2 Plan 02-02*

Tại lần đo của instructor ở `ap-northeast-1` + KB của họ, kết quả là `LATENCY_MS=0` (Sonic phản hồi essentially synchronously với end-of-send trong silence streaming phase). KB của bạn (`<your-kb-id>` — resolve qua `terraform -chdir=infra/envs/prod output -raw kb_id`) có thể cho `LATENCY_MS` khác phụ thuộc network latency tới `ap-northeast-1` từ vị trí của bạn; bất kỳ giá trị nào dưới `3000` (AGT-04 gate) đều pass. Chạy 1 lần là đủ — agent sẵn sàng cho Phần 3.3 deploy lên AgentCore.

## Browser test bằng tay

Mở `http://localhost:8000` trong Chrome hoặc Edge (Firefox đã từng có AudioWorklet quirks; Chromium-based browsers là smoke-test default). Click "Allow" cho microphone permission, click "Record", và hỏi:

> Do you have MacBook Pro?

Sonic gọi `lookup_product` ở Phase 1 KB và phát trả lời Apple-Store-style với stock + price của MacBook Pro M4. Phần 3.4 sẽ deploy widget này lên CloudFront để bạn dùng URL HTTPS thay vì localhost — yêu cầu HTTPS cho microphone là constraint của browser, không phải lỗi cấu hình.

## Cleanup local Docker resources

```bash
docker compose down
docker image rm hera-agent:dev 2>/dev/null || true
docker image prune -f
```

*Source: RUNBOOK.md (Cleanup local Docker resources) — Phase 2 Plan 02-02*

Pipecat agent không có persistent state (D-21 mandates in-memory only), nên không có gì phải backup giữa các run. KB và S3 bucket Phase 1 không bị tác động bởi các lệnh trên — Phase 1 cleanup là `terraform destroy` riêng.

## Tiếp theo

Agent đã chạy local end-to-end với KB Phase 1. Phần 3.3 sẽ build container multi-arch + push ECR + deploy AgentCore Runtime để cùng image chạy trên cloud, exposed qua Lambda presign + CloudFront cho browser kết nối qua URL HTTPS.
