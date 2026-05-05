"""FastAPI entrypoint for the Hera Pipecat agent.

Exposes two routes on port 8080:
- GET /ping       : AgentCore Runtime health check (returns {"status":"Healthy"}).
- WebSocket /ws   : Pipecat voice pipeline. One pipeline per connection.

This single-app shape matches the AgentCore HTTP service contract verbatim, so
Phase 3 deploys without a transport refactor.
"""

from datetime import datetime, timezone

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from loguru import logger

from hera_agent.pipeline import run_pipeline

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


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket) -> None:
    """Per-connection Pipecat pipeline. Closes when the client disconnects."""
    await websocket.accept()
    logger.info("WS client connected")
    # The only try/except in this module: WebSocketDisconnect is the normal
    # disconnect path, not error suppression. All other exceptions bubble up so
    # uvicorn logs them and the operator can root-cause (AGENTS.md mandate).
    try:
        await run_pipeline(websocket)
    except WebSocketDisconnect:
        logger.info("WS client disconnected")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
