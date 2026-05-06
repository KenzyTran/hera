"""Live AgentCore WSS smoke probe (Plan 03-04 Rule-4 update).

Mirrors the browser flow exactly: fetch the presign URL first, then open the
returned wss:// URL with TLS, stream 1s of synthetic 16 kHz Int16 silence,
and assert >=1 inbound binary frame within LATENCY_BUDGET_S. Cold-start
budget is more generous than Phase 2's local 3s gate because AgentCore
container cold-starts are slower than an already-running docker-compose.

Usage (production presign+fetch flow):
    PRESIGN_URL=https://....lambda-url.ap-northeast-1.on.aws/ \\
        uv run python bin/_smoke_deploy_probe.py

Usage (legacy direct-WSS flow, e.g. local docker-compose):
    AGENTCORE_WSS_URL=ws://localhost:8080/ws \\
        uv run python bin/_smoke_deploy_probe.py

Exit codes:
  0  - first binary frame arrived within budget
  1  - no binary frame arrived in time
  2  - WS could not be opened (or presign fetch failed)
  3  - missing both PRESIGN_URL and AGENTCORE_WSS_URL env vars
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import time
import urllib.request

import websockets

LATENCY_BUDGET_S = 10.0
SILENCE_DURATION_S = 1.0
SAMPLE_RATE_HZ = 16000


def _silence_int16(duration_s: float, rate_hz: int) -> bytes:
    n_samples = int(duration_s * rate_hz)
    # Int16 little-endian PCM, 2 bytes per sample, all zeros = silence.
    return b"\x00\x00" * n_samples


def _resolve_wss_url() -> str | None:
    """PRESIGN_URL -> fetch -> .url (mirrors browser). Falls back to direct AGENTCORE_WSS_URL."""
    presign_url = os.environ.get("PRESIGN_URL")
    if presign_url:
        sys.stdout.write(f"fetching presign URL from {presign_url} ...\n")
        sys.stdout.flush()
        with urllib.request.urlopen(presign_url, timeout=5) as resp:
            payload = json.loads(resp.read())
        url = payload.get("url")
        if not url:
            sys.stderr.write(f"ERROR: presign response missing 'url': {payload!r}\n")
            return None
        return url
    return os.environ.get("AGENTCORE_WSS_URL")


async def main() -> int:
    url = _resolve_wss_url()
    if not url:
        sys.stderr.write(
            "ERROR: neither PRESIGN_URL nor AGENTCORE_WSS_URL is set.\n"
        )
        return 3

    sys.stdout.write(f"connecting to {url[:80]}{'...' if len(url) > 80 else ''}\n")
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
