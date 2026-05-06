// Hera Phase 3 - polished web widget client.
// Capture/playback paths unchanged from Phase 2 (AudioWorklet 16 kHz Int16 LE
// in / 24 kHz Int16 LE out / sequential AudioBuffer playback queue). What's
// new in Phase 3 is the 5-state record-button machine, the 5 WID-06 error
// branches wired to D-28 trigger events, and the AGENTCORE_WSS_URL build-time
// placeholder per D-27.

// Build-time replacement target (Plan 03-04 Rule-4 deviation): the browser
// cannot SigV4-sign a WSS upgrade directly, so the widget fetches a
// short-lived presigned URL from a Lambda Function URL before opening the
// WebSocket. PRESIGN_URL is the Function URL; bin/build-widget.sh
// sed-replaces __PRESIGN_URL__ in the dist/ build copy. The source file
// commits with the local-dev sentinel so `docker compose up` keeps working
// unchanged via the typeof guard (CONTEXT.md D-27 Local dev unchanged).
//
// Local dev: PRESIGN_URL is undefined -> WS_LOCAL_DEV_URL is used directly
// against the local Pipecat agent at ws://localhost:8080/ws.
// Production: PRESIGN_URL points at the Function URL; connect() fetches
// {url} from it then opens that wss://.
const PRESIGN_URL = (typeof __PRESIGN_URL__ !== "undefined")
  ? "__PRESIGN_URL__"
  : null;
const WS_LOCAL_DEV_URL = "ws://localhost:8080/ws";

// 30s heartbeat per D-28 agent-timeout trigger event.
const HEARTBEAT_MS = 30000;

// DOM
const statusEl     = document.getElementById("status");
const recordBtn    = document.getElementById("recordBtn");
const transcriptEl = document.getElementById("transcript");
const micMutedEl   = document.getElementById("micMuted");

// Connection state
let ws            = null;
let captureCtx    = null;
let captureNode   = null;
let captureSource = null;
let mediaStream   = null;
let playbackCtx   = null;
let nextStart     = 0;
let recording     = false;
let agentTimeoutTimer = null;
let inboundBinarySeen = false;
let placeholderEmitted = false; // strip the empty-state placeholder on first append

// State machine: idle | connecting | listening | speaking | error
const STATES = ["idle", "connecting", "listening", "speaking", "error"];
const BTN_LABELS = {
  idle:       "Record",
  connecting: "Connecting...",
  listening:  "Recording (click to stop)",
  speaking:   "Agent speaking",
  error:      "Retry",
};
const PILL_LABELS = {
  disconnected: "disconnected",
  connecting:   "connecting",
  connected:    "connected",
  recording:    "recording",
  error:        "error",
};
const PILL_FOR_STATE = {
  idle:       "disconnected",
  connecting: "connecting",
  listening:  "recording",
  speaking:   "connected",
  error:      "error",
};

let state = "idle";

function setState(next) {
  if (!STATES.includes(next)) throw new Error("invalid state: " + next);
  state = next;
  // Button class swap (single class triggers per-state CSS)
  recordBtn.className = "btn btn-" + next;
  recordBtn.textContent = BTN_LABELS[next];
  recordBtn.disabled = (next === "speaking");
  recordBtn.setAttribute("aria-pressed", next === "listening" ? "true" : "false");
  recordBtn.setAttribute("aria-busy",    next === "connecting" ? "true" : "false");
  recordBtn.setAttribute("aria-disabled", next === "speaking" ? "true" : "false");
  // Status pill follows state.
  setPill(PILL_FOR_STATE[next]);
}

function setPill(pillState) {
  statusEl.textContent = PILL_LABELS[pillState];
  statusEl.className = "status " + pillState;
}

function nowHHMMSS() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `[${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}]`;
}

function appendLine(kind, text) {
  if (!placeholderEmitted) {
    transcriptEl.textContent = "";
    placeholderEmitted = true;
  }
  // Build a span so per-line color tokens apply (UI-SPEC Transcript line format).
  const span = document.createElement("span");
  span.className = "line-" + kind; // line-user | line-agent | line-system | line-error
  span.textContent = `${nowHHMMSS()} ${text}\n`;
  transcriptEl.appendChild(span);
  transcriptEl.scrollTop = transcriptEl.scrollHeight;
}

