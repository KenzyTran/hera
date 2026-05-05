// Hera Phase 2 - browser <-> agent WebSocket client.
//
// Capture path: getUserMedia -> AudioContext -> AudioWorkletNode (downsample
// to 16 kHz Int16 mono) -> binary WS frame to ws://localhost:8080/ws.
//
// Playback path: WS binary frame (24 kHz Int16 mono) -> Int16Array decode ->
// Float32 normalize -> AudioBuffer at 24 kHz -> sequential AudioBufferSourceNode
// queue (avoids clicks/dropouts on multi-frame responses).
//
// Patterns 6 + 7 from research/02-RESEARCH.md, verbatim.

const WS_URL = "ws://localhost:8080/ws";

const statusEl = document.getElementById("status");
const recordBtn = document.getElementById("recordBtn");
const transcriptEl = document.getElementById("transcript");

let ws = null;
let captureCtx = null;
let captureNode = null;
let captureSource = null;
let mediaStream = null;
let playbackCtx = null;
let nextStart = 0;
let recording = false;

function setStatus(text, cls) {
  statusEl.textContent = text;
  statusEl.className = "status" + (cls ? " " + cls : "");
}

function appendTranscript(line) {
  transcriptEl.textContent += line + "\n";
  transcriptEl.scrollTop = transcriptEl.scrollHeight;
}

async function connect() {
  setStatus("connecting...");
  ws = new WebSocket(WS_URL);
  ws.binaryType = "arraybuffer";

  // Reset playback queue on each new connection.
  if (!playbackCtx) {
    playbackCtx = new AudioContext({ sampleRate: 24000 });
  }

  ws.onopen = () => {
    setStatus("connected", "connected");
    appendTranscript("[ws] connected to " + WS_URL);
  };

  ws.onclose = (ev) => {
    setStatus("disconnected");
    appendTranscript("[ws] closed code=" + ev.code + " reason=" + (ev.reason || "(none)"));
    stopCapture();
  };

  ws.onerror = (ev) => {
    setStatus("error", "error");
    appendTranscript("[ws] error (see DevTools console for details)");
    console.error("ws error", ev);
  };

  ws.onmessage = (event) => {
    if (typeof event.data === "string") {
      // Control / transcript text frame from Pipecat.
      appendTranscript("[text] " + event.data);
      return;
    }
    // Binary frame: 24 kHz mono Int16 PCM. Schedule sequentially so multi-
    // frame responses play without clicks/dropouts.
    const int16 = new Int16Array(event.data);
    const float32 = new Float32Array(int16.length);
    for (let i = 0; i < int16.length; i++) float32[i] = int16[i] / 32768;
    const buffer = playbackCtx.createBuffer(1, float32.length, 24000);
    buffer.copyToChannel(float32, 0);
    const src = playbackCtx.createBufferSource();
    src.buffer = buffer;
    src.connect(playbackCtx.destination);
    const startAt = Math.max(playbackCtx.currentTime, nextStart);
    src.start(startAt);
    nextStart = startAt + buffer.duration;
  };
}

async function startCapture() {
  if (recording) return;

  // Resume playback context (browser autoplay policy: needs user gesture).
  if (playbackCtx && playbackCtx.state === "suspended") {
    await playbackCtx.resume();
  }

  mediaStream = await navigator.mediaDevices.getUserMedia({
    audio: {
      channelCount: 1,
      echoCancellation: true,
      noiseSuppression: true,
    },
  });

  // captureCtx defaults to the device's native rate (often 48 kHz). The
  // worklet downsamples to 16 kHz before posting to main thread.
  captureCtx = new AudioContext();
  await captureCtx.audioWorklet.addModule("audio-capture-worklet.js");

  captureSource = captureCtx.createMediaStreamSource(mediaStream);
  captureNode = new AudioWorkletNode(captureCtx, "capture-processor");
  captureSource.connect(captureNode);

  captureNode.port.onmessage = (e) => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(e.data); // raw 16 kHz Int16 LE PCM
    }
  };

  recording = true;
  recordBtn.textContent = "Recording (click to stop)";
  recordBtn.classList.add("recording");
  setStatus("recording", "connected");
  appendTranscript("[mic] capture started @ " + captureCtx.sampleRate + " Hz native, 16000 Hz wire");
}

function stopCapture() {
  if (!recording) return;
  recording = false;
  recordBtn.textContent = "Record";
  recordBtn.classList.remove("recording");
  if (captureNode) { captureNode.disconnect(); captureNode = null; }
  if (captureSource) { captureSource.disconnect(); captureSource = null; }
  if (captureCtx) { captureCtx.close(); captureCtx = null; }
  if (mediaStream) {
    mediaStream.getTracks().forEach((t) => t.stop());
    mediaStream = null;
  }
  appendTranscript("[mic] capture stopped");
}

async function init() {
  // Probe getUserMedia availability (some browsers / non-HTTPS origins block it).
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    setStatus("getUserMedia unsupported", "error");
    appendTranscript("[init] navigator.mediaDevices.getUserMedia is unavailable. Use Chrome/Edge over http://localhost or HTTPS.");
    return;
  }

  recordBtn.disabled = false;
  recordBtn.textContent = "Record";

  recordBtn.addEventListener("click", async () => {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      await connect();
      // Wait briefly for ws.onopen.
      await new Promise((r) => setTimeout(r, 200));
    }
    if (recording) {
      stopCapture();
    } else {
      try {
        await startCapture();
      } catch (e) {
        // Mic permission denied or device unavailable. Surface clearly; do
        // not silently retry (per AGENTS.md root-cause discipline).
        setStatus("mic error", "error");
        appendTranscript("[mic] error: " + e.message);
        console.error("mic error", e);
      }
    }
  });
}

init();
