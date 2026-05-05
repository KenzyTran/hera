---
phase: 02-pipecat-voice-agent-local
plan: 01
subsystem: agent
tags: [pipecat, aws-nova-sonic, bedrock, fastapi, websocket, uv, python-3.12, boto3, knowledge-base]

# Dependency graph
requires:
  - phase: 01-knowledge-base-foundation
    provides: live KB BKXE19AH89 in ap-northeast-1, bin/verify-kb.sh as the retrieve-shape reference, KB ARN that Plan 02-03 will pin in the consumer policy
provides:
  - hera-agent Python package (FastAPI /ping + /ws on port 8080) with Pipecat 1.1.0 + AWSNovaSonicLLMService + lookup_product KB tool
  - agent/pyproject.toml + agent/uv.lock pinning Python 3.12 and pipecat-ai[aws-nova-sonic,silero,websocket]==1.1.0 (consumed by Plan 02-02 Dockerfile uv sync --frozen)
  - bin/run-agent-local.sh launcher for fast local iteration without Docker
  - 11-test pytest suite with mocked boto3 covering D-17 (persona) and D-18 (lookup_product return contract)
affects: [02-02, 02-03, 03-agentcore-deploy]

# Tech tracking
tech-stack:
  added: [pipecat-ai==1.1.0, aws_sdk_bedrock_runtime, boto3, fastapi, uvicorn, websockets, pytest, pytest-asyncio, ruff]
  patterns:
    - "uv-managed Python project under agent/ (mirrors Phase 1 infra/ root layout convention)"
    - "FastAPI single-app /ping + /ws on port 8080 (AgentCore HTTP service contract — Phase 3 reuses this with no transport refactor)"
    - "asyncio.to_thread wrapper for sync boto3 inside async tool handlers (Pitfall F)"
    - "Explicit access_key_id/secret_access_key kwargs to AWSNovaSonicLLMService from os.environ (StaticCredentialsResolver — NOT boto3 default chain — Pitfall B / research correction #3)"
    - "register_function(..., cancel_on_interruption=False) so barge-in does not cancel in-flight KB calls (Pitfall H)"
    - "SessionContinuationParams(transition_threshold_seconds=360) handles AGT-05 (8-min Sonic stream cap) transparently"
    - "Module-level env-var read with KeyError fail-fast for required vars; os.environ.get() with documented defaults for optional (AGENTS.md root-cause discipline)"
    - "MagicMock-based pytest fixtures for boto3 KB client; conftest.py setdefault env vars before any hera_agent import"

key-files:
  created:
    - agent/pyproject.toml
    - agent/uv.lock
    - agent/.env.example
    - agent/.gitignore
    - agent/hera_agent/__init__.py
    - agent/hera_agent/config.py
    - agent/hera_agent/prompts.py
    - agent/hera_agent/tools.py
    - agent/hera_agent/pipeline.py
    - agent/hera_agent/main.py
    - agent/tests/__init__.py
    - agent/tests/conftest.py
    - agent/tests/test_config.py
    - agent/tests/test_lookup_product.py
    - agent/tests/test_prompts.py
    - bin/run-agent-local.sh
  modified: []

key-decisions:
  - "Plan 02-01 ships Python agent core only — no Dockerfile, no docker-compose, no frontend. Plan 02-02 adds those (separation keeps the unit-test loop fast and isolates the multi-arch buildx complexity)."
  - "Python 3.12 mandatory in pyproject.toml requires-python (NOT 3.11 as CONTEXT D-20 originally said) — Pipecat aws-nova-sonic extra has marker python_version>='3.12'; on 3.11 the extra silently no-ops. Research correction #1."
  - "AWS credentials passed as explicit kwargs to AWSNovaSonicLLMService from os.environ — NOT relying on boto3 default credential chain. The service uses StaticCredentialsResolver internally (Pipecat 1.1.0 source verified). Research correction #3 / Pitfall B."
  - "FastAPI single-app shape exposes both GET /ping and WebSocket /ws on the same port 8080 — AgentCore HTTP service contract, Phase 3 reuses with zero refactor. Research correction #4."
  - "lookup_product handler dispatches sync boto3 via await asyncio.to_thread — Pitfall F (boto3 is sync; inline sync inside async pipeline stutters audio playback)."
  - "register_function('lookup_product', handler, cancel_on_interruption=False) — Pitfall H (KB calls take ~400ms; cancelling+re-firing on every barge-in wastes user-perceived latency)."
  - "SessionContinuationParams(transition_threshold_seconds=360) configured explicitly even though it matches Pipecat's default — makes the AGT-05 contract grep-discoverable in pipeline.py."
  - "No AudioConfig instantiation anywhere — Pipecat defaults already satisfy AGT-07 (16 kHz Int16 in / 24 kHz mono out)."
  - "tools.py mirrors bin/verify-kb.sh 1:1 — numberOfResults=3, threshold from HERA_KB_SCORE_THRESHOLD env (default 0.4), 'no relevant product info' sentinel, top-1-first 'Source: <basename>\\n<text>' format joined by blank lines (D-18)."
  - "Only try/except in the codebase is `except WebSocketDisconnect: pass` in /ws handler — that is the normal disconnect path, not error suppression. AGENTS.md mandate honored."
  - "Dev dep websockets declared explicitly in pyproject.toml (already a transitive of Pipecat's websocket extra) so Plan 02-02's bin/_smoke_voice_probe.py has a stable AGT-04 latency-gate import that survives Pipecat-internal swaps."