// WID-06 error trigger map (CONTEXT.md D-28 verbatim copy)
const WID06 = {
  micPermissionDenied: "Allow microphone access in your browser to start.",
  wsConnectFailed:     "Couldn't reach the agent — check your connection and retry.",
  agentTimeout:        "The agent didn't respond in time — try again.",
  micMuted:            "Microphone is muted — unmute to continue.",
  micUnmuted:          "Microphone unmuted.",
  getUserMediaUnsupported: "Microphone needs HTTPS. Open this page over https:// or use Chrome/Edge on localhost.",
};

function fail(kind, message) {
  appendLine("error", "Error: " + message);
  setState("error");
  // Force-stop capture on any error.
  stopCapture();
}

// --- Heartbeat (D-28 trigger: agent-timeout = 30s WS heartbeat with no inbound binary frame) ---
function armHeartbeat() {
  clearHeartbeat();
  inboundBinarySeen = false;
  agentTimeoutTimer = setTimeout(() => {
    if (!inboundBinarySeen) {
      fail("agent-timeout", WID06.agentTimeout);
      if (ws && ws.readyState <= 1) ws.close(4000, "agent-timeout");
    }
  }, HEARTBEAT_MS);
}

function clearHeartbeat() {
  if (agentTimeoutTimer) {
    clearTimeout(agentTimeoutTimer);
    agentTimeoutTimer = null;
  }
}

function waitForOpen(socket) {
  return new Promise((resolve, reject) => {
    if (socket.readyState === WebSocket.OPEN) return resolve();
    const onOpen  = ()    => { cleanup(); resolve(); };
    const onErr   = (ev)  => { cleanup(); reject(ev); };
    const onClose = (ev)  => { cleanup(); reject(ev); };
    function cleanup() {
      socket.removeEventListener("open",  onOpen);
      socket.removeEventListener("error", onErr);
      socket.removeEventListener("close", onClose);
    }
    socket.addEventListener("open",  onOpen,  { once: true });
    socket.addEventListener("error", onErr,   { once: true });
    socket.addEventListener("close", onClose, { once: true });
  });
}

async function resolveWsUrl() {
  // Local dev path: no presign URL configured -> use the local-dev sentinel.
  if (!PRESIGN_URL) return WS_LOCAL_DEV_URL;
  // Production path: fetch a short-lived presigned WSS URL from the Lambda
  // Function URL. Failures here flow through the existing ws-connect-failed
  // WID-06 branch (D-28 trigger).
  const resp = await fetch(PRESIGN_URL, { method: "GET", cache: "no-store" });
  if (!resp.ok) throw new Error("presign fetch failed: HTTP " + resp.status);
  const body = await resp.json();
  if (!body.url) throw new Error("presign response missing url");
  return body.url;
}

async function connect() {
  // Fetch the WSS URL FIRST (presign call); only then open the socket.
  // A presign-fetch failure raises and is caught by the click handler's
  // try/catch -> fail("ws-connect-failed", ...) (D-28 trigger).
  const wsUrl = await resolveWsUrl();
  ws = new WebSocket(wsUrl);
  ws.binaryType = "arraybuffer";

  if (!playbackCtx) playbackCtx = new AudioContext({ sampleRate: 24000 });

  ws.onopen = () => {
    appendLine("system", "Connected.");
  };

  ws.onclose = (ev) => {
    clearHeartbeat();
    stopCapture();
    if (playbackCtx) {
      const ctx = playbackCtx;
      playbackCtx = null;
      nextStart = 0;
      ctx.close().catch((e) => console.warn("playbackCtx close failed", e));
    }
    if (ev.code !== 1000 && state !== "error") {
      // D-28 trigger: ws-connect-failed = onclose with code != 1000.
      fail("ws-connect-failed", WID06.wsConnectFailed);
    } else if (state !== "error") {
      setState("idle");
      appendLine("system", "Disconnected.");
    }
  };

  ws.onerror = () => {
    // D-28 trigger: ws-connect-failed = ws.onerror.
    if (state !== "error") fail("ws-connect-failed", WID06.wsConnectFailed);
  };

  ws.onmessage = (event) => {
    if (typeof event.data === "string") {
      // Pipecat control text frame - surface as system line for visibility.
      appendLine("system", event.data);
      return;
    }
    inboundBinarySeen = true;
    armHeartbeat();
    // Bump UX state to "speaking" on first audio chunk; flip back to listening
    // after the playback queue drains.
    if (state === "listening") setState("speaking");
    const int16 = new Int16Array(event.data);
    const f32 = new Float32Array(int16.length);
    for (let i = 0; i < int16.length; i++) f32[i] = int16[i] / 32768;
    const buf = playbackCtx.createBuffer(1, f32.length, 24000);
    buf.copyToChannel(f32, 0);
    const src = playbackCtx.createBufferSource();
    src.buffer = buf;
    src.connect(playbackCtx.destination);
    const startAt = Math.max(playbackCtx.currentTime, nextStart);
    src.start(startAt);
    nextStart = startAt + buf.duration;
    src.onended = () => {
      if (state === "speaking" && playbackCtx && nextStart <= playbackCtx.currentTime + 0.05) {
        setState("listening");
      }
    };
  };
}

