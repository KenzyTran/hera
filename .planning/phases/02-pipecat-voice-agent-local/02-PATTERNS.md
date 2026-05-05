# Phase 2: Pipecat Voice Agent (Local) - Pattern Map

**Mapped:** 2026-05-05
**Files analyzed:** 20 new/modified files
**Analogs found:** 5 / 20 (in-repo); 15 / 20 are greenfield with external reference patterns from RESEARCH.md

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `agent/hera_agent/main.py` | Pipecat entrypoint + FastAPI app | request-response (WS + HTTP) | RESEARCH.md Pattern 4 + Complete example (lines 372–733) | greenfield — external reference |
| `agent/hera_agent/pipeline.py` | Pipecat pipeline builder | event-driven (audio frame pipeline) | RESEARCH.md Pattern 5 (lines 403–469) | greenfield — external reference |
| `agent/hera_agent/tools.py` | KB retrieve tool | request-response (boto3 sync) | `bin/verify-kb.sh` lines 78–111 | role-match (bash → Python) |
| `agent/hera_agent/prompts.py` | System prompt constant | config/data | RESEARCH.md D-17 spec | greenfield — no analog |
| `agent/hera_agent/config.py` | Env var reader | config | `bin/verify-kb.sh` lines 37–45 | partial-match (bash → Python) |
| `agent/hera_agent/__init__.py` | Package marker | utility | none | greenfield |
| `agent/pyproject.toml` | uv project manifest | config | none in repo | greenfield — external reference |
| `agent/uv.lock` | Generated lockfile | config | none in repo | greenfield — generated artifact |
| `agent/Dockerfile` | Multi-arch container image | config | RESEARCH.md Dockerfile example (lines 736–771) | greenfield — external reference |
| `agent/.dockerignore` | Docker build exclusions | config | none in repo | greenfield |
| `agent/.env.example` | Env var documentation | config | none in repo | greenfield |
| `docker-compose.yml` | Local 2-service stack | config | RESEARCH.md docker-compose example (lines 781–808) | greenfield — external reference |
| `frontend/index.html` | Browser test page | frontend asset | none in repo | greenfield — external reference |
| `frontend/app.js` | WS client + audio wiring | frontend, event-driven | RESEARCH.md Pattern 6 + Pattern 7 (lines 471–542) | greenfield — external reference |
| `frontend/audio-capture-worklet.js` | 16 kHz Int16 downsampler | frontend, transform | RESEARCH.md Pattern 6 (lines 476–500) | greenfield — external reference |
| `frontend/nginx.conf` | nginx static-file config | config | none in repo | greenfield — no analog |
| `infra/modules/kb_consumer_policy/main.tf` | IAM managed policy module | IAM/Terraform | `infra/modules/knowledge_base/iam.tf` lines 38–96 | role-match (inline policy → managed policy) |
| `infra/modules/kb_consumer_policy/variables.tf` | Module input variables | Terraform config | `infra/modules/knowledge_base/variables.tf` lines 1–17 | exact |
| `infra/modules/kb_consumer_policy/outputs.tf` | Module outputs | Terraform config | `infra/modules/knowledge_base/outputs.tf` lines 1–19 | exact |
| `infra/envs/prod/main.tf` | Root env — module call (modify) | Terraform root | `infra/envs/prod/main.tf` lines 5–11 | exact |
| `infra/envs/prod/outputs.tf` | Root env — add output (modify) | Terraform root | `infra/envs/prod/outputs.tf` lines 1–19 | exact |
| `bin/run-agent-local.sh` | Local dev preflight + run helper | bash utility | `bin/verify-kb.sh` lines 1–66 | role-match |
| `RUNBOOK.md` | Operational doc extension (modify) | documentation | `RUNBOOK.md` existing sections | exact (extend pattern) |

---

## Pattern Assignments

### `agent/hera_agent/main.py` (Pipecat entrypoint, request-response)

