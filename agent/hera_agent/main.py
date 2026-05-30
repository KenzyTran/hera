"""FastAPI entrypoint for the Hera Pipecat agent.

Exposes routes on port 8080:
- GET  /ping          : AgentCore Runtime health check (returns {"status":"Healthy"}).
- POST /invocations   : AgentCore HTTP data-plane stub. Voice loop runs on /ws.
- WebSocket /ws       : Browser voice pipeline (raw PCM). One pipeline per connection.
- POST /twiml         : Twilio voice webhook — returns TwiML to open a Media Stream.
- WebSocket /twilio   : Twilio Media Streams pipeline. One pipeline per phone call.
"""

import json
import os
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse, Response
from loguru import logger

from hera_agent.logging_setup import configure_logging
from hera_agent.pipeline import run_pipeline, run_twilio_pipeline
from hera_agent.tracing import flush as flush_tracing, init_tracing

configure_logging()
# Must run BEFORE Langfuse() so both Pipecat and Langfuse SDK share the
# global OTEL TracerProvider.
init_tracing()

app = FastAPI(title="hera-agent", version="0.1.0")

# Captured once at module import. The /ping field name promises "when state
# last changed", which for this stateless agent is process boot time. Using
# tz-aware UTC so the integer matches operator-side log timestamps regardless
# of the host's local zone.
_BOOT_TIME = int(datetime.now(tz=timezone.utc).timestamp())


@app.get("/ping")
async def ping() -> dict:
    """AgentCore Runtime health probe (HTTP 200 -> status=Healthy)."""
    return {
        "status": "Healthy",
        "time_of_last_update": _BOOT_TIME,
    }


@app.post("/invocations")
async def invocations() -> JSONResponse:
    """AgentCore HTTP data-plane stub. Voice loop runs on /ws (D-31)."""
    return JSONResponse({
        "agent": "hera-pipecat-sonic",
        "status": "running",
        "model": "amazon.nova-2-sonic-v1:0",
    })


_LANGFUSE_ENABLED = bool(os.environ.get("LANGFUSE_SECRET_KEY"))
_lf = None
if _LANGFUSE_ENABLED:
    try:
        from langfuse import Langfuse
        _lf = Langfuse()
        logger.info(
            f"Langfuse client initialized: host={os.environ.get('LANGFUSE_HOST')} "
            f"public_key={os.environ.get('LANGFUSE_PUBLIC_KEY','')[:12]}... "
            f"auth_check={_lf.auth_check()}"
        )
    except Exception as e:
        logger.exception(f"Langfuse init failed: {e}")
        _lf = None
        _LANGFUSE_ENABLED = False
else:
    logger.info("Langfuse disabled (LANGFUSE_SECRET_KEY not set)")


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket) -> None:
    """Per-connection Pipecat pipeline. Closes when the client disconnects."""
    await websocket.accept()
    logger.info("WS client connected")
    session_id = str(uuid.uuid4())

    try:
        await run_pipeline(websocket, session_id=session_id)
    except WebSocketDisconnect:
        logger.info("WS client disconnected")
    except Exception:
        logger.exception("WS pipeline failed")
        raise
    finally:
        # Flush the global OTEL provider (holds the Langfuse OTLP exporter and
        # ALL spans: conversation / turn / lookup_product / kb_retrieve) before
        # the AgentCore microVM freezes. _lf.flush() only drains the separate
        # Langfuse SDK provider, which no longer carries any spans.
        flush_tracing()
        if _LANGFUSE_ENABLED and _lf is not None:
            _lf.flush()


async def _parse_twilio_start(websocket: WebSocket) -> dict:
    """Read initial Twilio Media Streams events to extract stream_sid and call_sid."""
    while True:
        msg = await websocket.receive_text()
        payload = json.loads(msg)
        if payload.get("event") == "start":
            return {
                "stream_sid": payload["start"]["streamSid"],
                "call_sid": payload["start"]["callSid"],
            }


@app.post("/twiml")
async def twiml_webhook(request: Request) -> Response:
    """Return TwiML instructing Twilio to open a Media Stream to /twilio."""
    host = request.headers.get("host", "localhost:8080")
    proto = request.headers.get("x-forwarded-proto", request.url.scheme)
    ws_scheme = "wss" if proto == "https" else "ws"
    twiml = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        "<Response>"
        f'<Connect><Stream url="{ws_scheme}://{host}/twilio" /></Connect>'
        "</Response>"
    )
    return Response(content=twiml, media_type="application/xml")


@app.websocket("/twilio")
async def twilio_ws_endpoint(websocket: WebSocket) -> None:
    """Per-call Twilio Media Streams handler. One Pipecat pipeline per phone call."""
    await websocket.accept()
    logger.info("Twilio WS connected")
    call_data = await _parse_twilio_start(websocket)
    call_sid = call_data["call_sid"]
    stream_sid = call_data["stream_sid"]
    logger.info(f"Twilio call started: call_sid={call_sid} stream_sid={stream_sid}")

    try:
        await run_twilio_pipeline(websocket, stream_sid, call_sid)
    except WebSocketDisconnect:
        logger.info("Twilio WS disconnected")
    except Exception:
        logger.exception("Twilio pipeline failed")
        raise
    finally:
        # Flush the global OTEL provider (holds the Langfuse OTLP exporter and
        # ALL spans: conversation / turn / lookup_product / kb_retrieve) before
        # the AgentCore microVM freezes. _lf.flush() only drains the separate
        # Langfuse SDK provider, which no longer carries any spans.
        flush_tracing()
        if _LANGFUSE_ENABLED and _lf is not None:
            _lf.flush()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
