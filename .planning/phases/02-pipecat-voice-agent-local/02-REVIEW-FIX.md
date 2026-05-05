---
phase: 02-pipecat-voice-agent-local
fixed_at: 2026-05-05T00:00:00Z
review_path: .planning/phases/02-pipecat-voice-agent-local/02-REVIEW.md
iteration: 2
findings_in_scope: 11
fixed: 11
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-05-05
**Source review:** `.planning/phases/02-pipecat-voice-agent-local/02-REVIEW.md`
**Iteration:** 2

**Summary:**
- Findings in scope: 11 (Critical + Warning + Info)
- Fixed: 11 (6 in iteration 1 + 1 co-fix in iteration 1 + 4 in iteration 2)
- Skipped: 0

Iteration 1 (`/gsd:code-review 2 --fix`, 2026-05-05) closed all 6 Warnings
plus IN-04 as a co-fix. Iteration 2 (`/gsd:code-review 2 --fix --all`,
2026-05-05) closed the 4 remaining Info findings (IN-01, IN-02, IN-03,
IN-05). All 11 findings from the review are now resolved.

## Fixed Issues

### WR-01: smoke-voice.sh diagnostic block is dead code under `set -e`

**Files modified:** `bin/smoke-voice.sh`
**Commit:** `85171ff` (iteration 1)
**Applied fix:** Replaced two-line `uv run ...; PROBE_RC=$?` with same-line capture `PROBE_RC=0; uv run ... || PROBE_RC=$?`. Under `set -euo pipefail` the original form was unreachable on probe failure; the `|| PROBE_RC=$?` form evaluates the failed command in a context where `set -e` is suppressed, so the `FAIL: AGT-04 latency probe exit ${PROBE_RC}` diagnostic now actually prints. Gate exit-code behaviour unchanged (still non-zero on probe failure).

### WR-02: Browser captures audio before WebSocket is OPEN

**Files modified:** `frontend/app.js`
**Commit:** `3ec0b18` (iteration 1)
**Applied fix:** Replaced `await new Promise((r) => setTimeout(r, 200))` race with an explicit `waitForOpen(ws)` helper that resolves on the WS `open` event and rejects on `error` or `close`. The Record click now blocks on the handshake before `startCapture()` runs. Also added drop-counter logging in the worklet `onmessage` send path (`console.warn` on first dropped frame and every 25th thereafter) so a regression here is visible — per AGENTS.md "fail loudly, no silent drops". Listeners are removed in a shared cleanup function to avoid leaks if the connection closes mid-await.

### WR-03: AudioWorklet downsamples 48 kHz to 16 kHz with no anti-aliasing filter

**Files modified:** `frontend/audio-capture-worklet.js`
**Commit:** `72f6236` (iteration 1)
**Applied fix:** Added a one-pole IIR low-pass filter ahead of the decimator. Cutoff ~7 kHz (just under the 8 kHz Nyquist of the 16 kHz target rate) attenuates the 8-24 kHz band before decimation so it cannot fold back into the voice band. Filter state (`_lpfState`, `_lpfCoeff`) is constructed once and carried across `process()` calls so the filter is continuous across quanta. Also switched the `Float32 -> Int16` cast from `Math.floor` to `Math.round` — the trivial co-fix for IN-04 (symmetric quantiser, no asymmetric bias on negative samples). The per-quantum running-cursor improvement (IN-03) was deferred to iteration 2.

### WR-04: docker-compose.yml uses `nginx:alpine` floating tag

**Files modified:** `docker-compose.yml`
**Commit:** `1359f23` (iteration 1)
**Applied fix:** Pinned `image: nginx:alpine` to `image: nginx:1.27-alpine` to match the locked-stack reproducibility discipline (pinned Pipecat ==1.1.0, pinned Terraform ~> 6.27). Added a one-line comment explaining why the tag is pinned and instructing future maintainers to bump deliberately. `docker compose config --quiet` (with placeholder env vars to bypass the unrelated `${VAR:?msg}` interpolation) confirms the YAML structure is valid.

### WR-05: Dockerfile base image `ghcr.io/astral-sh/uv:python3.12-trixie-slim` is unpinned

**Files modified:** `agent/Dockerfile`
**Commit:** `6a32f56` (iteration 1)
**Applied fix:** Pinned to `ghcr.io/astral-sh/uv:0.10.8-python3.12-trixie-slim`. Selected uv 0.10.8 specifically because that is the version `uv --version` reports on the local machine that ran the AGT-04 latency gate during Phase 2 verification — pinning to the verified version, not the latest (0.11.9), is what the reproducibility goal requires. Tag existence confirmed against `ghcr.io/v2/astral-sh/uv/manifests/0.10.8-python3.12-trixie-slim` (HTTP 200 with proper Accept headers).

