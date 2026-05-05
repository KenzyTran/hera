---
phase: 02-pipecat-voice-agent-local
reviewed: 2026-05-05T00:00:00Z
depth: standard
files_reviewed: 34
files_reviewed_list:
  - agent/pyproject.toml
  - agent/uv.lock
  - agent/.env.example
  - agent/.gitignore
  - agent/.dockerignore
  - agent/Dockerfile
  - agent/hera_agent/__init__.py
  - agent/hera_agent/config.py
  - agent/hera_agent/prompts.py
  - agent/hera_agent/tools.py
  - agent/hera_agent/pipeline.py
  - agent/hera_agent/main.py
  - agent/hera_agent/serializer.py
  - agent/tests/__init__.py
  - agent/tests/conftest.py
  - agent/tests/test_config.py
  - agent/tests/test_lookup_product.py
  - agent/tests/test_prompts.py
  - bin/run-agent-local.sh
  - bin/run-agent-docker.sh
  - bin/smoke-voice.sh
  - bin/_smoke_voice_probe.py
  - docker-compose.yml
  - frontend/index.html
  - frontend/app.js
  - frontend/audio-capture-worklet.js
  - infra/modules/kb_consumer_policy/versions.tf
  - infra/modules/kb_consumer_policy/variables.tf
  - infra/modules/kb_consumer_policy/main.tf
  - infra/modules/kb_consumer_policy/outputs.tf
  - infra/envs/prod/main.tf
  - infra/envs/prod/outputs.tf
  - RUNBOOK.md
findings:
  blocker: 0
  warning: 6
  info: 5
  total: 11
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-05-05
**Depth:** standard
**Files Reviewed:** 34
**Status:** issues_found

## Summary

The Phase 2 implementation cleanly delivers a Pipecat 1.1.0 voice agent on Python 3.12, a multi-arch-friendly Dockerfile, a vanilla browser frontend, an AGT-04 latency probe, and a zero-wildcard IAM consumer policy. The locked stack decisions (StaticCredentialsResolver, RawPCMSerializer wiring, asyncio.to_thread for boto3, cancel_on_interruption=False for the lookup tool, fixed-name unattached managed policy) are all implemented correctly and are well-commented.

No BLOCKER-level defects were found: there are no IAM wildcards, no committed secrets, the container runs as a non-root user, the AWSNovaSonicLLMService is wired with explicit static credentials, and the boto3 client is offloaded via `asyncio.to_thread`. Tests pass on the live AGT-04 gate path documented in RUNBOOK.

The findings below are all reproducibility, correctness-on-edge-paths, or test-quality issues. The most important is WR-01: a `set -e` interaction in `bin/smoke-voice.sh` that makes a diagnostic message permanently unreachable. The frontend has two independent issues around capture timing and ASR audio quality (WR-02, WR-03) that are tolerable for local dev today but should be addressed before any non-localhost demo.

## Warnings

### WR-01: smoke-voice.sh diagnostic block is dead code under `set -e`

**File:** `bin/smoke-voice.sh:72-79`
**Issue:** With `set -euo pipefail` active (line 15), if `uv run python ${REPO_ROOT}/bin/_smoke_voice_probe.py` exits non-zero, bash aborts the script on that line before reaching `PROBE_RC=$?`. Lines 73-79 (capturing `$?`, the `cd "${REPO_ROOT}"` restore, the `if [[ ${PROBE_RC} -ne 0 ]]; then ... exit 1` block) are unreachable on probe failure. The script still exits non-zero (so the CI gate works), but the explicit "FAIL: AGT-04 latency probe exit ${PROBE_RC}" diagnostic that the code clearly intends to print is permanently silent. The probe's own stderr is the only failure signal an operator sees.

**Fix:** Either disable errexit around the probe, or capture the exit code in the same statement as the call so `set -e` does not trip:
```bash
# Option A - same-line capture (idiomatic with set -e)
PROBE_RC=0
uv run python "${REPO_ROOT}/bin/_smoke_voice_probe.py" || PROBE_RC=$?
cd "${REPO_ROOT}"

# Option B - explicit toggle
set +e
uv run python "${REPO_ROOT}/bin/_smoke_voice_probe.py"
PROBE_RC=$?
set -e
cd "${REPO_ROOT}"
```

### WR-02: Browser captures audio before WebSocket is OPEN, dropping the user's first words

**File:** `frontend/app.js:150-169` (capture lifecycle), `frontend/app.js:111-115` (silent send-drop)
**Issue:** The Record-button handler does `await connect(); await new Promise((r) => setTimeout(r, 200)); await startCapture()`. `connect()` constructs the WebSocket but does not await `onopen` — it returns immediately. The 200ms `setTimeout` is a guess, not a synchronisation primitive. If the WS handshake takes longer than 200ms (any non-localhost network, heavy laptop load, cold start), `startCapture()` runs while `ws.readyState !== OPEN`, the worklet starts emitting frames, and `onmessage`-side line 112 silently drops every frame: `if (ws && ws.readyState === WebSocket.OPEN) { ws.send(...) }`. The user's opening syllables vanish with no log, no UI signal. AGENTS.md mandates failing fast, not silently dropping data.