**Analog:** RESEARCH.md `## Code Examples — Complete agent/main.py` (lines 623–733)
**Why:** RESEARCH.md assembles the canonical main.py from Patterns 1–5, cross-referenced against `pipecat-ai/pipecat /examples/realtime/realtime-aws-nova-sonic.py @ v1.1.0`. No in-repo Python exists.
**What to change vs analog:** Split the monolithic example into `main.py` (FastAPI app + ws route) and `pipeline.py` (pipeline builder) per RESEARCH.md recommended project structure (lines 229–262). Move KB constants and `_kb_retrieve` to `tools.py`. Move `SYSTEM_PROMPT` to `prompts.py`. Move env var reading to `config.py`.

**Imports pattern** (from RESEARCH.md lines 628–652):
```python
import asyncio
import os
from datetime import datetime
from pathlib import PurePosixPath

import boto3
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from loguru import logger

from pipecat.adapters.schemas.function_schema import FunctionSchema
from pipecat.adapters.schemas.tools_schema import ToolsSchema
from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.frames.frames import LLMRunFrame
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.aggregators.llm_response_universal import (
    LLMContextAggregatorPair, LLMUserAggregatorParams,
)
from pipecat.services.aws.nova_sonic.llm import AWSNovaSonicLLMService
from pipecat.services.aws.nova_sonic.session_continuation import SessionContinuationParams
from pipecat.services.llm_service import FunctionCallParams
from pipecat.transports.websocket.fastapi import (
    FastAPIWebsocketParams, FastAPIWebsocketTransport,
)
```

**FastAPI /ping + /ws pattern** (from RESEARCH.md lines 683–733):
```python
app = FastAPI()

@app.get("/ping")
async def ping():
    return {"status": "Healthy", "time_of_last_update": int(datetime.now().timestamp())}

@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket):
    await websocket.accept()
    logger.info("WS client connected")
    # ... build transport, llm, pipeline per-connection (one pipeline per session)
    try:
        await PipelineRunner(handle_sigint=False).run(task)
    except WebSocketDisconnect:
        pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

---

### `agent/hera_agent/pipeline.py` (pipeline builder, event-driven)

**Analog:** RESEARCH.md Pattern 5 (lines 403–469)
**Why:** Pattern 5 is the canonical `FastAPIWebsocketTransport` pipeline assembly, derived from Pipecat's `realtime-aws-nova-sonic.py` example adapted for FastAPI.
**What to change vs analog:** Extract into a standalone `build_pipeline()` / `run_pipeline(websocket)` function; import `llm` from a builder in `main.py`; import `TOOLS` from `tools.py`.

**Core pipeline pattern** (from RESEARCH.md lines 425–468):
```python
async def run_pipeline(websocket):
    transport = FastAPIWebsocketTransport(
        websocket=websocket,
        params=FastAPIWebsocketParams(
            audio_in_enabled=True,
            audio_out_enabled=True,
            add_wav_header=False,
        ),
    )
    llm = build_llm()   # AWSNovaSonicLLMService construction (Pattern 1)
    llm.register_function("lookup_product", lookup_product_handler, cancel_on_interruption=False)

    context = LLMContext(tools=tools)
    user_agg, asst_agg = LLMContextAggregatorPair(
        context,
        user_params=LLMUserAggregatorParams(vad_analyzer=SileroVADAnalyzer()),
    )
    pipeline = Pipeline([
        transport.input(),
        user_agg,
        llm,
        transport.output(),
        asst_agg,
    ])
    task = PipelineTask(pipeline, params=PipelineParams(
        enable_metrics=True,
        enable_usage_metrics=True,
    ))

    @transport.event_handler("on_client_connected")
    async def on_connected(transport, client):
        context.add_message({"role": "developer", "content": "Greet the user briefly."})
        await task.queue_frames([LLMRunFrame()])

    @transport.event_handler("on_client_disconnected")
    async def on_disconnected(transport, client):
        await task.cancel()

    await PipelineRunner(handle_sigint=False).run(task)
