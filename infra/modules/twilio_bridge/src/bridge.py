"""Per-call coroutine: terminate Twilio Media Streams WS, open SigV4-signed
upstream WSS to AgentCore Runtime, bidirectionally bridge resampled audio.

Architecture (D-56 REVISED — App Runner long-running container):
    Twilio WS  <-FastAPI->  handle_twilio_call coroutine  <-websockets->  AgentCore /ws

For each accepted call:
  1. Wait for Twilio `start` event (captures CallSid + streamSid).
  2. SigV4-sign + open upstream WSS to bedrock-agentcore (server-side, NOT
     a presigned URL for browser — we sign the GET upgrade request directly).
  3. Run two pumps in asyncio.gather:
     - inbound:  Twilio media frames -> mu-law decode -> ratecv 8k->16k -> upstream send
     - outbound: upstream Int16 frames -> ratecv inrate->8k -> mu-law encode -> Twilio send
  4. Exit on Twilio `stop` event or upstream close.

SigV4 mechanics mirror infra/modules/widget_presigner/src/handler.py
(REGION + RUNTIME_ARN + SERVICE + HOST + ENCODED_ARN + URL constants are the
same shape) but use SigV4Auth (header) instead of SigV4QueryAuth (URL query)
because we sign an outgoing WS upgrade, not mint a presigned URL for the
browser.

Sonic 8-min stream cap (Phase 2 D-19, AGT-05) is handled inside the agent's
Pipecat pipeline via SessionContinuationParams(transition_threshold_seconds=360)
— the bridge sees stream rotation as normal Sonic events and does NOT need to
handle it.

The Sonic output sample rate over `bedrock-agentcore /ws` is currently
treated as 16000 Hz; Plan 06-03 dial-in smoke confirms this against the live
Runtime and adjusts SONIC_OUTPUT_RATE_HZ if it turns out to be 24000 (D-59
open caveat).
"""

import asyncio
import base64
import json
from urllib.parse import quote

import logging

import websockets
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.session import Session
from fastapi import WebSocket

from src.config import AGENTCORE_RUNTIME_ARN, AWS_REGION
from src.resample import sonic_to_twilio, twilio_to_sonic

logger = logging.getLogger(__name__)

SERVICE = "bedrock-agentcore"
HOST = f"bedrock-agentcore.{AWS_REGION}.amazonaws.com"
ENCODED_ARN = quote(AGENTCORE_RUNTIME_ARN, safe="")
WSS_URL_BASE = f"wss://{HOST}/runtimes/{ENCODED_ARN}/ws?qualifier=DEFAULT"
HTTPS_URL_BASE = f"https://{HOST}/runtimes/{ENCODED_ARN}/ws?qualifier=DEFAULT"

# Phase 2 RUNBOOK says Pipecat default OUT is 24 kHz Int16 (AGT-07); the
# AgentCore data-plane WSS framing rate may differ. Plan 06-03 confirms
# against live Runtime and updates this constant if the live probe shows 24k.
SONIC_OUTPUT_RATE_HZ = 16000

_SESSION = Session()


def _signed_upstream_headers(session_id: str) -> dict:
    """SigV4-sign the GET upgrade request and return the headers dict.

    Mechanics mirror widget_presigner/src/handler.py:_presign_wss_url, but
    as Authorization-header auth on an outgoing WS upgrade (SigV4Auth)
    rather than a presigned URL for browsers (SigV4QueryAuth).

    The X-Amzn-Bedrock-AgentCore-Runtime-Session-Id header (per AWS docs
    runtime-get-started-websocket.html) carries the Twilio CallSid so each
    phone call gets a distinct AgentCore session — same session-id-per-call
    contract the widget already uses (browser uses a UUID).
    """
    creds = _SESSION.get_credentials().get_frozen_credentials()
    request = AWSRequest(method="GET", url=HTTPS_URL_BASE)
    request.headers["X-Amzn-Bedrock-AgentCore-Runtime-Session-Id"] = session_id
    SigV4Auth(creds, SERVICE, AWS_REGION).add_auth(request)
    return dict(request.headers.items())