**Fix:** Replace the sleep with an explicit `onopen` await, and either buffer or warn on dropped pre-OPEN frames:
```js
function waitForOpen(ws) {
  return new Promise((resolve, reject) => {
    if (ws.readyState === WebSocket.OPEN) return resolve();
    ws.addEventListener("open", () => resolve(), { once: true });
    ws.addEventListener("error", reject, { once: true });
  });
}

// in the click handler:
if (!ws || ws.readyState !== WebSocket.OPEN) {
  await connect();
  await waitForOpen(ws);
}
await startCapture();
```
Optionally also count and log dropped frames in the `onmessage` send path so a regression here is visible.

### WR-03: AudioWorklet downsamples 48 kHz to 16 kHz with no anti-aliasing filter

**File:** `frontend/audio-capture-worklet.js:15-28`
**Issue:** The worklet picks every Nth sample (`channel[Math.floor(i * ratio)]`) with no low-pass filter ahead of decimation. At a typical 48 kHz native rate, all energy from 8 kHz to 24 kHz folds back into 0-8 kHz as aliasing. For voice this manifests as extra noise on sibilants and any keyboard / fan noise the mic picks up, degrading Sonic ASR — exactly the failure mode Pitfall D was meant to prevent. The AGT-04 latency probe uses synthetic silence so it cannot detect this; the live AGT-04 reading of LATENCY_MS=0 is not evidence the audio path is clean.

**Fix:** Add a one-pole IIR low-pass before the decimator (cheap, no extra deps), or use OfflineAudioContext / `BiquadFilterNode` upstream of the worklet. Minimal in-worklet patch:
```js
process(inputs) {
  const input = inputs[0];
  if (!input || input.length === 0) return true;
  const channel = input[0];
  const ratio = sampleRate / this.targetRate;
  // One-pole LPF at ~7 kHz (just under Nyquist for 16 kHz).
  // y[n] = a*y[n-1] + (1-a)*x[n] with a tuned for sampleRate.
  const a = Math.exp(-2 * Math.PI * 7000 / sampleRate);
  let y = this._lpfState ?? 0;
  const filtered = new Float32Array(channel.length);
  for (let i = 0; i < channel.length; i++) {
    y = a * y + (1 - a) * channel[i];
    filtered[i] = y;
  }
  this._lpfState = y;
  const outLen = Math.floor(channel.length / ratio);
  const out = new Int16Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const s = filtered[Math.floor(i * ratio)];
    out[i] = Math.max(-32768, Math.min(32767, Math.round(s * 32767)));
  }
  this.port.postMessage(out.buffer, [out.buffer]);
  return true;
}
```
(Also note `Math.floor` on a possibly-negative product is asymmetric; `Math.round` is the conventional symmetric quantiser — see IN-04.)

### WR-04: docker-compose.yml uses `nginx:alpine` floating tag — non-reproducible builds

**File:** `docker-compose.yml:37`
**Issue:** `image: nginx:alpine` resolves to whatever Alpine-based nginx is current at pull time. A workshop attendee running `bin/run-agent-docker.sh` next month may get a different nginx than the one verified during Phase 2. This contradicts the stated reproducibility goal of "Phase 3 deploys without a transport refactor" and the locked-stack discipline documented in CLAUDE.md.

**Fix:** Pin to a specific tag (and ideally a digest) the same way you pin Pipecat to `==1.1.0` in `pyproject.toml`:
```yaml
frontend:
  image: nginx:1.27-alpine
```

### WR-05: Dockerfile base image `ghcr.io/astral-sh/uv:python3.12-trixie-slim` is unpinned

**File:** `agent/Dockerfile:11`
**Issue:** Same class of issue as WR-04. The `uv:python3.12-trixie-slim` tag is mutable; uv ships frequently. Phase 3's AgentCore image build will diverge from Phase 2's locally-verified image whenever uv publishes a new release. AGT-04 was demonstrated against one snapshot of this tag; it is not a contract.

**Fix:** Pin to a uv release version (or a digest) the same way the Python and Terraform versions are pinned:
```dockerfile
FROM ghcr.io/astral-sh/uv:0.10.5-python3.12-trixie-slim AS base
# or, even stronger:
FROM ghcr.io/astral-sh/uv@sha256:<digest> AS base
```

### WR-06: `test_prompt_has_no_filler_words_in_examples` does not test what its name claims