```

**LLM construction pattern** (from RESEARCH.md Pattern 1, lines 276–290):
```python
llm = AWSNovaSonicLLMService(
    secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
    access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
    session_token=os.getenv("AWS_SESSION_TOKEN"),  # optional
    region=os.environ.get("AWS_REGION", "ap-northeast-1"),
    settings=AWSNovaSonicLLMService.Settings(
        voice="matthew",
        system_instruction=SYSTEM_PROMPT,
    ),
    session_continuation=SessionContinuationParams(
        transition_threshold_seconds=360,
    ),
)
```

---

### `agent/hera_agent/tools.py` (KB retrieve tool, request-response)

**Analog:** `bin/verify-kb.sh` lines 37–45 (env defaults), lines 78–111 (retrieve call + score filter)
**Why:** `verify-kb.sh` makes the exact same `bedrock-agent-runtime retrieve` call with the same query shape, `numberOfResults=3`, and `HERA_KB_SCORE_THRESHOLD` threshold. The Python version is a 1:1 translation.
**What to change vs analog:** Translate bash to Python; add `asyncio.to_thread` offload (Pitfall F); format response as `Source: <basename>\n<text>` per D-18 (verify-kb.sh only checks the score, does not format).

**Env var defaults pattern** (from `bin/verify-kb.sh` lines 37–45):
```bash
REGION="${HERA_REGION:-ap-northeast-1}"
THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"
KB_ID=""
```
Translate to Python as:
```python
_KB_ID = os.environ["HERA_KB_ID"]         # required; fail fast if missing
_THRESHOLD = float(os.environ.get("HERA_KB_SCORE_THRESHOLD", "0.4"))
_REGION = os.environ.get("AWS_REGION", "ap-northeast-1")
_kb = boto3.client("bedrock-agent-runtime", region_name=_REGION)
```

**Retrieve call + score filter pattern** (from `bin/verify-kb.sh` lines 78–99, translated to Python per RESEARCH.md Pattern 3 lines 350–368):
```python
def kb_retrieve_sync(query: str) -> str:
    """Retrieve from Bedrock KB; return formatted chunks or sentinel string."""
    resp = _kb.retrieve(
        knowledgeBaseId=_KB_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": 3}},
    )
    chunks = [
        r for r in resp.get("retrievalResults", [])
        if r.get("score", 0) >= _THRESHOLD
    ]
    if not chunks:
        return "no relevant product info"
    return "\n\n".join(
        f"Source: {PurePosixPath(r['location']['s3Location']['uri']).name}\n{r['content']['text']}"
        for r in chunks
    )

async def lookup_product_handler(params: FunctionCallParams):
    """Pipecat tool handler; offloads sync boto3 call to a thread."""
    result = await asyncio.to_thread(kb_retrieve_sync, params.arguments["query"])
    await params.result_callback(result)
```

**Tool schema pattern** (from RESEARCH.md Pattern 2, lines 303–320):
```python
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

---

### `agent/hera_agent/prompts.py` (system prompt constant, config)

**Analog:** None in repo. RESEARCH.md D-17 defines the persona spec.
**Why:** No existing prompt files in repo. D-17 is the only spec.
**What to change vs analog:** Author the literal SYSTEM_PROMPT string during execution following D-17: crisp associate, 2–3 example Q/A pairs, no filler words.

**Pattern** (module shape):
```python
SYSTEM_PROMPT = """
You are a crisp Apple Store associate. Get to the answer fast.
Greeting: short opener, e.g. "Hi, what can I check for you?"
Product replies: 1-2 sentences plus the relevant stock numbers.
Refuse non-Apple questions in 1 line: "I only handle Apple product questions — anything else?"
Never use filler words like "absolutely" or "great question".

Examples:
Q: Do you have iPhone 15 Pro Max in stock?
A: Yes — iPhone 15 Pro Max (256 GB, Natural Titanium) is available, SKU IP15PM-256-NAT.

Q: What's the price of the MacBook Pro 14-inch M3?
A: The MacBook Pro 14-inch M3 starts at $1,599. The M3 Pro config is $1,999.

Q: Can you help me with my Netflix subscription?
A: I only handle Apple product questions — anything else?
"""
```

---

### `agent/hera_agent/config.py` (env var reader, config)