patterns-established:
  - "FastAPI ASGI app with mixed HTTP + WebSocket routes on one port — pattern reused in Phase 3 AgentCore deploy"
  - "Pipecat per-connection PipelineTask (one LLM instance per WebSocket) with LLMContext for in-process state per AGT-06/D-21"
  - "Sync-boto3-via-asyncio.to_thread for KB Retrieve from a tool handler"
  - "uv project layout under agent/ — pyproject.toml + uv.lock committed for reproducibility (mirrors Phase 1 .terraform.lock.hcl decision)"
  - "Module-level env reads with KeyError fail-fast — same discipline as Phase 1 verify-kb.sh f78a39a (`command -v jq` fail-fast)"

requirements-completed: [AGT-01, AGT-02, AGT-03, AGT-05, AGT-06, AGT-07]

# Metrics
duration: 5min
completed: 2026-05-05
---

# Phase 02 Plan 01: Pipecat Voice Agent Core Summary

**Pipecat 1.1.0 voice agent (FastAPI /ping + /ws on 8080, AWSNovaSonicLLMService with explicit static creds, lookup_product KB tool via asyncio.to_thread) — six AGT requirements satisfied; Plan 02-02 packages this code into a multi-arch container and Plan 02-03 ships the IAM consumer policy.**

## Performance

- **Duration:** ~5 min (per-task commit times: 13:42 → 13:46 local)
- **Started:** 2026-05-05T06:42:16Z
- **Completed:** 2026-05-05T06:46:16Z
- **Tasks:** 3
- **Files modified:** 16 (all created — no edits to existing files; Phase 1 untouched)

## Accomplishments

- uv-managed Python 3.12 project at `agent/` with pinned Pipecat 1.1.0 + AWS Nova Sonic extras; `uv sync --frozen` exits 0 and `uv.lock` contains `aws-sdk-bedrock-runtime` (proves the 3.12 marker resolved correctly).
- Six-module `hera_agent` package: FastAPI app exposing `/ping` (Healthy) and `/ws` (Pipecat pipeline) on port 8080; LLM constructed per-connection with explicit static AWS credentials; `lookup_product` KB tool registered with `cancel_on_interruption=False`; KB call dispatched via `asyncio.to_thread`; `SessionContinuationParams(transition_threshold_seconds=360)` for AGT-05; D-17 "Crisp store associate" SYSTEM_PROMPT with refusal line and 3 example Q/A pairs; `_kb_retrieve` mirrors `bin/verify-kb.sh` (numberOfResults=3, threshold filter, sentinel, top-1-first basename format).
- 11-test pytest suite passes in 2.04 seconds with no live AWS calls — boto3 fully mocked via `monkeypatch.setattr(tools, "_kb", MagicMock())`. Tests cover D-18 (lookup_product return contract: high-score formatting, below-threshold sentinel, empty-results sentinel, retrieve call shape) and D-17 (SYSTEM_PROMPT invariants: Apple mention, refusal line, lookup_product reference) plus config fail-fast on missing HERA_KB_ID.
- `bin/run-agent-local.sh` launcher with verify-kb.sh-style preflight discipline (`set -euo pipefail`, `command -v uv`, fail-fast `${VAR:?}` env-var checks, uv-only — no `pip`, no `python3`); `exec uv run uvicorn hera_agent.main:app --host 0.0.0.0 --port 8080`.

## Task Commits

Each task was committed atomically:

