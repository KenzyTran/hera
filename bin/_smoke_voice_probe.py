"""AGT-04 latency probe: end-of-send to first inbound binary frame.

Connects to ws://localhost:8080/ws (the live Pipecat agent), sends ~1 second
of synthetic 16 kHz mono Int16 silence as raw binary frames, then awaits the
first inbound binary frame (Sonic's greeting / acknowledgement audio). The
elapsed monotonic time between end-of-send and first inbound binary frame is
the measured latency. Exits 0 if elapsed < 3.0 seconds, 1 otherwise.

Why silence: a real spoken question would consume KB tokens and add jitter
from VAD / KB Retrieve round-trip. The on_client_connected handler in
hera_agent.pipeline.py queues an LLMRunFrame that prompts Sonic to greet -
that greeting audio is the first inbound binary frame, and its time to first
byte is what AGT-04 measures.

Run with: cd agent && uv run python ../bin/_smoke_voice_probe.py
(running outside the agent/.venv will fail with ModuleNotFoundError: websockets)

Exit codes:
  0   measured latency < 3.0 seconds (AGT-04 gate passed)
  1   measured latency >= 3.0 seconds OR no inbound binary frame within 10s
"""

import asyncio
import sys
import time

import websockets

WS_URL = "ws://localhost:8080/ws"
SAMPLE_RATE_HZ = 16000
CLIP_SECONDS = 1.0
FRAME_SAMPLES = 320  # 20ms frames at 16 kHz, matches Pipecat default
LATENCY_BUDGET_SECONDS = 3.0
INBOUND_TIMEOUT_SECONDS = 10.0


async def probe() -> int:
    silence_frame = (b"\x00\x00") * FRAME_SAMPLES  # 320 Int16 LE zeros
    total_frames = int((SAMPLE_RATE_HZ * CLIP_SECONDS) / FRAME_SAMPLES)

    async with websockets.connect(WS_URL, max_size=None) as ws:
        # Stream silence frames at real time so VAD treats this as a normal mic feed.
        for _ in range(total_frames):
            await ws.send(silence_frame)
            await asyncio.sleep(FRAME_SAMPLES / SAMPLE_RATE_HZ)
        end_of_send = time.monotonic()

        # Await the first inbound frame that is binary (text frames are control/transcript).
        deadline = end_of_send + INBOUND_TIMEOUT_SECONDS
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                print("FAIL: no inbound binary frame within 10s of end-of-send", file=sys.stderr)
                return 1
            msg = await asyncio.wait_for(ws.recv(), timeout=remaining)
            if isinstance(msg, (bytes, bytearray)):
                first_inbound = time.monotonic()
                break
            # Text frame (control / transcript) - keep waiting for first audio.

    elapsed = first_inbound - end_of_send
    print(f"LATENCY_MS={int(elapsed * 1000)}")
    if elapsed >= LATENCY_BUDGET_SECONDS:
        print(f"FAIL: latency {elapsed:.3f}s >= AGT-04 budget {LATENCY_BUDGET_SECONDS}s", file=sys.stderr)
        return 1
    print(f"OK: latency {elapsed:.3f}s < AGT-04 budget {LATENCY_BUDGET_SECONDS}s")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(probe()))
