---
phase: 06-twilio-bridge-phone-number-cleanup
plan: 02
subsystem: twilio-bridge-container
tags: [twilio, bridge, app-runner, fastapi, audioop, sigv4, python313, uv]
requires:
  - "Phase 6 Plan 06-01 (Wave 1, file-disjoint sibling): Terraform module infra/modules/twilio_bridge/*.tf — ECR repo + App Runner service + IAM instance/access roles + Secrets Manager secret + CloudWatch log group. Plan 06-01's outputs (twilio_bridge_ecr_repository_url + twilio_bridge_wss_url + agentcore_runtime_arn forwarded to instance role) are consumed by Plan 06-03 push + Plan 06-04 deploy."
  - "Live AWS state from Phase 4 — AgentCore Runtime hera_agent-GIsf2P4ImD (version=3, READY) at arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD; KB BKXE19AH89; CloudFront widget URL — UNTOUCHED in Plan 06-02 (D-64)."
provides:
  - "infra/modules/twilio_bridge/Dockerfile — multi-arch (linux/arm64,linux/amd64) container build on uv:0.10.8-python3.13-trixie-slim base; two-layer uv sync; non-root appuser uid 1000; /ping HEALTHCHECK; uvicorn entrypoint on port 8080."
  - "infra/modules/twilio_bridge/pyproject.toml + uv.lock — Python 3.13 project pinning fastapi>=0.115.6,<1 + uvicorn[standard] + websockets>=15 + audioop-lts==0.2.2 + boto3 + botocore + twilio>=9; dev deps pytest>=8 + pytest-asyncio + ruff + httpx; 52 packages resolved in lockfile (1219 lines)."
  - "infra/modules/twilio_bridge/src/main.py — FastAPI app with GET /ping (App Runner health probe) + WebSocket /twilio (D-67 X-Twilio-Signature validation BEFORE accept(); only try/except is for documented WebSocketDisconnect path per AGENTS.md)."
  - "infra/modules/twilio_bridge/src/bridge.py — handle_twilio_call per-call coroutine: drains Twilio connected/start, opens SigV4-signed upstream WSS to bedrock-agentcore /ws with X-Amzn-Bedrock-AgentCore-Runtime-Session-Id = Twilio CallSid, runs concurrent inbound/outbound pumps via asyncio.wait FIRST_COMPLETED, threads ratecv state per direction (Pitfall 4 mitigation), dispatches connected/start/media/stop/mark/dtmf events."
  - "infra/modules/twilio_bridge/src/config.py — env-var resolution (AWS_REGION lazy-default ap-northeast-1; AGENTCORE_RUNTIME_ARN + TWILIO_AUTH_TOKEN required → fail-fast); validate_twilio_signature uses twilio.request_validator.RequestValidator (D-67 — no hand-rolled HMAC) with trailing-slash retry (Pitfall 2)."
  - "infra/modules/twilio_bridge/src/resample.py — twilio_to_sonic + sonic_to_twilio mu-law<->Int16 ratecv pair using audioop-lts shim on Python 3.13 (PEP 594); state threaded across frames within a call."
  - "infra/modules/twilio_bridge/tests/{test_ping,test_signature,test_resample,test_upstream}.py — 10 offline tests (BLOCKER-5 fix) covering /ping smoke + signature validator (valid/tampered/missing) + resample byte-count math + state-threading (Pitfall 4) + SigV4 header construction (auth + x-amz-date + session-id). All pass on uv-managed Python 3.13."
affects:
  - "Plan 06-03 (Wave 2): consumes the Dockerfile + uv.lock + src/ tree from this plan to ship bin/push-bridge-image.sh + bin/cleanup-verify-twilio.sh + RUNBOOK Phase 6 paste-blocks."
  - "Plan 06-04 (Wave 3, autonomous=false with operator checkpoints): consumes Plan 06-03 + 06-01 outputs to run live two-pass terraform apply + dial-in smoke. The default SONIC_OUTPUT_RATE_HZ=16000 in src/bridge.py is the open caveat that the dial-in smoke probes and overrides if live AgentCore data-plane WSS frames at 24000."
