"""FastAPI entrypoint for the Hera Twilio Bridge.

Exposes two routes on port 8080:
- GET           /ping     : App Runner health probe (returns {"status":"Healthy",...}).
- WebSocket     /twilio   : Twilio Media Streams terminator. One per phone call.

D-67: X-Twilio-Signature HMAC validation runs at the WS upgrade BEFORE accept().
"""

from datetime import datetime, timezone

import logging

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from src.bridge import handle_twilio_call
from src.config import validate_twilio_signature

logger = logging.getLogger(__name__)
app = FastAPI(title="hera-twilio-bridge", version="0.1.0")

# Captured once at module import. The /ping field name promises "when state
# last changed", which for this stateless bridge is process boot time.
_BOOT_TIME = int(datetime.now(tz=timezone.utc).timestamp())


@app.get("/ping")
async def ping() -> dict:
    """App Runner health probe (HTTP 200 -> status=Healthy)."""
    return {
        "status": "Healthy",
        "time_of_last_update": _BOOT_TIME,
    }


@app.websocket("/twilio")
async def twilio_endpoint(websocket: WebSocket) -> None:
    """Per-call Twilio Media Streams handler. Closes when Twilio sends `stop`
    or peer hangs up.
    """
    validate_twilio_signature(websocket)
    await websocket.accept()
    logger.info("Twilio WS accepted")
    # The only try/except in this module: WebSocketDisconnect is the normal
    # protocol-close path, not error suppression. All other exceptions bubble
    # up so uvicorn logs them and App Runner CloudWatch surfaces the
    # root-cause for the operator (AGENTS.md mandate).
    try:
        await handle_twilio_call(websocket)
    except WebSocketDisconnect:
        logger.info("Twilio WS disconnected")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
