---
phase: 02-pipecat-voice-agent-local
fixed_at: 2026-05-05T00:00:00Z
review_path: .planning/phases/02-pipecat-voice-agent-local/02-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-05-05
**Source review:** `.planning/phases/02-pipecat-voice-agent-local/02-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 6 (Critical + Warning)
- Fixed: 6
- Skipped: 0
- Out-of-scope (Info, untouched): IN-01, IN-02, IN-03, IN-05
- Trivial co-fix included: IN-04 (Math.floor -> Math.round, applied as part of WR-03)

## Fixed Issues

### WR-01: smoke-voice.sh diagnostic block is dead code under `set -e`

**Files modified:** `bin/smoke-voice.sh`
**Commit:** `85171ff`
**Applied fix:** Replaced two-line `uv run ...; PROBE_RC=$?` with same-line capture `PROBE_RC=0; uv run ... || PROBE_RC=$?`. Under `set -euo pipefail` the original form was unreachable on probe failure; the `|| PROBE_RC=$?` form evaluates the failed command in a context where `set -e` is suppressed, so the `FAIL: AGT-04 latency probe exit ${PROBE_RC}` diagnostic now actually prints. Gate exit-code behaviour unchanged (still non-zero on probe failure).

### WR-02: Browser captures audio before WebSocket is OPEN

**Files modified:** `frontend/app.js`
**Commit:** `3ec0b18`
**Applied fix:** Replaced `await new Promise((r) => setTimeout(r, 200))` race with an explicit `waitForOpen(ws)` helper that resolves on the WS `open` event and rejects on `error` or `close`. The Record click now blocks on the handshake before `startCapture()` runs. Also added drop-counter logging in the worklet `onmessage` send path (`console.warn` on first dropped frame and every 25th thereafter) so a regression here is visible — per AGENTS.md "fail loudly, no silent drops". Listeners are removed in a shared cleanup function to avoid leaks if the connection closes mid-await.

### WR-03: AudioWorklet downsamples 48 kHz to 16 kHz with no anti-aliasing filter

**Files modified:** `frontend/audio-capture-worklet.js`
**Commit:** `72f6236`
**Applied fix:** Added a one-pole IIR low-pass filter ahead of the decimator. Cutoff ~7 kHz (just under the 8 kHz Nyquist of the 16 kHz target rate) attenuates the 8-24 kHz band before decimation so it cannot fold back into the voice band. Filter state (`_lpfState`, `_lpfCoeff`) is constructed once and carried across `process()` calls so the filter is continuous across quanta. Also switched the `Float32 -> Int16` cast from `Math.floor` to `Math.round` — the trivial co-fix for IN-04 (symmetric quantiser, no asymmetric bias on negative samples). The per-quantum running-cursor improvement (IN-03) was deferred — out of scope for the Critical+Warning pass.

### WR-04: docker-compose.yml uses `nginx:alpine` floating tag

**Files modified:** `docker-compose.yml`
**Commit:** `1359f23`
**Applied fix:** Pinned `image: nginx:alpine` to `image: nginx:1.27-alpine` to match the locked-stack reproducibility discipline (pinned Pipecat ==1.1.0, pinned Terraform ~> 6.27). Added a one-line comment explaining why the tag is pinned and instructing future maintainers to bump deliberately. `docker compose config --quiet` (with placeholder env vars to bypass the unrelated `${VAR:?msg}` interpolation) confirms the YAML structure is valid.

### WR-05: Dockerfile base image `ghcr.io/astral-sh/uv:python3.12-trixie-slim` is unpinned

**Files modified:** `agent/Dockerfile`
**Commit:** `6a32f56`
**Applied fix:** Pinned to `ghcr.io/astral-sh/uv:0.10.8-python3.12-trixie-slim`. Selected uv 0.10.8 specifically because that is the version `uv --version` reports on the local machine that ran the AGT-04 latency gate during Phase 2 verification — pinning to the verified version, not the latest (0.11.9), is what the reproducibility goal requires. Tag existence confirmed against `ghcr.io/v2/astral-sh/uv/manifests/0.10.8-python3.12-trixie-slim` (HTTP 200 with proper Accept headers).

### WR-06: `test_prompt_has_no_filler_words_in_examples` does not test what its name claims

**Files modified:** `agent/tests/test_prompts.py`
**Commit:** `534c7f2`
**Applied fix:** Renamed the test to `test_filler_words_absent_from_example_responses` and replaced the inverted `assert "absolutely" in SYSTEM_PROMPT.lower()` body with a real enforcement: parse out every `You:` example line from `SYSTEM_PROMPT`, then assert no banned filler (`absolutely`, `great question`, `let me think`) appears in any of them. Added an `assert you_lines` precondition so the test fails loudly if a future refactor accidentally drops the example block. `uv run pytest tests/test_prompts.py -v` reports 5/5 pass; `uv run pytest` against the full agent suite reports 11/11 pass.

---

_Fixed: 2026-05-05_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