tech-stack:
  added:
    - "Python 3.13 (uv-managed) — required by audioop-lts shim because stdlib audioop was removed in 3.13 per PEP 594"
    - "audioop-lts==0.2.2 — verbatim drop-in for stdlib audioop on Python 3.13"
    - "twilio>=9 — RequestValidator for X-Twilio-Signature HMAC (D-67, no hand-rolled HMAC)"
    - "websockets>=15 — outgoing client for upstream bedrock-agentcore WSS (server-side SigV4 signed via SigV4Auth header, NOT SigV4QueryAuth presign — different from widget_presigner)"
    - "httpx — required transitive dep for FastAPI TestClient (Rule 3 fix in Task 1)"
  patterns:
    - "FastAPI single-app shape with /ping + WebSocket route (mirrors agent/hera_agent/main.py verbatim — Pattern S9)"
    - "Bounded WebSocketDisconnect try/except as the ONLY defensive try in the entire bridge source (AGENTS.md mandate; carried forward from Phase 2 D-23)"
    - "uv-managed two-layer Dockerfile: --no-install-project layer + project layer (mirrors agent/Dockerfile pattern; Phase 2 D-20)"
    - "Multi-arch buildx via TARGETPLATFORM/BUILDPLATFORM ARG (NO FROM --platform pin — Pitfall C from Phase 2)"
    - "SigV4Auth (header) on outgoing AWSRequest — mirrors widget_presigner SigV4QueryAuth mechanics but for an outgoing WS upgrade rather than a browser-bound presigned URL"
    - "Per-call ratecv state threaded inside coroutine local scope (in_state owned by inbound pump, out_state by outbound; no shared mutable state, no lock needed — WARNING-3 pattern)"
    - "Fail-fast env vars (os.environ['TWILIO_AUTH_TOKEN'] / os.environ['AGENTCORE_RUNTIME_ARN']) for security-critical config; lazy-default only for AWS_REGION (Phase 2 D-20 pattern)"
key-files:
  created:
    - "infra/modules/twilio_bridge/Dockerfile"
    - "infra/modules/twilio_bridge/pyproject.toml"
    - "infra/modules/twilio_bridge/uv.lock"
    - "infra/modules/twilio_bridge/.dockerignore"
    - "infra/modules/twilio_bridge/src/__init__.py"
    - "infra/modules/twilio_bridge/src/main.py"
    - "infra/modules/twilio_bridge/src/bridge.py"
    - "infra/modules/twilio_bridge/src/config.py"
    - "infra/modules/twilio_bridge/src/resample.py"
    - "infra/modules/twilio_bridge/tests/test_ping.py"
    - "infra/modules/twilio_bridge/tests/test_signature.py"
    - "infra/modules/twilio_bridge/tests/test_resample.py"
    - "infra/modules/twilio_bridge/tests/test_upstream.py"
  modified:
    - ".gitignore — added infra/modules/twilio_bridge/{.venv,__pycache__,**/__pycache__,.pytest_cache,.ruff_cache} (Rule 3 fix; mirrors infra/cdk/ pattern)"
decisions:
  - "Plan 06-02 / Task 1: dev-dependency httpx added to pyproject.toml (Rule 3 fix). FastAPI's TestClient requires httpx; without it test_ping.py fails at import time with `RuntimeError: The starlette.testclient module requires the httpx package`. Plan text did not list httpx but the verify gate (`uv run pytest tests/`) cannot pass without it."
  - "Plan 06-02 / Task 4: tests/test_signature.py reads AUTH_TOKEN from os.environ at module load instead of hardcoding 'fixture-token' (Rule 1 fix). pytest collects test_ping.py first (alphabetical: test_ping, test_resample, test_signature, test_upstream); test_ping.py uses os.environ.setdefault to set TWILIO_AUTH_TOKEN='test-token'; src.config._VALIDATOR is initialised with that value at import time. test_signature.py's setdefault is then a no-op so its hardcoded 'fixture-token' did NOT match _VALIDATOR's auth token, causing test_valid_signature_passes to fail with PermissionError. Reading the env var at module load matches whatever the validator was actually built with — same fix shape as the demonstrated isolation-passes-but-suite-fails diagnosis."
  - "Plan 06-02 / Task 1: dev-dependencies block uses [tool.uv] dev-dependencies instead of the deprecated dependency-groups.dev format because the rest of the Hera repo (agent/pyproject.toml + infra/cdk/pyproject.toml) uses the legacy form. uv 0.10.8 still resolves it cleanly with a deprecation warning; switching to dependency-groups.dev would diverge from the project pattern and is a v3 migration."
  - "Plan 06-02 / Task 1 Dockerfile comment edited: original plan body had `# Do NOT add 'FROM --platform=linux/arm64 ...'` which contained the literal token `FROM --platform=` and tripped the acceptance criterion `grep -q 'FROM --platform=' Dockerfile` (returns nothing) — the criterion's intent is to ban the directive, not the documenting comment. Comment rephrased to 'Do NOT pin a per-arch platform on the FROM directive' preserving meaning."