1. **Task 1: uv project bootstrap** — `b606c8e` (feat) — agent/pyproject.toml, agent/uv.lock, agent/.env.example, agent/.gitignore
2. **Task 2: Author hera_agent package** — `a55862d` (feat) — six modules under agent/hera_agent/ (config, prompts, tools, pipeline, main, __init__)
3. **Task 3: Author unit tests + bin/run-agent-local.sh** — `db64e08` (test) — five files under agent/tests/ + bin/run-agent-local.sh

**Plan metadata:** (will be created when this SUMMARY + STATE.md updates are committed)

## Import Chain Verified End-to-End

The full call graph imports cleanly with `HERA_KB_ID=BKXE19AH89 uv run python -c "from hera_agent.main import app"` (Pipecat 1.1.0 banner prints; both `/ping` and `/ws` routes assert-pass):

```
hera_agent.main.app
  -> @app.get("/ping")        (AgentCore health probe)
  -> @app.websocket("/ws")    -> hera_agent.pipeline.run_pipeline(websocket)
                                  -> FastAPIWebsocketTransport
                                  -> AWSNovaSonicLLMService(access_key_id=..., secret_access_key=..., session_continuation=SessionContinuationParams(transition_threshold_seconds=360))
                                  -> llm.register_function("lookup_product", handler, cancel_on_interruption=False)
                                  -> hera_agent.tools.lookup_product_handler(params)
                                       -> asyncio.to_thread(_kb_retrieve, query)
                                            -> boto3 bedrock-agent-runtime.retrieve(knowledgeBaseId=KB_ID, retrievalQuery={"text": query}, retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": 3}})
                                            -> filter score >= KB_SCORE_THRESHOLD; return "no relevant product info" or "Source: <basename>\n<text>" joined by \n\n
```

## Files Created/Modified

**Bootstrap (Task 1):**
- `agent/pyproject.toml` — uv project manifest (Python >=3.12, pipecat-ai[aws-nova-sonic,silero,websocket]==1.1.0, dev deps include websockets for Plan 02-02 smoke probe)
- `agent/uv.lock` — frozen dependency graph (95 packages resolved); contains `aws-sdk-bedrock-runtime` and `websockets`
- `agent/.env.example` — env-var contract documentation (placeholders only, never real secrets)
- `agent/.gitignore` — excludes `.venv/`, `__pycache__/`, `.env`; does NOT exclude `uv.lock`

**Package (Task 2):**
- `agent/hera_agent/__init__.py` — package marker
- `agent/hera_agent/config.py` — env reader, `KB_ID = os.environ["HERA_KB_ID"]` fail-fast, defaults for `KB_SCORE_THRESHOLD` (0.4), `AWS_REGION` (ap-northeast-1), `HERA_VOICE` (matthew)
- `agent/hera_agent/prompts.py` — D-17 SYSTEM_PROMPT (Crisp store associate persona, refusal line, 3 example Q/A pairs)
- `agent/hera_agent/tools.py` — `_kb_retrieve` sync helper (mirrors verify-kb.sh), `lookup_product_handler` async wrapper with `asyncio.to_thread`, `lookup_product_schema` (FunctionSchema), `TOOLS = ToolsSchema(standard_tools=[...])`
- `agent/hera_agent/pipeline.py` — `build_llm()` (explicit static creds + SessionContinuationParams), `run_pipeline(websocket)` (FastAPIWebsocketTransport + Silero VAD + LLMContext + LLMContextAggregatorPair, register_function with cancel_on_interruption=False, on_client_connected/disconnected handlers, PipelineRunner with handle_sigint=False)
- `agent/hera_agent/main.py` — FastAPI app, `GET /ping` (Healthy), `@app.websocket("/ws")` with the only try/except in the codebase (`WebSocketDisconnect`)

**Tests + launcher (Task 3):**
- `agent/tests/__init__.py` — package marker (empty)
- `agent/tests/conftest.py` — `os.environ.setdefault` for required env vars before any hera_agent import; sample retrieve-response fixtures (high-score, below-threshold, empty); `mock_kb_client` monkeypatches `tools._kb`
- `agent/tests/test_config.py` — KeyError on missing HERA_KB_ID, defaults for optional vars (importlib.reload pattern)
- `agent/tests/test_lookup_product.py` — D-18 contract (4 tests: top-1-first basename format, below-threshold sentinel, empty-results sentinel, correct retrieve call args)
- `agent/tests/test_prompts.py` — D-17 invariants (5 tests: prompt non-empty, Apple mention, refusal line, lookup_product mention, forbidden-words rule line is permitted to mention them)
- `bin/run-agent-local.sh` — `set -euo pipefail`, `command -v uv` preflight, `${VAR:?ERROR}` fail-fast for AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/HERA_KB_ID, defaults for AWS_REGION/HERA_KB_SCORE_THRESHOLD/HERA_VOICE, `exec uv run uvicorn hera_agent.main:app --host 0.0.0.0 --port 8080`

