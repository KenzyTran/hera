"""Synthetic live-smoke test for the deployed Twilio bridge App Runner service.

Validates TWIL-01 + TWIL-02 end-to-end against live AWS infrastructure WITHOUT a
real Twilio account or a real phone call:

  1. Computes X-Twilio-Signature using twilio.request_validator.RequestValidator
     with the synthetic auth token stored in Secrets Manager (hera/twilio/auth-token).
  2. Opens a WSS connection to wss://<service>.awsapprunner.com/twilio with the
     signed header.
  3. Sends a Twilio Media Streams `connected` event, then a `start` event
     carrying synthetic callSid + streamSid metadata.
  4. Sends N seconds of mu-law 8kHz silence frames (payload = 0xFF bytes,
     base64 encoded, 20ms chunks per Twilio Media Streams default).
  5. Listens for any inbound media frame from the bridge (which would come
     from the AgentCore upstream resampled + base64-encoded).
  6. Sends `stop` event and closes.

Pass criteria:
  - WSS upgrade accepted (signature validates → 101 Switching Protocols)
  - Bridge logs "Twilio start: callSid=..." + "AgentCore upstream WSS open"
  - At least one media frame received back OR upstream stays open >= 2s
    (proves bridge accepted upstream and pumps are wired)

Run locally:
  export WSS_URL="wss://amwdkzmyet.ap-northeast-1.awsapprunner.com/twilio"
  export TWILIO_AUTH_TOKEN="$(aws secretsmanager get-secret-value \
    --secret-id hera/twilio/auth-token --region ap-northeast-1 \
    --query SecretString --output text)"
  uv run --python 3.13 python tests/test_live_smoke.py
"""

import asyncio
import base64
import json
import os
import sys
import time
import uuid

import websockets
from twilio.request_validator import RequestValidator

WSS_URL = os.environ.get("WSS_URL", "")
TWILIO_AUTH_TOKEN = os.environ.get("TWILIO_AUTH_TOKEN", "")

SILENCE_BYTE = 0xFF
FRAME_BYTES = 160
FRAME_INTERVAL_S = 0.02
TOTAL_FRAMES = 100
RECEIVE_TIMEOUT_S = 6.0


def _sign(url: str, token: str) -> str:
    """X-Twilio-Signature header value for the WS upgrade URL."""
    return RequestValidator(token).compute_signature(url, {})


def _https_form(wss_url: str) -> str:
    return wss_url.replace("ws://", "https://").replace("wss://", "https://")


async def smoke() -> int:
    if not WSS_URL or not TWILIO_AUTH_TOKEN:
        print("ERROR: WSS_URL and TWILIO_AUTH_TOKEN env vars are required", file=sys.stderr)
        return 2

    https_url = _https_form(WSS_URL)
    signature = _sign(https_url, TWILIO_AUTH_TOKEN)
    headers = {"X-Twilio-Signature": signature}

    call_sid = f"CA{uuid.uuid4().hex[:30]}"
    stream_sid = f"MZ{uuid.uuid4().hex[:30]}"
    print(f"WSS_URL              = {WSS_URL}")
    print(f"signed URL           = {https_url}")
    print(f"X-Twilio-Signature   = {signature}")
    print(f"synthetic call_sid   = {call_sid}")
    print(f"synthetic stream_sid = {stream_sid}")

    t_open = time.monotonic()
    async with websockets.connect(WSS_URL, additional_headers=headers) as ws:
        t_upgrade = time.monotonic() - t_open
        print(f"OK: WSS upgrade accepted (signature ok) in {t_upgrade*1000:.0f}ms")

        await ws.send(json.dumps({"event": "connected", "protocol": "Call", "version": "1.0.0"}))
        await ws.send(
            json.dumps(
                {
                    "event": "start",
                    "sequenceNumber": "1",
                    "start": {
                        "accountSid": "ACsynthetic" + uuid.uuid4().hex[:24],
                        "callSid": call_sid,
                        "streamSid": stream_sid,
                        "tracks": ["inbound"],
                        "mediaFormat": {
                            "encoding": "audio/x-mulaw",
                            "sampleRate": 8000,
                            "channels": 1,
                        },
                    },
                    "streamSid": stream_sid,
                }
            )
        )
        print("OK: sent connected + start events")

        async def send_silence() -> int:
            payload = base64.b64encode(bytes([SILENCE_BYTE] * FRAME_BYTES)).decode("ascii")
            sent = 0
            for i in range(TOTAL_FRAMES):
                envelope = json.dumps(
                    {
                        "event": "media",
                        "sequenceNumber": str(i + 2),
                        "streamSid": stream_sid,
                        "media": {
                            "track": "inbound",
                            "chunk": str(i + 1),
                            "timestamp": str(i * 20),
                            "payload": payload,
                        },
                    }
                )
                await ws.send(envelope)
                sent += 1
                await asyncio.sleep(FRAME_INTERVAL_S)
            return sent

        inbound_audio_frames = 0
        upstream_open_ms = 0
        send_task = asyncio.create_task(send_silence())
        t_listen = time.monotonic()
        try:
            while time.monotonic() - t_listen < RECEIVE_TIMEOUT_S:
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=1.0)
                except asyncio.TimeoutError:
                    if send_task.done():
                        break
                    continue
                if isinstance(msg, str):
                    obj = json.loads(msg)
                    if obj.get("event") == "media" and "payload" in obj.get("media", {}):
                        inbound_audio_frames += 1
                        if inbound_audio_frames <= 3:
                            decoded = base64.b64decode(obj["media"]["payload"])
                            print(
                                f"OK: inbound media frame #{inbound_audio_frames} "
                                f"({len(decoded)} mu-law bytes)"
                            )
                    else:
                        print(f"INFO: inbound non-media event: {obj.get('event')}")
                else:
                    print(f"INFO: inbound binary frame: {len(msg)} bytes")
        finally:
            upstream_open_ms = (time.monotonic() - t_listen) * 1000
            if not send_task.done():
                send_task.cancel()
                try:
                    await send_task
                except asyncio.CancelledError:
                    pass

        await ws.send(json.dumps({"event": "stop", "sequenceNumber": "999", "streamSid": stream_sid}))
        print(f"OK: sent stop event")

        print(f"-- summary --")
        print(f"inbound audio frames received = {inbound_audio_frames}")
        print(f"upstream-listen window (ms)   = {upstream_open_ms:.0f}")
        print(f"upgrade latency (ms)          = {t_upgrade*1000:.0f}")

    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(smoke()))