metrics:
  duration: ~25min
  completed: 2026-05-07
  task_count: 4
  file_count_created: 13
  file_count_modified: 1
  test_pass_count: 10
  uv_packages_resolved: 52
---

# Phase 6 Plan 02: Twilio Bridge Container Source Summary

Phase 6 Wave 1 Plan 06-02 ships the Twilio Media Streams bridge container source under `infra/modules/twilio_bridge/{Dockerfile, pyproject.toml, uv.lock, .dockerignore, src/, tests/}`. The 9 source files + 4 offline test files give Plan 06-03 + 06-04 a fully de-risked image to push and deploy: signature validation, resample state-threading, and SigV4 header construction are all covered by 10 pre-execution offline tests on uv-managed Python 3.13. Live AWS state untouched; v1 system untouched per D-64.

## Files Created (13)

**Container project (5):**
- `infra/modules/twilio_bridge/Dockerfile` — multi-arch (linux/arm64,linux/amd64) on `ghcr.io/astral-sh/uv:0.10.8-python3.13-trixie-slim`; two-layer uv sync; non-root `appuser` UID 1000; `HEALTHCHECK` probes `/ping`; `CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]`. NO env-var bake-in (App Runner injects AGENTCORE_RUNTIME_ARN + TWILIO_AUTH_TOKEN + AWS_REGION at runtime per Plan 06-01).
- `infra/modules/twilio_bridge/pyproject.toml` — `requires-python = ">=3.13"` (D-59 — required for audioop-lts which replaces stdlib audioop removed in 3.13 per PEP 594); deps `fastapi>=0.115.6,<1`, `uvicorn[standard]`, `websockets>=15`, `audioop-lts==0.2.2`, `boto3`, `botocore`, `twilio>=9`; dev `pytest>=8`, `pytest-asyncio`, `ruff`, `httpx` (httpx is required by FastAPI TestClient — Rule 3 fix; not listed in plan but `uv run pytest` cannot pass without it).
- `infra/modules/twilio_bridge/uv.lock` — 52 packages resolved against uv-managed Python 3.13.12; `uv lock --check` exits 0; 1219 lines.
- `infra/modules/twilio_bridge/.dockerignore` — small allowlist excluding `.venv`, `__pycache__`, `*.pyc`, `.pytest_cache`, `.ruff_cache`, `.mypy_cache`, `tests`, `build`, `dist`, `*.egg-info`, `.DS_Store`.
- `infra/modules/twilio_bridge/src/__init__.py` — empty package marker.

**Bridge source (4):**
- `infra/modules/twilio_bridge/src/main.py` — FastAPI app exposing GET `/ping` + WebSocket `/twilio`. `validate_twilio_signature(websocket)` runs BEFORE `await websocket.accept()` (D-67 enforcement point — T-06-02-01 mitigation). Single bounded `try/except WebSocketDisconnect` for the documented protocol-close path (Pattern S9 / AGENTS.md).
- `infra/modules/twilio_bridge/src/bridge.py` — `handle_twilio_call` per-call coroutine. Drains Twilio `connected` event, captures CallSid + streamSid from `start`, opens SigV4-signed upstream WSS via `websockets.connect(WSS_URL_BASE, additional_headers=_signed_upstream_headers(call_sid))`. Two pumps via `asyncio.wait FIRST_COMPLETED`: inbound `pump_twilio_to_sonic` decodes mu-law base64 → `twilio_to_sonic(..., in_state)` → `upstream.send`; outbound `pump_sonic_to_twilio` reads `async for frame in upstream` → `sonic_to_twilio(frame, SONIC_OUTPUT_RATE_HZ, out_state)` → base64 → `twilio_ws.send_text(envelope)`. ratecv `in_state` / `out_state` owned per-pump (no shared lock — WARNING-3). Outbound text frames (transcript / tool events) dropped at DEBUG-level for operator log correlation (WARNING-4).
- `infra/modules/twilio_bridge/src/config.py` — `AWS_REGION` lazy-defaults to `ap-northeast-1` (D-14); `AGENTCORE_RUNTIME_ARN` + `TWILIO_AUTH_TOKEN` are REQUIRED env vars (`os.environ[...]`) — fail-fast surfaces operator misconfig as a container restart loop instead of allowing anonymous traffic. `validate_twilio_signature` uses `twilio.request_validator.RequestValidator.validate(url, {}, signature)` with trailing-slash retry (Pitfall 2); raises `PermissionError` on failure.
- `infra/modules/twilio_bridge/src/resample.py` — `twilio_to_sonic(mulaw_8k, state)` does `audioop.ulaw2lin → audioop.ratecv(8000→16000)`; `sonic_to_twilio(pcm16_in, in_rate, state)` does `audioop.ratecv(in_rate→8000) → audioop.lin2ulaw`. Both return `(bytes, new_state)`; caller threads `new_state` into next call. `audioop` import resolves on Python 3.13 via the audioop-lts shim.