**Analog:** `bin/verify-kb.sh` lines 37–45 (env defaults + arg parsing)
**Why:** verify-kb.sh is the only existing config-reading pattern in the repo; Python version mirrors the same env var names and defaults.
**What to change vs analog:** Python module, not bash; use `os.environ` / `os.getenv`; raise `KeyError` on missing required vars (fail-fast per AGENTS.md; no defensive default for `HERA_KB_ID`).

**Pattern:**
```python
import os

KB_ID: str = os.environ["HERA_KB_ID"]                             # required
KB_SCORE_THRESHOLD: float = float(os.environ.get("HERA_KB_SCORE_THRESHOLD", "0.4"))
AWS_REGION: str = os.environ.get("AWS_REGION", "ap-northeast-1")
```

---

### `agent/pyproject.toml` (uv project manifest, config)

**Analog:** None in repo (greenfield Python).
**Why:** First Python project file in the repo; no prior pyproject.toml exists.
**What to change vs analog:** Follow RESEARCH.md Standard Stack (lines 107–115): `requires-python = ">=3.12"`, pipecat-ai extras `[aws-nova-sonic,silero,websocket]` pinned at `==1.1.0`, boto3 latest, fastapi, uvicorn[standard]. Dev deps: pytest, pytest-asyncio, ruff.

**Pattern** (from RESEARCH.md lines 134–139):
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

[tool.uv]
dev-dependencies = [
    "pytest",
    "pytest-asyncio",
    "ruff",
]
```

---

### `agent/Dockerfile` (multi-arch container, config)

**Analog:** RESEARCH.md Dockerfile example (lines 736–771)
**Why:** RESEARCH.md provides the complete, verified Dockerfile for `ghcr.io/astral-sh/uv:python3.12-trixie-slim` with multi-arch buildx, `uv sync --frozen`, non-root user, HEALTHCHECK, and CMD.
**What to change vs analog:** Use as-is; confirm `hera_agent/` package path matches the `COPY` instruction.

**Core pattern** (from RESEARCH.md lines 740–770):
```dockerfile
# syntax=docker/dockerfile:1.7
FROM ghcr.io/astral-sh/uv:python3.12-trixie-slim AS base

ARG TARGETPLATFORM
ARG BUILDPLATFORM

WORKDIR /app

# Layer 1: dependencies (cached unless pyproject.toml or uv.lock change)
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --frozen --no-install-project

# Layer 2: project source
COPY hera_agent /app/hera_agent
COPY pyproject.toml uv.lock /app/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/ping').read()"]

