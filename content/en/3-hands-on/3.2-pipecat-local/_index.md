---
title: "3.2 Pipecat Local"
date: 2025-01-01
weight: 2
---

## Goal of this section

Run the Pipecat agent on your laptop, open a local browser that connects to the agent over WebSocket, ask "Do you have MacBook Pro?" → Sonic calls the `lookup_product` tool against the Section 3.1 KB → Sonic plays back the audio response. Latency p95 from end-of-utterance to first audio chunk under 3 seconds (AGT-04 gate).

## Agent project structure

A Python 3.12 project managed by `uv`, no auto-magic framework — every WebSocket connection runs an independent Pipecat pipeline (Pattern P1).

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

Python 3.12 is mandatory — the Pipecat `aws-nova-sonic` extra has marker `python_version>='3.12'`; on 3.11 the extra silently no-ops and `aws_sdk_bedrock_runtime` is missing from the lockfile, so the agent ImportErrors at runtime. Pipecat 1.1.0 is pinned exactly so the workshop is not broken by an upstream major bump.

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

The same app shape deploys to AgentCore Runtime in Section 3.3 with no transport refactor. `/ping` is the AgentCore healthcheck, `/invocations` matches the AgentCore HTTP data-plane contract (a static stub because the voice loop runs on `/ws`), and `/ws` is the Pipecat WebSocket endpoint the browser connects to.

## prompts.py: Apple Store assistant persona (English)

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

Sonic stays in an English persona; chatbot speech is English (D-17 Phase 2). Workshop docs remain bilingual vi/en, but audio output is always English.

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

The tool uses `numberOfResults=3`, filters out chunks below threshold 0.4, and returns the sentinel `"no relevant product info"` when the KB returns nothing. boto3 is sync, so the handler dispatches via `asyncio.to_thread` to avoid blocking the Pipecat event loop (Pitfall F).

{{% notice warning %}}
**Tool-use schema must be strict:** Sonic calls tools based on the JSON schema you register. A wrong schema (missing field, wrong type, extra key) → Sonic raises a validation error mid-stream and the voice loop drops audio. The schema must match Pipecat 1.1.0's `FunctionSchema`; see `register_function("lookup_product", handler, cancel_on_interruption=False)` in `pipeline.py`. `cancel_on_interruption=False` matters — the KB call takes ~400ms; cancel + re-fire on every barge-in wastes user-perceived latency (Pitfall H).

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

`AWSNovaSonicLLMService` uses `StaticCredentialsResolver` internally — it does NOT follow the boto3 default chain directly (Pitfall B). The code resolves credentials through the boto3 chain (env vars → `~/.aws` → IMDSv2) and passes them in as static kwargs, so the same image runs in both local docker-compose (env vars) and AgentCore Runtime (IMDSv2).

{{% notice warning %}}
**8 minutes Sonic stream cap:** Amazon Nova 2 Sonic terminates each single bidirectional stream after ~8 minutes (~480 seconds). Pipecat `SessionContinuationParams(transition_threshold_seconds=360)` automatically rotates the stream ~120 seconds before the cap with no audible interruption. If you comment out this param, conversations longer than 8 minutes break mid-sentence with no warning.

*Source: agent/hera_agent/pipeline.py — Phase 2 Plan 02-01*
{{% /notice %}}

{{% notice info %}}
**Audio sample rate is fixed:** input 16 kHz mono PCM Int16 (browser AudioWorklet), output 24 kHz mono PCM (Sonic). Pipecat 1.1.0 defaults are correct — do not instantiate `AudioConfig` in code. Misconfigure (for instance 22.05 kHz to match the browser AudioContext default) and audio comes out "chipmunk" or transcription silently fails. The browser Worklet handles anti-alias LPF + decimation from 48 kHz down to 16 kHz.

*Source: frontend/audio-capture-worklet.js — Phase 2 Plan 02-02*
{{% /notice %}}

## Step 1: Run locally via uv path

The fastest path for dev iteration — no container build; on every code change just Ctrl+C and rerun.

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

Resolve `HERA_KB_ID` from `terraform -chdir=infra/envs/prod output -raw kb_id` (the KB id from Section 3.1). Region default `ap-northeast-1` via env `AWS_REGION`.

## Step 2: Run locally via Docker compose path

This path mirrors Phase 3 deploy — the same image artifact (multi-arch buildx) is what gets pushed to ECR for AgentCore Runtime.

```bash
docker compose up
# agent     -> http://localhost:8080
# frontend  -> http://localhost:8000
```

*Source: docker-compose.yml — Phase 2 Plan 02-02*

`docker-compose.yml` uses REQUIRED-syntax `${VAR:?msg}` for `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `HERA_KB_ID` — if missing, the container fail-fasts with a clear message before start. Region default `ap-northeast-1` via `AWS_REGION:-ap-northeast-1`.

## Step 3: Smoke test latency (AGT-04 gate)

`bin/smoke-voice.sh` brings up the docker-compose stack, opens a WebSocket to `ws://localhost:8080/ws`, sends 1 second of synthetic 16 kHz Int16 silence, and times the first inbound binary frame. Exits 0 only when `LATENCY_MS < 3000`.

```bash
bash bin/smoke-voice.sh
# probe brings up docker compose stack, opens WS to ws://localhost:8080/ws,
# sends 1s of synthetic 16 kHz Int16 silence, awaits first inbound binary frame
# OK: AGT-04 latency gate passed
```

*Source: bin/smoke-voice.sh — Phase 2 Plan 02-02*

At the instructor's measurement on `ap-northeast-1` + their KB, the result was `LATENCY_MS=0` (Sonic responded essentially synchronously with end-of-send during the silence streaming phase). Your KB (`<your-kb-id>` — resolve via `terraform -chdir=infra/envs/prod output -raw kb_id`) may produce a different `LATENCY_MS` depending on network latency from your location to `ap-northeast-1`; any value under `3000` (AGT-04 gate) passes. Run once is enough — the agent is ready for Section 3.3 AgentCore deploy.

## Manual browser test

Open `http://localhost:8000` in Chrome or Edge (Firefox has had AudioWorklet quirks; Chromium-based browsers are the smoke-test default). Click "Allow" on the microphone permission prompt, click "Record", and ask:

> Do you have MacBook Pro?

Sonic calls `lookup_product` against the Phase 1 KB and plays back an Apple-Store-style answer with the in-stock MacBook Pro M4 configurations. Section 3.4 will deploy this widget to CloudFront so you can use an HTTPS URL instead of localhost — the HTTPS-for-microphone requirement is a browser constraint, not a configuration error.

## Clean up local Docker resources

```bash
docker compose down
docker image rm hera-agent:dev 2>/dev/null || true
docker image prune -f
```

*Source: RUNBOOK.md (Cleanup local Docker resources) — Phase 2 Plan 02-02*

The Pipecat agent has no persistent state (D-21 mandates in-memory only), so there is nothing to back up between runs. The Phase 1 KB and S3 buckets are untouched by the commands above — Phase 1 cleanup is a separate `terraform destroy`.

## Next

The agent runs locally end-to-end against the Phase 1 KB. Section 3.3 builds the multi-arch container + pushes to ECR + deploys to AgentCore Runtime so the same image runs in the cloud, exposed via Lambda presign + CloudFront so the browser can connect over an HTTPS URL.