**Offline tests (4):**
- `infra/modules/twilio_bridge/tests/test_ping.py` — 1 case: `TestClient(app).get("/ping")` returns 200 with `status=Healthy` and integer `time_of_last_update`.
- `infra/modules/twilio_bridge/tests/test_signature.py` — 3 cases: valid HMAC passes (no raise), tampered URL raises `PermissionError`, missing signature header raises `PermissionError`. AUTH_TOKEN read from `os.environ` at module load to align with whatever value `_VALIDATOR` was initialised with (Rule 1 fix — see Deviations).
- `infra/modules/twilio_bridge/tests/test_resample.py` — 3 cases: 160 mu-law bytes → 600-680 PCM16 bytes (8k→16k ratio with filter ramp tolerance), 640 PCM16 bytes → 140-180 mu-law bytes (16k→8k ratio), state threading mutates output bytes (Pitfall 4 evidence).
- `infra/modules/twilio_bridge/tests/test_upstream.py` — 3 cases: `_signed_upstream_headers("CA-x")` returns headers including `authorization`, `x-amz-date`, `x-amzn-bedrock-agentcore-runtime-session-id`; session-id value equals the `call_sid` argument exactly; Authorization Credential field includes the access-key + region + service strings (`AKIAIOSFODNN7EXAMPLE`, `ap-northeast-1`, `bedrock-agentcore`).

## Files Modified (1)

- `.gitignore` — added `infra/modules/twilio_bridge/{.venv,__pycache__,**/__pycache__,.pytest_cache,.ruff_cache}` mirroring the existing `infra/cdk/` block. Rule 3 fix to keep generated artifacts out of git.

## Verification Results

**`uv lock --check` (run from `infra/modules/twilio_bridge/`):** ✓ exit 0 — `Resolved 52 packages in 6ms`. Lockfile consistent with pyproject.toml on uv-managed Python 3.13.12.

**`uv run --python 3.13 pytest tests/` (run from `infra/modules/twilio_bridge/`):**
```
..........                                                               [100%]
10 passed in 0.55s
```
- test_ping.py: 1 passed
- test_signature.py: 3 passed (valid_signature, tampered_url, missing_signature)
- test_resample.py: 3 passed (twilio_to_sonic_doubles, sonic_to_twilio_halves, state_threading)
- test_upstream.py: 3 passed (signed_headers_present, session_id_value, authorization_credential_format)

**AST parse clean:** all 4 source files (`main.py`, `bridge.py`, `config.py`, `resample.py`) parse on Python 3.13 with no syntax errors.

**try/except audit:**
- `src/bridge.py` — 0 try/except blocks
- `src/config.py` — 0 try/except blocks
- `src/resample.py` — 0 try/except blocks
- `src/main.py` — 1 try/except block (the documented `WebSocketDisconnect` path; AGENTS.md mandate enforced)

**Signature gate ordering (T-06-02-01):** `grep -B2 'await websocket.accept' src/main.py | grep -q 'validate_twilio_signature'` returns 0 — validator runs BEFORE `accept()`.

**ratecv state threading (Pitfall 4):** `in_state` + `out_state` both present in `bridge.py`; per-pump nonlocal write (no shared lock).