CMD ["uvicorn", "hera_agent.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

---

### `docker-compose.yml` (local 2-service stack, config)

**Analog:** RESEARCH.md docker-compose example (lines 781–808)
**Why:** RESEARCH.md provides the complete shape per D-20: agent on 8080, frontend nginx:alpine on 8000, env passthrough with required-var syntax.
**What to change vs analog:** Use as-is. Confirm `./frontend` volume mount path is correct relative to repo root.

**Core pattern** (from RESEARCH.md lines 782–808):
```yaml
services:
  agent:
    build: ./agent
    image: hera-agent:dev
    ports:
      - "8080:8080"
    environment:
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:?need AWS_ACCESS_KEY_ID in shell or .env}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:?need AWS_SECRET_ACCESS_KEY}
      AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN:-}
      AWS_REGION: ap-northeast-1
      HERA_KB_ID: ${HERA_KB_ID:?need HERA_KB_ID (e.g. BKXE19AH89)}
      HERA_KB_SCORE_THRESHOLD: "0.4"
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/ping').read()"]
      interval: 30s
      timeout: 3s
      retries: 3
  frontend:
    image: nginx:alpine
    ports:
      - "8000:80"
    volumes:
      - ./frontend:/usr/share/nginx/html:ro
```

---

### `frontend/audio-capture-worklet.js` (16 kHz Int16 downsampler, transform)

**Analog:** RESEARCH.md Pattern 6 (lines 476–500)
**Why:** Pattern 6 is the exact AudioWorklet downsampler shape for 48 kHz → 16 kHz Float32 → Int16, verified against the aws-samples reference repo.
**What to change vs analog:** Use as-is; register as `"capture-processor"`.

**Core pattern** (from RESEARCH.md lines 476–500):
```javascript
class CaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.targetRate = 16000;
  }
  process(inputs) {
    const input = inputs[0];
    if (!input || input.length === 0) return true;
    const channel = input[0];  // mono
    const ratio = sampleRate / this.targetRate;
    const outLen = Math.floor(channel.length / ratio);
    const out = new Int16Array(outLen);
    for (let i = 0; i < outLen; i++) {
      const s = channel[Math.floor(i * ratio)];
      out[i] = Math.max(-32768, Math.min(32767, Math.floor(s * 32767)));
    }
    this.port.postMessage(out.buffer, [out.buffer]);
    return true;
  }
}
registerProcessor("capture-processor", CaptureProcessor);
```

---

### `frontend/app.js` (WS client + audio wiring, event-driven)

**Analog:** RESEARCH.md Pattern 6 (lines 502–514) + Pattern 7 (lines 520–541)
**Why:** Both patterns are verified WS client + AudioWorklet wiring + 24 kHz playback queue from the aws-samples reference and web.dev patterns.
**What to change vs analog:** Combine into a single `app.js`; add record button event listener; add transcript panel update logic.

**Capture and send pattern** (from RESEARCH.md lines 502–514):
```javascript
const ws = new WebSocket("ws://localhost:8080/ws");
ws.binaryType = "arraybuffer";
const ac = new AudioContext();
await ac.audioWorklet.addModule("audio-capture-worklet.js");
const stream = await navigator.mediaDevices.getUserMedia({
    audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true }
});
const source = ac.createMediaStreamSource(stream);
const node = new AudioWorkletNode(ac, "capture-processor");
source.connect(node);
node.port.onmessage = (e) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(e.data);
};
```

**Playback queue pattern** (from RESEARCH.md lines 522–541):
```javascript
const playCtx = new AudioContext({ sampleRate: 24000 });
let nextStart = playCtx.currentTime;
ws.onmessage = (event) => {
    if (typeof event.data === "string") return;  // control/transcript frame
    const int16 = new Int16Array(event.data);
    const float32 = new Float32Array(int16.length);
    for (let i = 0; i < int16.length; i++) float32[i] = int16[i] / 32768;
    const buffer = playCtx.createBuffer(1, float32.length, 24000);
    buffer.copyToChannel(float32, 0);
    const src = playCtx.createBufferSource();
    src.buffer = buffer;
    src.connect(playCtx.destination);
    const startAt = Math.max(playCtx.currentTime, nextStart);
    src.start(startAt);
    nextStart = startAt + buffer.duration;
};
```

---

### `infra/modules/kb_consumer_policy/main.tf` (IAM managed policy module, CRUD)

**Analog:** `infra/modules/knowledge_base/iam.tf` lines 38–96
**Why:** `iam.tf` uses `data "aws_iam_policy_document"` blocks + `aws_iam_role_policy` resource with the same zero-wildcard, enumerated-Action discipline (D-13). The new module uses `aws_iam_policy` (managed, not inline) — same jsonencode pattern.
**What to change vs analog:** Use `aws_iam_policy` resource (not `aws_iam_role_policy`); single-statement policy with `Action = "bedrock:Retrieve"` and `Resource = var.kb_arn`; no `data "aws_caller_identity"` needed since we're not constructing ARNs here; no role attachment in Phase 2.

**IAM policy document pattern** (from `infra/modules/knowledge_base/iam.tf` lines 38–52 — inline document shape to mirror with jsonencode):
```hcl
# iam.tf pattern to mirror (inline policy with enumerated Actions, zero wildcards):
data "aws_iam_policy_document" "kb_inline" {
  statement {
    sid       = "S3SourceListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.source.arn]
  }
  # ... more statements
}
resource "aws_iam_role_policy" "kb_inline" {
  name   = "${var.name_prefix}-kb-inline"
  role   = aws_iam_role.kb_service_role.id
  policy = data.aws_iam_policy_document.kb_inline.json
}
```
New module uses `jsonencode` directly (per RESEARCH.md lines 823–835) to stay self-contained:
```hcl
resource "aws_iam_policy" "kb_retrieve" {
  name        = var.name
  description = "Grants bedrock:Retrieve on the hera-kb (Phase 2 ships, Phase 3 attaches)."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "RetrieveFromHeraKB"
      Effect   = "Allow"
      Action   = "bedrock:Retrieve"
      Resource = var.kb_arn
    }]
  })
}
```

---

### `infra/modules/kb_consumer_policy/variables.tf` (module inputs, Terraform config)

**Analog:** `infra/modules/knowledge_base/variables.tf` lines 1–17
**Why:** Exact same pattern: `variable` blocks with `description`, `type = string`, optional `default`.
**What to change vs analog:** Only two variables: `kb_arn` (required, no default — must pass explicitly) and `name` (optional, default `"hera-kb-retrieve-prod"`).

**Variable pattern** (from `infra/modules/knowledge_base/variables.tf` lines 1–17):
```hcl
variable "name_prefix" {
  description = "Prefix for all named resources..."
  type        = string
  default     = "hera"
}
variable "region" {
  description = "AWS region for ARN constructions..."
  type        = string
  default     = "ap-northeast-1"
}
```
New module mirrors this shape:
```hcl
variable "kb_arn" {
  description = "Bedrock KB ARN to scope bedrock:Retrieve to (zero wildcards per D-13)."
  type        = string
  # no default — caller must pass module.knowledge_base.kb_arn
}
variable "name" {
  description = "Managed policy name."
  type        = string
  default     = "hera-kb-retrieve-prod"
}
```

---

### `infra/modules/kb_consumer_policy/outputs.tf` (module outputs, Terraform config)

**Analog:** `infra/modules/knowledge_base/outputs.tf` lines 1–19
**Why:** Exact same pattern: `output` blocks with `description` and `value`.
**What to change vs analog:** Single output `policy_arn`.

**Output pattern** (from `infra/modules/knowledge_base/outputs.tf` lines 1–9):
```hcl
output "kb_id" {
  description = "Bedrock Knowledge Base ID. Consumed by..."
  value       = aws_bedrockagent_knowledge_base.this.id
}
output "kb_arn" {
  description = "Bedrock Knowledge Base ARN. Used by Phase 2..."
  value       = aws_bedrockagent_knowledge_base.this.arn
}
```
New module mirrors this:
```hcl
output "policy_arn" {
  description = "Managed policy ARN. Phase 3 attaches to the AgentCore execution role."
  value       = aws_iam_policy.kb_retrieve.arn
}
```

---

### `infra/envs/prod/main.tf` (root env module call — modify, Terraform root)

**Analog:** `infra/envs/prod/main.tf` lines 5–11
**Why:** Exact pattern to follow: `module` block with `source` (relative path) and named variable assignments. The existing `knowledge_base` module call is the template.
**What to change vs analog:** Add a second `module` block for `kb_consumer_policy`; source is `../../modules/kb_consumer_policy`; pass `kb_arn = module.knowledge_base.kb_arn`.

**Existing pattern** (from `infra/envs/prod/main.tf` lines 5–11):
```hcl
module "knowledge_base" {
  source = "../../modules/knowledge_base"

  name_prefix = var.name_prefix
  env         = var.env
  region      = var.region
}
```
Addition to append:
```hcl
module "kb_consumer_policy" {
  source = "../../modules/kb_consumer_policy"

  kb_arn = module.knowledge_base.kb_arn
}
```

---

### `infra/envs/prod/outputs.tf` (root env outputs — modify, Terraform root)

**Analog:** `infra/envs/prod/outputs.tf` lines 1–19
**Why:** Exact pattern: `output` block with `description` and `value` referencing a module attribute.
**What to change vs analog:** Add one output `kb_retrieve_policy_arn` pointing to `module.kb_consumer_policy.policy_arn`.

**Existing pattern** (from `infra/envs/prod/outputs.tf` lines 1–9):
```hcl
output "kb_id" {
  description = "Bedrock Knowledge Base ID."
  value       = module.knowledge_base.kb_id
}
output "kb_arn" {
  description = "Bedrock Knowledge Base ARN. Consumed by Phase 2..."
  value       = module.knowledge_base.kb_arn
}
```
Addition to append:
```hcl
output "kb_retrieve_policy_arn" {
  description = "Managed policy ARN; Phase 3 attaches to AgentCore execution role."
  value       = module.kb_consumer_policy.policy_arn
}
```

---

### `bin/run-agent-local.sh` (local dev helper, bash utility)

**Analog:** `bin/verify-kb.sh` lines 1–66
**Why:** `verify-kb.sh` is the only in-repo bash script and defines the preflight pattern (set -euo pipefail, command -v checks, env var defaults, clear exit codes). The new script follows the same discipline.
**What to change vs analog:** Purpose changes from KB polling to local agent startup preflight (check docker/docker-compose available, check required env vars set, then exec `docker compose up`). No polling loop.

**Preflight pattern** (from `bin/verify-kb.sh` lines 1–35):
```bash
#!/usr/bin/env bash
# bin/run-agent-local.sh - Phase 2 local agent startup preflight.
set -euo pipefail

# --- preflight: required tools ---
command -v docker         >/dev/null 2>&1 || { echo "ERROR: docker not found on PATH" >&2; exit 2; }
command -v docker compose >/dev/null 2>&1 || { echo "ERROR: docker compose (v2) not found" >&2; exit 2; }

# --- required env vars ---
: "${AWS_ACCESS_KEY_ID:?ERROR: AWS_ACCESS_KEY_ID must be set in shell}"
: "${AWS_SECRET_ACCESS_KEY:?ERROR: AWS_SECRET_ACCESS_KEY must be set in shell}"
: "${HERA_KB_ID:?ERROR: HERA_KB_ID must be set. Run: terraform -chdir=infra/envs/prod output -raw kb_id}"

# --- defaults ---
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export HERA_KB_SCORE_THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"

echo "starting agent stack: agent on :8080, frontend on :8000"
docker compose up --build
```

**Exit code convention** (from `bin/verify-kb.sh` lines 9–12 comment block):
- Exit 0: success
- Exit 1: runtime failure
- Exit 2: argument/preflight error

---

### `RUNBOOK.md` (operational doc extension, documentation)

**Analog:** `RUNBOOK.md` existing structure (lines 1–80 read)
**Why:** Phase 2 sections follow the exact same operational pattern: paste-ready commands, no emojis, English, section headers with action verbs, brief explanatory prose before each command block.
**What to change vs analog:** Append three new sections (do not modify existing sections): "Local agent setup (Phase 2)", "First voice test", "Cleanup local Docker resources". Mirror the prose + code block format from "First deploy" and "First sync" sections.

**Section structure pattern** (from `RUNBOOK.md` lines 39–65):
```markdown
## First deploy

The first deploy creates the source S3 bucket...

```bash
cd infra/envs/prod
terraform init
terraform apply
```

Expected outcome:
- `terraform apply` completes in ~30-60 seconds.
- Outputs: `kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`.
```
New Phase 2 sections follow this structure:
```markdown
## Local agent setup (Phase 2)

Pre-flight: set required env vars and start the Docker Compose stack.

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export HERA_KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
docker compose up --build
```

Expected outcome:
- `agent` container starts on port 8080, `/ping` returns HTTP 200.
- `frontend` container starts on port 8000, browser opens `http://localhost:8000/`.
```

---

## Shared Patterns

### Env Var Naming Convention
**Source:** `bin/verify-kb.sh` lines 37–45
**Apply to:** `agent/hera_agent/config.py`, `docker-compose.yml`, `agent/.env.example`, `bin/run-agent-local.sh`

All project-specific env vars use the `HERA_` prefix: `HERA_KB_ID`, `HERA_KB_SCORE_THRESHOLD`. AWS SDK vars use the standard SDK names (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`). No new env var names invented for Phase 2 — reuse the names from `verify-kb.sh` exactly.