## Research Corrections Applied

The four research corrections from `02-RESEARCH.md` were enforced verbatim and grep-checked:

1. **#1 Python 3.12 mandatory** — `requires-python = ">=3.12"` in `agent/pyproject.toml`. `agent/uv.lock` contains `aws-sdk-bedrock-runtime` at line 222 (proves the `python_version>='3.12'` marker on Pipecat's `aws-nova-sonic` extra resolved). On 3.11 this extra silently no-ops.
2. **#3 Explicit static credentials** — `agent/hera_agent/pipeline.py` calls `AWSNovaSonicLLMService(access_key_id=os.environ["AWS_ACCESS_KEY_ID"], secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"], session_token=os.getenv("AWS_SESSION_TOKEN"), region=AWS_REGION, ...)`. Mounting `~/.aws` alone is insufficient because the service uses `StaticCredentialsResolver`, not the boto3 default chain.
3. **#4 Single FastAPI app with /ping + /ws on port 8080** — `agent/hera_agent/main.py` has both `@app.get("/ping")` and `@app.websocket("/ws")` decorators on the same `FastAPI()` instance; uvicorn entry is `uvicorn hera_agent.main:app --host 0.0.0.0 --port 8080`. Phase 3 AgentCore deploy reuses this exact app — no transport refactor.
4. **(Pitfall F) asyncio.to_thread** — `agent/hera_agent/tools.py` line 45: `result = await asyncio.to_thread(_kb_retrieve, params.arguments["query"])`. boto3 is sync; calling it inline from an async tool handler stutters Pipecat's event loop and causes audible audio glitches.

Other guard-rail enforcements:

- **Pitfall H:** `register_function("lookup_product", lookup_product_handler, cancel_on_interruption=False)` in `pipeline.py`.
- **AGT-05 (8-min Sonic cap):** `SessionContinuationParams(transition_threshold_seconds=360)` in `pipeline.py`. Pipecat rotates the bidi stream ~120s before the cap; user perceives no interruption.
- **AGT-07 (audio defaults):** No `AudioConfig(...)` instantiation anywhere — Pipecat defaults satisfy 16 kHz Int16 in / 24 kHz mono out automatically.

## Plan 02-02 Smoke-Probe Dep Confirmed

Per the plan's success criterion #13:

```
$ cd agent && uv run python -c "import websockets; print(websockets.__version__)"
websockets 15.0.1
```

`websockets` is in `agent/uv.lock` line 2170. Plan 02-02's `bin/_smoke_voice_probe.py` (AGT-04 latency gate) will resolve this dep when invoked as `cd agent && uv run python ../bin/_smoke_voice_probe.py`.

## Decisions Made

All decisions are pre-locked by the plan or by the prior-phase context. No new decisions were taken at execution time. The decisions table in the frontmatter mirrors the plan's `must_haves.truths` and `02-RESEARCH.md` corrections; nothing was reinvented during execution.

## Deviations from Plan

None — plan executed exactly as written. All sixteen files contain verbatim the contents the plan specified. The only on-the-fly observation was the `tool.uv.dev-dependencies` deprecation warning emitted by uv 0.10.8 (the field still works; uv suggests `dependency-groups.dev` for forward compatibility). This is **not** a deviation: the plan explicitly specified the `[tool.uv]` block shape, and switching to `dependency-groups.dev` mid-execution would be scope creep into a Plan 02-02-or-later cleanup. Recorded here for the next plan to consider.

The plan's emoji-scan acceptance command in Task 2 used a regex `except\s+(?!WebSocketDisconnect)\w+` that false-positives on prose words like "except in" / "except around" inside docstrings. A line-anchored grep (`^\s*except\s`) returns the only real `except` clause: `agent/hera_agent/main.py:40: except WebSocketDisconnect:`. The contract is satisfied; the original regex is just over-broad. Not changing it now (plan-text fidelity), noting for future plan-checker tightening.

---

**Total deviations:** 0 — plan executed exactly as written.
**Impact on plan:** None.

## Issues Encountered