**Docker buildx multi-arch local build:** ✓ succeeded against `linux/arm64,linux/amd64 --provenance=false --sbom=false --tag hera-twilio-bridge:dev-multiarch infra/modules/twilio_bridge`. Both per-arch layers built clean (~36s arm64 uv sync, ~13s useradd). The "WARNING: No output specified" is expected — multi-arch images can't be `--load`ed into the local Docker daemon; the manifest stays in the build cache. Plan 06-03's `bin/push-bridge-image.sh --push` repeats the same buildx invocation against ECR.

**v1 system unchanged (D-64):** `git diff 65ef025..HEAD --name-only` lists 0 files under `agent/`, `cdk/`, `frontend/`, `bin/cleanup-verify.sh`, or any of `infra/modules/{knowledge_base,kb_consumer_policy,agentcore_iam,ecr,widget_hosting,widget_presigner,observability}/`. The only files outside `infra/modules/twilio_bridge/` touched are `.gitignore` (additive only — no edits to existing rules) and the new SUMMARY.md being authored now.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Added `httpx` to dev-dependencies**
- **Found during:** Task 4 — first `uv run --python 3.13 pytest tests/` invocation.
- **Issue:** Plan's `pyproject.toml` listed dev deps as `pytest>=8`, `pytest-asyncio`, `ruff`. FastAPI's `TestClient` (used by `test_ping.py`) imports `starlette.testclient`, which requires `httpx`; without it `pytest` fails at collection time with `RuntimeError: The starlette.testclient module requires the httpx package`. Pytest verify gate cannot pass without httpx.
- **Fix:** Added `httpx` to `[tool.uv] dev-dependencies` in `infra/modules/twilio_bridge/pyproject.toml` and re-ran `uv lock` (52 packages now include httpx + transitive httpcore + h11 + anyio).
- **Files modified:** `infra/modules/twilio_bridge/pyproject.toml`, `infra/modules/twilio_bridge/uv.lock`.
- **Commit:** `082f7b5` (Task 1).

**2. [Rule 1 - Bug] tests/test_signature.py: read AUTH_TOKEN from os.environ at module load**
- **Found during:** Task 4 — first full-suite `pytest tests/` run; `test_valid_signature_passes` failed with `PermissionError: invalid X-Twilio-Signature` even though the same test passed in isolation (`pytest tests/test_signature.py`).
- **Root cause:** pytest collects tests in alphabetical filename order: `test_ping.py` → `test_resample.py` → `test_signature.py` → `test_upstream.py`. The first three modules each call `os.environ.setdefault("TWILIO_AUTH_TOKEN", "...")`. Python's `setdefault` is a no-op once the key exists, so whichever module imports first (`test_ping.py` with `"test-token"`) wins. `src.config._VALIDATOR = RequestValidator(TWILIO_AUTH_TOKEN)` is initialised at first import (also from `test_ping.py`) with `"test-token"`. `test_signature.py` then computed HMAC fixtures with the hardcoded `"fixture-token"` — mismatch, validator rejected.
- **Fix:** changed `AUTH_TOKEN = "fixture-token"` to `AUTH_TOKEN = os.environ["TWILIO_AUTH_TOKEN"]` in `tests/test_signature.py`. Now whatever value the validator was built with is also used to compute the test fixtures — guaranteed agreement regardless of test collection order. Diagnosis-as-evidence: same test in isolation `pytest tests/test_signature.py` passes (only fails in full-suite run); running fixture isolation script (env var exactly matching fixture token) → all paths green.
- **Files modified:** `infra/modules/twilio_bridge/tests/test_signature.py`.
- **Commit:** `b0b0ba2` (Task 4).

**3. [Rule 1 - Bug] Dockerfile comment line tripped the platform-pin acceptance criterion**
- **Found during:** Task 1 — first acceptance-criterion sweep after writing Dockerfile.
- **Issue:** Plan's Dockerfile body included a comment line `# Do NOT add \`FROM --platform=linux/arm64 ...\` — that breaks local AMD64 ...`. The acceptance criterion `grep -q 'FROM --platform=' infra/modules/twilio_bridge/Dockerfile` (returns nothing) was meant to forbid the Dockerfile *directive* `FROM --platform=...`, but the comment text contained the literal substring and tripped the grep.
- **Fix:** Rephrased the comment to `# Do NOT pin a per-arch platform on the FROM directive — that would break local AMD64 ...` preserving meaning. The Dockerfile directive itself was always correct (`FROM ghcr.io/astral-sh/uv:0.10.8-python3.13-trixie-slim AS base` — no `--platform` ARG).
- **Files modified:** `infra/modules/twilio_bridge/Dockerfile`.
- **Commit:** `082f7b5` (Task 1).