```bash
REGION="${HERA_REGION:-ap-northeast-1}"
THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"
```

### Zero-Wildcard IAM
**Source:** `infra/modules/knowledge_base/iam.tf` lines 38–96 (D-13 mandate)
**Apply to:** `infra/modules/kb_consumer_policy/main.tf`

Every IAM Action and Resource is enumerated precisely. No `*` in Action or Resource. No `"*"` principal. The existing `iam.tf` has three statements, each with exact Action list and exact ARN. The new module has one statement: `Action = "bedrock:Retrieve"`, `Resource = var.kb_arn`.

### Terraform Module Interface Pattern
**Source:** `infra/modules/knowledge_base/variables.tf` + `infra/modules/knowledge_base/outputs.tf`
**Apply to:** `infra/modules/kb_consumer_policy/variables.tf`, `infra/modules/kb_consumer_policy/outputs.tf`

Every variable has a `description` (quoted string) and a `type`. Required variables omit `default`. Every output has a `description` that names the consumer phase. Cross-module references use `module.<name>.<output>` syntax (not data sources or SSM).

### No Emojis, No Defensive Try/Except
**Source:** `CLAUDE.md` + `AGENTS.md` + `bin/verify-kb.sh` (`2>/dev/null` removal lesson commit `f78a39a`)
**Apply to:** All Python files, all bash scripts, RUNBOOK.md additions