async function startCapture() {
  if (recording) return;

  if (playbackCtx && playbackCtx.state === "suspended") await playbackCtx.resume();

  // D-28 trigger: mic-permission-denied = getUserMedia reject. Caller fail() handles.
  mediaStream = await navigator.mediaDevices.getUserMedia({
    audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
  });

  // D-28 trigger: mic-muted = MediaStreamTrack.muted event.
  for (const track of mediaStream.getAudioTracks()) {
    track.addEventListener("mute", () => {
      micMutedEl.hidden = false;
      appendLine("error", WID06.micMuted);
    });
    track.addEventListener("unmute", () => {
      micMutedEl.hidden = true;
      appendLine("system", WID06.micUnmuted);
    });
  }

  captureCtx = new AudioContext();
  await captureCtx.audioWorklet.addModule("audio-capture-worklet.js");
  captureSource = captureCtx.createMediaStreamSource(mediaStream);
  captureNode = new AudioWorkletNode(captureCtx, "capture-processor");
  captureSource.connect(captureNode);

  let dropped = 0;
  captureNode.port.onmessage = (e) => {
    if (ws && ws.readyState === WebSocket.OPEN) { ws.send(e.data); return; }
    dropped += 1;
    if (dropped === 1 || dropped % 25 === 0) console.warn("[mic] WS not OPEN; dropped frame", dropped);
  };

  recording = true;
  armHeartbeat();
  appendLine("system", `Mic capture started @ ${captureCtx.sampleRate} Hz native, 16000 Hz wire.`);
}

function stopCapture() {
  if (!recording) return;
  recording = false;
  micMutedEl.hidden = true;
  if (captureNode)   { captureNode.disconnect();   captureNode   = null; }
  if (captureSource) { captureSource.disconnect(); captureSource = null; }
  if (captureCtx)    { captureCtx.close();         captureCtx    = null; }
  if (mediaStream)   { mediaStream.getTracks().forEach((t) => t.stop()); mediaStream = null; }
  appendLine("system", "Mic capture stopped.");
}

async function init() {
  // D-28 trigger: getUserMedia unsupported (non-HTTPS origin).
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    fail("getusermedia-unsupported", WID06.getUserMediaUnsupported);
    recordBtn.disabled = true;
    return;
  }

  setState("idle");
  recordBtn.disabled = false;

  recordBtn.addEventListener("click", async () => {
    if (state === "speaking") return; // disabled
    if (state === "error") {
      // Reset to idle and let user retry.
      placeholderEmitted = true; // keep the error history visible - do not wipe transcript
      setState("idle");
      return;
    }
    if (state === "listening") {
      stopCapture();
      if (ws && ws.readyState <= 1) ws.close(1000, "user-stop");
      setState("idle");
      return;
    }
    // state === "idle" -> connect + capture.
    setState("connecting");
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      try {
        await connect();
        await waitForOpen(ws);
      } catch {
        fail("ws-connect-failed", WID06.wsConnectFailed);
        return;
      }
    }
    setState("listening");
    try {
      await startCapture();
    } catch (e) {
      // getUserMedia reject branch -> mic-permission-denied (D-28 trigger).
      fail("mic-permission-denied", WID06.micPermissionDenied);
      console.error("mic error", e);
    }
  });
}

init();