**4. [Rule 3 - Blocking issue] Added twilio_bridge to .gitignore**
- **Found during:** Task 4 — `git status --short` after running `pytest`.
- **Issue:** Running `uv sync` + `pytest` creates `infra/modules/twilio_bridge/.venv/`, `infra/modules/twilio_bridge/src/__pycache__/`, `infra/modules/twilio_bridge/.pytest_cache/`, etc. The repo's existing `.gitignore` explicitly listed `infra/cdk/` artifacts (`.venv/`, `__pycache__/`, etc.) but NOT the twilio_bridge equivalents. The `.venv` had its own auto-generated nested `.gitignore` (uv writes one) that ignored its contents, but the project gitignore didn't cover the parent paths or pycache.
- **Fix:** Added a parallel block to `.gitignore` mirroring the cdk pattern: `infra/modules/twilio_bridge/{.venv,__pycache__,**/__pycache__,.pytest_cache,.ruff_cache}`. Lockfile (`uv.lock`) IS committed — same contract as cdk and agent.
- **Files modified:** `.gitignore`.
- **Commit:** `b0b0ba2` (Task 4).

## Threat Model Dispositions Verified

| Threat | Disposition | Verification |
|---|---|---|
| T-06-02-01 (Spoofing — anonymous /twilio WS) | mitigate | `grep -B2 'await websocket.accept' src/main.py | grep -q 'validate_twilio_signature'` returns 0; test_signature.py covers valid/tampered/missing paths offline (10 passed). |
| T-06-02-02 (Tampering — replayed Twilio audio frames) | accept | Documented per memory `project_v2_twilio_scope` minimal demo scope; AgentCore concurrency cap=2 (D-30) bounds blast radius. No code change. |
| T-06-02-03 (Info disclosure — auth token in source/logs) | mitigate | `grep -r 'fixture-token\|test-token\|TWILIO_AUTH_TOKEN.*=.*\".*\"' src/ tests/` finds no string-literal tokens in src; tests use fixture tokens injected via `os.environ.setdefault`. No `print(os.environ)` or token in logger calls. |
| T-06-02-04 (Info disclosure — runtime ARN in source) | accept | ARN is operational metadata; comes from env var `AGENTCORE_RUNTIME_ARN` set by App Runner from Plan 06-01. No string literal in source. |
| T-06-02-05 (DoS — malformed JSON crashes container) | accept (loud-fail) | `bridge.py` has 0 try/except; `json.loads` exception bubbles to uvicorn → App Runner restart. AGENTS.md mandate honored. |
| T-06-02-06 (Tampering — image substitution) | mitigate | Plan 06-01 owns ECR `image_tag_mutability=IMMUTABLE` + `scan_on_push=true`. Plan 06-02 ships source only; tags applied by Plan 06-03 push script. |
| T-06-02-07 (Info disclosure — caller phone number in logs) | accept (low-risk) | `bridge.py` logs only `callSid` + `streamSid` + `mediaFormat`; phone number does not appear in Twilio Media Streams envelopes. |
| T-06-02-08 (Repudiation — bridge calls AgentCore) | accept | CloudTrail captures every `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream` with the bridge instance role identity (Plan 06-01 names it `hera-twilio-bridge-instance-prod`). CallSid header carried as session id. |

## Live AWS State

**UNCHANGED.** This plan ships container source code only — no `terraform apply`, no `aws *` CLI invocations, no live infrastructure. The existing AgentCore Runtime (`hera_agent-GIsf2P4ImD`), KB (`BKXE19AH89`), CloudFront widget URL (`https://dg0w939ktclw6.cloudfront.net`), CloudWatch dashboard (`hera-prod`), 2 op alarms, and 1 billing alarm in us-east-1 are all unmodified. No new AWS resources created. No IAM. No ECR push (Plan 06-03 owns push). Demo budget honored (memory `project_demo_budget`).

## Open Caveat for Plan 06-04