No emoji characters anywhere. No bare `try/except Exception: pass` or equivalent. Let exceptions propagate. Add `except` only when the type is known and the handler does something meaningful (e.g., `except WebSocketDisconnect: pass` in the WS route is intentional — it's the normal disconnect path, not error suppression).

### Bash Script Structure
**Source:** `bin/verify-kb.sh` lines 1–35
**Apply to:** `bin/run-agent-local.sh`

All bash scripts: `#!/usr/bin/env bash` shebang, `set -euo pipefail`, `command -v <tool>` preflight with exit 2, env var defaults with `${VAR:-default}` syntax, required vars with `${VAR:?message}`, concise `echo` status lines (no emojis), exit codes (0 = success, 1 = failure, 2 = arg/preflight error).

---

## No Analog Found (greenfield — use RESEARCH.md patterns)

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `agent/hera_agent/prompts.py` | prompt constant | config | No existing prompt files in repo; D-17 is the spec |
| `agent/hera_agent/__init__.py` | package marker | utility | No existing Python packages in repo |
| `agent/uv.lock` | generated lockfile | config | Generated by `uv lock`; no prior Python project |
| `agent/.dockerignore` | Docker build exclusions | config | No Docker artifacts in repo before Phase 2 |
| `agent/.env.example` | env var documentation | config | No prior env documentation files |
| `frontend/index.html` | browser test page | frontend asset | No frontend assets in repo; aws-samples reference repo `frontend/` is the closest external model |
| `frontend/nginx.conf` | nginx static config | config | No nginx in repo; use nginx:alpine default config unless path rewriting is needed (it is not for Phase 2) |

**For the planner:** Files in this table should be authored from scratch using RESEARCH.md Patterns 6–7 and the aws-samples reference repo as external references. The `nginx.conf` file is likely unnecessary — `nginx:alpine` default config serves `/usr/share/nginx/html` which is exactly the volume mount target in docker-compose.yml. Omit the file unless the planner's test reveals a routing requirement.

---

## Metadata

**Analog search scope:** `infra/modules/knowledge_base/`, `infra/envs/prod/`, `bin/`, `RUNBOOK.md`
**In-repo files scanned:** 9 files read (iam.tf, main.tf x2, outputs.tf x2, variables.tf x2, verify-kb.sh, RUNBOOK.md)
**External references used:** RESEARCH.md Patterns 1–7, Complete agent/main.py example, Dockerfile example, docker-compose.yml example, Terraform module examples (all lines 266–855)
**Pattern extraction date:** 2026-05-05