### WR-06: `test_prompt_has_no_filler_words_in_examples` does not test what its name claims

**Files modified:** `agent/tests/test_prompts.py`
**Commit:** `534c7f2` (iteration 1)
**Applied fix:** Renamed the test to `test_filler_words_absent_from_example_responses` and replaced the inverted `assert "absolutely" in SYSTEM_PROMPT.lower()` body with a real enforcement: parse out every `You:` example line from `SYSTEM_PROMPT`, then assert no banned filler (`absolutely`, `great question`, `let me think`) appears in any of them. Added an `assert you_lines` precondition so the test fails loudly if a future refactor accidentally drops the example block. `uv run pytest tests/test_prompts.py -v` reports 5/5 pass; `uv run pytest` against the full agent suite reports 11/11 pass.

### IN-01 / IN-02: `/ping` reports request time as `time_of_last_update`, and naive datetime

**Files modified:** `agent/hera_agent/main.py`
**Commit:** `5e8750f` (iteration 2)
**Applied fix:** Captured a module-level `_BOOT_TIME = int(datetime.now(tz=timezone.utc).timestamp())` once at import, and changed `/ping` to return that fixed value as `time_of_last_update`. The field name promises "when did agent state last change" — for this stateless agent that is process boot — and the integer now matches operator-side UTC log timestamps regardless of host locale. Combined IN-01 (semantic field meaning) and IN-02 (naive `datetime.now()` -> tz-aware UTC) into one commit because the IN-01 patch suggested in REVIEW.md naturally subsumes IN-02 by importing `timezone` and using `tz=timezone.utc`. AgentCore Runtime ignores the field (HTTP 200 + `status=Healthy` is the liveness signal), so this is a contract-naming and future-debugging correctness fix, not a behavioural change. `uv run pytest agent/tests/` reports 11/11 pass after the change.

### IN-03: AudioWorklet drops a few samples per quantum at non-integer ratios

**Files modified:** `frontend/audio-capture-worklet.js`
**Commit:** `109c686` (iteration 2)
**Applied fix:** Replaced the per-quantum index loop (`for i in 0..outLen: filtered[floor(i * ratio)]`) with a running float cursor `this._cursor` that advances by `ratio` per output sample and carries the fractional remainder into the next `process()` invocation via `this._cursor -= channel.length`. At native rate 48 kHz the ratio is exactly 3 and the old code was already correct; at 44.1 kHz (ratio ~= 2.756) the old code restarted at 0 each quantum and dropped the leftover fraction, producing slow drift / jitter. This fix is now warranted because the WR-03 anti-alias LPF is in place — without the LPF the cursor improvement would have been masked by aliasing noise (REVIEW.md flagged the dependency explicitly). `node --check` passes.

### IN-04: Float -> Int16 conversion uses `Math.floor`, asymmetric for negative samples

**Files modified:** `frontend/audio-capture-worklet.js`
**Commit:** `72f6236` (iteration 1, co-fix in WR-03)
**Applied fix:** Already fixed as a co-fix during the WR-03 LPF rewrite. The `Math.floor(s * 32767)` cast was changed to `Math.max(-32768, Math.min(32767, Math.round(s * 32767)))` — `Math.round` is the conventional symmetric quantiser, so negative samples are no longer biased one step lower than their positive mirror. Verified present in HEAD as part of iteration 2; no second commit needed.

### IN-05: `playbackCtx` and `nextStart` leak across reconnects

**Files modified:** `frontend/app.js`
**Commit:** `c726797` (iteration 2)
**Applied fix:** Added a teardown block to `ws.onclose` after `stopCapture()`: synchronously snapshot the context into a local, set `playbackCtx = null` and `nextStart = 0`, then call `ctx.close().catch(...)` to release audio resources. The synchronous reset prevents any racing `onmessage` (theoretical — WebSocket spec says no more `onmessage` after `onclose`) from scheduling a buffer on the closing context, and `nextStart = 0` ensures the next `connect()` (which has a `if (!playbackCtx)` guard) starts the playback queue from a clean state. The async close errors are logged via `console.warn` rather than propagated — the user-visible status is already "disconnected". `node --check` passes.

---

_Fixed: 2026-05-05_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