`SONIC_OUTPUT_RATE_HZ` defaults to `16000` Hz in `src/bridge.py` (line ~62). Phase 2 RUNBOOK records Pipecat default OUT as 24 kHz Int16 (AGT-07), but it is not yet probed at the AgentCore data-plane WSS level (D-59 open caveat). Plan 06-04's operator dial-in checkpoint (with stopwatch protocol per WARNING-2) probes the live `bedrock-agentcore /ws` framing rate by:
1. Logging the byte length of the first inbound `bytes` frame from `upstream` (via `aws logs tail` after the operator dials).
2. If the frame is ~1920 bytes (≈ 40ms × 24kHz × 2 bytes), flip `SONIC_OUTPUT_RATE_HZ = 24000` and re-deploy.
3. If the frame is ~1280 bytes (≈ 40ms × 16kHz × 2 bytes), keep the default.

`SONIC_OUTPUT_RATE_HZ` is a single integer constant — adjusting it is a one-line edit + re-push, no architectural impact. BLOCKER-5 fix (this plan's offline tests) ensures the resampler functions correctly at both rates: `test_sonic_to_twilio_halves_at_16k_input` covers 16k → 8k; the dial-in smoke covers the 24k → 8k path live.

## Hand-off

**Plan 06-03 (Wave 2, autonomous=true)** consumes:
- `terraform output -raw twilio_bridge_ecr_repository_url` (from Plan 06-01 sibling).
- This plan's `infra/modules/twilio_bridge/{Dockerfile, src/, pyproject.toml, uv.lock}` for `bin/push-bridge-image.sh`.

Plan 06-03 ships:
- `bin/push-bridge-image.sh` — mirrors `bin/push-image.sh` (`--provenance=false --sbom=false`); git-SHA tag.
- `bin/cleanup-verify-twilio.sh` — mirrors `bin/cleanup-verify.sh` (verify-only; AWS + Twilio API checks).
- `RUNBOOK.md` Phase 6 paste-blocks — Twilio account setup, Secrets Manager auth-token paste, number purchase, TwiML Bin creation, voice-webhook wiring, App Runner deploy lifecycle, smoke test, cleanup quy trinh.

**Plan 06-04 (Wave 3, autonomous=false with 2 operator checkpoints)** consumes Plans 06-01 + 06-02 + 06-03 outputs to execute the live two-pass `terraform apply` + dial-in smoke + REQ flips.

## Self-Check: PASSED

**File existence (13 created + 1 modified):**
- ✓ `infra/modules/twilio_bridge/Dockerfile` — present
- ✓ `infra/modules/twilio_bridge/pyproject.toml` — present
- ✓ `infra/modules/twilio_bridge/uv.lock` — present (1219 lines, 52 packages)
- ✓ `infra/modules/twilio_bridge/.dockerignore` — present
- ✓ `infra/modules/twilio_bridge/src/__init__.py` — present
- ✓ `infra/modules/twilio_bridge/src/main.py` — present
- ✓ `infra/modules/twilio_bridge/src/bridge.py` — present
- ✓ `infra/modules/twilio_bridge/src/config.py` — present
- ✓ `infra/modules/twilio_bridge/src/resample.py` — present
- ✓ `infra/modules/twilio_bridge/tests/test_ping.py` — present
- ✓ `infra/modules/twilio_bridge/tests/test_signature.py` — present
- ✓ `infra/modules/twilio_bridge/tests/test_resample.py` — present
- ✓ `infra/modules/twilio_bridge/tests/test_upstream.py` — present
- ✓ `.gitignore` — modified

**Commit existence:**
- ✓ `082f7b5` — `feat(06-02): scaffold twilio_bridge container — Dockerfile + uv project + .dockerignore`
- ✓ `d425cd8` — `feat(06-02): add bridge config + resample modules — twilio signature validator + mu-law/Int16 ratecv`
- ✓ `68fa695` — `feat(06-02): add bridge FastAPI entrypoint + per-call SigV4-signed upstream WSS pump`
- ✓ `b0b0ba2` — `test(06-02): add offline test suite — /ping + signature + resample + SigV4 header construction`

All 4 atomic commits present in `git log --oneline -5`.

---

*Plan 06-02 complete. 4 tasks, 4 atomic commits, 13 source files + 1 modified, 10 offline tests passing, 0 live AWS work. Ready for Wave 2 (Plan 06-03).*