async def handle_twilio_call(twilio_ws: WebSocket) -> None:
    """One coroutine per phone call. Holds upstream WSS open for the call
    duration. Returns when Twilio sends `stop` or upstream closes.
    """
    # 1. Drain `connected` + wait for `start` event to capture call metadata.
    call_sid: str | None = None
    stream_sid: str | None = None
    while call_sid is None:
        msg = await twilio_ws.receive_text()
        payload = json.loads(msg)
        event = payload.get("event")
        if event == "connected":
            logger.info("Twilio connected: protocol=%s", payload.get("protocol"))
            continue
        if event == "start":
            call_sid = payload["start"]["callSid"]
            stream_sid = payload["start"]["streamSid"]
            logger.info(
                "Twilio start: callSid=%s streamSid=%s mediaFormat=%s",
                call_sid,
                stream_sid,
                payload["start"].get("mediaFormat"),
            )
            continue
        logger.warning("unexpected pre-start event: %s", event)

    # 2. Open SigV4-signed upstream WSS for the call duration.
    headers = _signed_upstream_headers(call_sid)
    async with websockets.connect(WSS_URL_BASE, additional_headers=headers) as upstream:
        logger.info("AgentCore upstream WSS open for callSid=%s", call_sid)

        # ratecv state threaded across frames per direction (Pitfall 4).
        # in_state owned by pump_twilio_to_sonic; out_state owned by
        # pump_sonic_to_twilio; no shared state, no lock needed (WARNING-3).
        in_state: object | None = None
        out_state: object | None = None

        async def pump_twilio_to_sonic() -> None:
            nonlocal in_state
            while True:
                msg = await twilio_ws.receive_text()
                payload = json.loads(msg)
                event = payload.get("event")
                if event == "media":
                    mulaw_8k = base64.b64decode(payload["media"]["payload"])
                    pcm16_16k, in_state = twilio_to_sonic(mulaw_8k, in_state)
                    await upstream.send(pcm16_16k)
                elif event == "stop":
                    logger.info("Twilio stop received; closing pumps")
                    return
                elif event in ("mark", "dtmf"):
                    # Ignored for v2 minimum bridge scope.
                    continue
                else:
                    logger.warning("unexpected mid-call event: %s", event)

        async def pump_sonic_to_twilio() -> None:
            nonlocal out_state
            async for frame in upstream:
                # AgentCore upstream emits Int16 LE bytes for audio frames.
                # Plan 06-03 confirms framing rate against live Runtime.
                if isinstance(frame, bytes):
                    mulaw_8k, out_state = sonic_to_twilio(
                        frame, SONIC_OUTPUT_RATE_HZ, out_state
                    )
                    b64 = base64.b64encode(mulaw_8k).decode("ascii")
                    envelope = json.dumps(
                        {
                            "event": "media",
                            "streamSid": stream_sid,
                            "media": {"payload": b64},
                        }
                    )
                    await twilio_ws.send_text(envelope)
                else:
                    # Text frames from AgentCore (transcript / tool events) are
                    # dropped at DEBUG-level so the operator can correlate via
                    # `aws logs tail` (WARNING-4 fix). The phone handset never
                    # surfaces transcript; this trace is diagnostic only.
                    logger.debug("dropped AgentCore non-audio frame: %r", frame[:80])
                    continue

        # 3. Run both pumps concurrently. Whichever finishes first cancels
        # the other; asyncio.gather propagates the first exception.
        done, pending = await asyncio.wait(
            {asyncio.create_task(pump_twilio_to_sonic()), asyncio.create_task(pump_sonic_to_twilio())},
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending:
            task.cancel()
        for task in done:
            # Surface any exception from the completed pump (root-cause
            # discipline).
            task.result()
    logger.info("AgentCore upstream closed for callSid=%s", call_sid)