**File:** `agent/tests/test_prompts.py:24-33`
**Issue:** The test name promises "no filler words in examples". The body asserts `"absolutely" in SYSTEM_PROMPT.lower()` and `"great question" in SYSTEM_PROMPT.lower()` — i.e. it asserts the words **are present** (which they are, in the rule-text line that bans them). The test would pass trivially even if the example responses themselves used those filler words. The docstring acknowledges the inversion but the assertion does not actually enforce the D-17 rule on the examples block.

**Fix:** Either rename the test to reflect what it tests, or actually enforce the rule by parsing out the example "You:" lines and asserting filler is absent there:
```python
def test_filler_words_absent_from_example_responses():
    """D-17: 'You:' example replies must not contain banned filler."""
    banned = ("absolutely", "great question", "let me think")
    for line in SYSTEM_PROMPT.splitlines():
        stripped = line.strip().lower()
        if stripped.startswith("you:"):
            for word in banned:
                assert word not in stripped, f"banned filler {word!r} in example: {line!r}"
```

## Info

### IN-01: `/ping` reports request time as `time_of_last_update`

**File:** `agent/hera_agent/main.py:24-27`
**Issue:** The field name `time_of_last_update` semantically means "when did agent state last change", but the code emits `int(datetime.now().timestamp())` — i.e. the time of the current request. The AgentCore Runtime contract uses HTTP 200 + status=Healthy as the liveness signal, and ignores the timestamp field, so this is not a functional bug. It is a small naming/contract mismatch worth correcting before Phase 3.

**Fix:** Either rename to `time_of_response` or capture an actual last-update timestamp at startup:
```python
_BOOT_TIME = int(datetime.now(tz=timezone.utc).timestamp())

@app.get("/ping")
async def ping() -> dict:
    return {"status": "Healthy", "time_of_last_update": _BOOT_TIME}
```

### IN-02: `int(datetime.now().timestamp())` is naive; should be UTC-aware

**File:** `agent/hera_agent/main.py:11,26`
**Issue:** `datetime.now()` returns local time; `.timestamp()` then converts using the system local zone. On a host configured to a non-UTC zone, the wall-clock-derived integer can be off by hours from what an operator reading container logs in UTC expects. AgentCore Runtime ignores the field, so this is not an outage risk, just a future-debugging papercut.

**Fix:** Use `datetime.now(tz=timezone.utc)` (and add `from datetime import timezone`).

### IN-03: AudioWorklet drops a few samples per quantum at non-integer ratios

**File:** `frontend/audio-capture-worklet.js:19-26`
**Issue:** With native rate 48 kHz, ratio = 3, `floor(128 / 3) = 42`, consuming `42 * 3 = 126` of 128 samples per quantum (~1.5% loss, no drift). At 44.1 kHz, ratio ≈ 2.756, `floor(128 / 2.756) = 46`, consuming `46 * 2.756 ≈ 126.8` samples — and the floor of `i * ratio` for i in 0..45 is computed against a pure index, not a running counter, so any leftover fractional position from the previous quantum is discarded. Net effect: a slow drift/jitter on non-48 kHz hardware. Modern Chromium-on-laptop is overwhelmingly 48 kHz, so this is rarely visible in practice.

**Fix:** Maintain a running float read-cursor across `process()` calls instead of restarting at 0 each quantum:
```js
this._cursor = this._cursor ?? 0;
const out = [];
while (this._cursor < channel.length) {
  // sample with whichever interpolation you want
  const idx = Math.floor(this._cursor);
  out.push(/* clamp + Int16 from filtered[idx] */);
  this._cursor += ratio;
}
this._cursor -= channel.length; // carry remainder into next quantum
```
Only worth doing if the LPF in WR-03 is also added.

### IN-04: Float→Int16 conversion uses `Math.floor`, asymmetric for negative samples

**File:** `frontend/audio-capture-worklet.js:24`
**Issue:** `Math.floor(s * 32767)` rounds toward -infinity, which biases negative samples one step lower than their positive mirror. The clamp `Math.max(-32768, ...)` then catches the corner case. `Math.round` (or `Math.trunc`) is the conventional symmetric quantiser. The audible difference is below noise floor at 16 kHz; flagged for completeness.

**Fix:** `out[i] = Math.max(-32768, Math.min(32767, Math.round(s * 32767)));`

### IN-05: `playbackCtx` and `nextStart` leak across reconnects

**File:** `frontend/app.js:24,43-45,82`
**Issue:** `playbackCtx` is created once and never closed; `nextStart` is module-level and not reset on reconnect. The `Math.max(playbackCtx.currentTime, nextStart)` clamp prevents user-visible glitches because `currentTime` always advances, but the AudioContext stays alive across reconnects and accumulates resources. `stopCapture()` correctly tears down the capture context but leaves the playback context running. Not a bug in the local-dev session model; a tidy-up worth doing before Phase 3 if the page is ever long-lived.

**Fix:** On `ws.onclose` (or a dedicated cleanup), `playbackCtx.close().then(() => { playbackCtx = null; nextStart = 0; })`.

---

_Reviewed: 2026-05-05_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
