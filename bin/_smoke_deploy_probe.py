"""Live AgentCore WSS smoke probe.

Mirrors bin/_smoke_voice_probe.py (Phase 2 AGT-04 gate) but targets the live
public AgentCore WSS endpoint with TLS. Asserts >=1 inbound binary frame
arrives within LATENCY_BUDGET_S of end-of-send. Cold-start budget is more
generous than Phase 2's local 3s gate because AgentCore container cold-starts
are slower than an already-running docker-compose.

Usage:  AGENTCORE_WSS_URL=wss://... uv run python bin/_smoke_deploy_probe.py

Exit codes:
  0  - first binary frame arrived within budget
  1  - no binary frame arrived in time
  2  - WS could not be opened
  3  - missing AGENTCORE_WSS_URL env var
"""

from __future__ import annotations

import asyncio
import os
import sys
import time

import websockets

LATENCY_BUDGET_S = 10.0
SILENCE_DURATION_S = 1.0
SAMPLE_RATE_HZ = 16000


def _silence_int16(duration_s: float, rate_hz: int) -> bytes:
    n_samples = int(duration_s * rate_hz)
    # Int16 little-endian PCM, 2 bytes per sample, all zeros = silence.
    return b"\x00\x00" * n_samples


async def main() -> int:
    url = os.environ.get("AGENTCORE_WSS_URL")
    if not url:
        sys.stderr.write("ERROR: AGENTCORE_WSS_URL not set.\n")
        return 3

    sys.stdout.write(f"connecting to {url} ...\n")
    sys.stdout.flush()

    silence = _silence_int16(SILENCE_DURATION_S, SAMPLE_RATE_HZ)

    # `wss://` => TLS via the standard library SSL context. The websockets
    # client picks this up from the URL scheme.
    async with websockets.connect(url, max_size=None) as ws:
        sys.stdout.write("connected; streaming 1s of 16 kHz Int16 silence ...\n")
        # Stream silence in 100ms quanta (3200 bytes each) to mimic browser
        # AudioWorklet send cadence.
        chunk_bytes = int(SAMPLE_RATE_HZ * 0.1) * 2
        for i in range(0, len(silence), chunk_bytes):
            await ws.send(silence[i : i + chunk_bytes])

        sys.stdout.write("send complete; awaiting first inbound binary frame ...\n")
        start = time.monotonic()
        try:
            while True:
                msg = await asyncio.wait_for(ws.recv(), timeout=LATENCY_BUDGET_S)
                if isinstance(msg, (bytes, bytearray)):
                    elapsed_ms = int((time.monotonic() - start) * 1000)
                    sys.stdout.write(f"OK: first binary frame in {elapsed_ms}ms\n")
                    return 0
                # Skip text frames (Pipecat control frames may arrive first).
                sys.stdout.write(f"text frame: {msg!r}\n")
        except asyncio.TimeoutError:
            sys.stderr.write(
                f"FAIL: no binary frame within {LATENCY_BUDGET_S}s budget.\n"
            )
            return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