- **`tool.uv.dev-dependencies` deprecation warning** — uv 0.10.8 prints a warning on every `uv lock` / `uv sync` / `uv run`: `The 'tool.uv.dev-dependencies' field (used in 'pyproject.toml') is deprecated and will be removed in a future release; use 'dependency-groups.dev' instead`. The field still works in uv 0.10.x and the plan specified this exact key. Not changing per scope discipline; flagged for a future minor refactor (not blocking; warning is informational, not an error).
- **Plan's emoji-scan command included `agent/**/*.py` which matches `agent/.venv/**` after sync** — third-party packages like `rich`, `transformers`, `loguru` legitimately contain emoji glyphs in their source files. Resolved by scanning only project files (`agent/hera_agent/**/*.py`, `agent/tests/**/*.py`, `agent/pyproject.toml`, `agent/.env.example`, `bin/run-agent-local.sh`); all project files are clean. `.venv/` is in `agent/.gitignore` so it never enters the repo.

## User Setup Required

None for Plan 02-01. Plan 02-02 will require `docker` + `docker buildx` + AWS credentials in shell or `~/.aws` for the live voice-loop smoke probe (autonomous: false plan).

For local dev with this plan's code, the developer must:

1. Have AWS credentials with Bedrock Nova 2 Sonic model access enabled in `ap-northeast-1` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN`).
2. Set `HERA_KB_ID=BKXE19AH89` (the live Phase 1 KB).
3. Run `bash bin/run-agent-local.sh` from the repo root. The agent listens on `http://localhost:8080/ping` (health) and `ws://localhost:8080/ws` (voice).

There is no browser frontend yet — that arrives in Plan 02-02 alongside the Dockerfile.

## Next Phase Readiness

Plan 02-01 is complete and Wave 1 is half-done.

**Wave 1 status:**
- 02-01 (this plan): complete (commits b606c8e, a55862d, db64e08).
- 02-03 (parallel sibling): not yet started — IAM consumer policy + RUNBOOK.md Phase 2 sections.

**Wave 2 (depends on 02-01 deliverables):**
- 02-02 — multi-arch Dockerfile (linux/arm64 + linux/amd64 via docker buildx, base `ghcr.io/astral-sh/uv:python3.12-trixie-slim`), `docker-compose.yml` two-service stack (`agent` on host 8080, `frontend` on host 8000), minimal browser frontend with AudioWorklet 16 kHz capture and 24 kHz playback, `bin/run-agent-docker.sh`, `bin/_smoke_voice_probe.py` (AGT-04 latency gate, blocks on `LATENCY_MS<3000`). Consumes `agent/uv.lock` and `hera_agent.main:app` directly.

**Phase 3 readiness preview:** The `main.py` shape (FastAPI app with `/ping` + `/ws` on port 8080) is already the AgentCore Runtime HTTP service contract verbatim. Phase 3 deploys this same module path (`hera_agent.main:app`) without a transport refactor.

## Self-Check: PASSED

All sixteen files exist and all three commit hashes are present in `git log`:

- `agent/pyproject.toml`, `agent/uv.lock`, `agent/.env.example`, `agent/.gitignore` — present (commit b606c8e).
- `agent/hera_agent/{__init__,config,prompts,tools,pipeline,main}.py` — present (commit a55862d).
- `agent/tests/{__init__,conftest,test_config,test_lookup_product,test_prompts}.py` and `bin/run-agent-local.sh` — present (commit db64e08).
- `git log --oneline | grep -E "b606c8e|a55862d|db64e08"` returns all three.

Verification block from plan:
- `cd agent && uv sync --frozen` exits 0 (Audited 93 packages in 11ms).
- `HERA_KB_ID=BKXE19AH89 uv run python -c "from hera_agent.main import app; ..."` exits 0 with `OK`.
- `uv run python -c "from pipecat.services.aws.nova_sonic.llm import AWSNovaSonicLLMService"` exits 0.
- `uv run python -c "from pipecat.transports.websocket.fastapi import FastAPIWebsocketTransport, FastAPIWebsocketParams"` exits 0.
- `uv run python -c "import websockets; print(websockets.__version__)"` prints `websockets 15.0.1`.
- `cd agent && uv run pytest -x -q` exits 0 with `11 passed in 2.04s`.
- All seven research-correction greps return matches.
- No emojis in any project file (`.venv/` excluded as per .gitignore).
- No `pip install` or `python3 ` invocations in `agent/hera_agent/`, `agent/tests/`, or `bin/run-agent-local.sh`.
- No `AKIA[0-9A-Z]{16}` patterns anywhere in `agent/`.

---
*Phase: 02-pipecat-voice-agent-local*
*Plan: 01*
*Completed: 2026-05-05*
