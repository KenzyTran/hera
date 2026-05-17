"""FastAPI entrypoint for the Hera Pipecat agent.

Exposes three routes on port 8080:
- GET  /ping        : AgentCore Runtime health check (returns {"status":"Healthy"}).
- POST /invocations : AgentCore HTTP data-plane stub. Voice loop runs on /ws.
- WebSocket /ws     : Pipecat voice pipeline. One pipeline per connection.

This single-app shape matches the AgentCore HTTP service contract verbatim, so
Phase 3 deploys without a transport refactor.
"""

from datetime import datetime, timezone

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from loguru import logger

from hera_agent.logging_setup import configure_logging
from hera_agent.pipeline import run_pipeline

configure_logging()

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
    """AgentCore HTTP data-plane stub + Sonic bidi probe."""
    import asyncio
    import json
    import uuid

    import boto3
    from aws_sdk_bedrock_runtime.client import BedrockRuntimeClient, Config
    from aws_sdk_bedrock_runtime.config import SigV4AuthScheme
    from aws_sdk_bedrock_runtime.models import (
        BidirectionalInputPayloadPart,
        InvokeModelWithBidirectionalStreamInputChunk,
        InvokeModelWithBidirectionalStreamOperationInput,
    )
    from smithy_aws_core.identity.static import StaticCredentialsResolver

    region = "ap-northeast-1"
    frozen = boto3.Session().get_credentials().get_frozen_credentials()

    cfg = Config(
        endpoint_uri=f"https://bedrock-runtime.{region}.amazonaws.com",
        region=region,
        aws_access_key_id=frozen.access_key,
        aws_secret_access_key=frozen.secret_key,
        aws_session_token=frozen.token,
        aws_credentials_identity_resolver=StaticCredentialsResolver(),
        auth_schemes={"aws.auth#sigv4": SigV4AuthScheme(service="bedrock")},
    )
    client = BedrockRuntimeClient(config=cfg)

    prompt_name = str(uuid.uuid4())
    content_name = str(uuid.uuid4())
    send_events = [
        {"event": {"sessionStart": {"inferenceConfiguration": {"maxTokens": 256, "topP": 0.9, "temperature": 0.7}}}},
        {"event": {"promptStart": {"promptName": prompt_name, "textOutputConfiguration": {"mediaType": "text/plain"}, "audioOutputConfiguration": {"mediaType": "audio/lpcm", "sampleRateHertz": 24000, "sampleSizeBits": 16, "channelCount": 1, "voiceId": "matthew", "encoding": "base64", "audioType": "SPEECH"}}}},
        {"event": {"contentStart": {"promptName": prompt_name, "contentName": content_name, "type": "TEXT", "interactive": True, "role": "USER", "textInputConfiguration": {"mediaType": "text/plain"}}}},
        {"event": {"textInput": {"promptName": prompt_name, "contentName": content_name, "content": "Hello."}}},
        {"event": {"contentEnd": {"promptName": prompt_name, "contentName": content_name}}},
    ]

    received = []
    try:
        stream = await client.invoke_model_with_bidirectional_stream(
            InvokeModelWithBidirectionalStreamOperationInput(model_id="amazon.nova-2-sonic-v1:0")
        )
        for ev in send_events:
            await stream.input_stream.send(
                InvokeModelWithBidirectionalStreamInputChunk(
                    value=BidirectionalInputPayloadPart(bytes_=json.dumps(ev).encode())
                )
            )
        logger.info(f"Probe: sent {len(send_events)} events, waiting 5s for replies...")

        async def read_some():
            async for event in stream.output_stream:
                received.append(str(event)[:300])
                if len(received) >= 5:
                    break

        try:
            await asyncio.wait_for(read_some(), timeout=5.0)
        except asyncio.TimeoutError:
            logger.warning(f"Probe: timeout after 5s, received {len(received)} events")
        await stream.input_stream.close()
    except Exception as e:
        logger.exception(f"Probe failed: {e}")
        return JSONResponse({"probe_error": str(e), "received": received}, status_code=500)

    logger.info(f"Probe: received {len(received)} events: {received[:2]}")
    return JSONResponse({
        "agent": "hera-pipecat-sonic",
        "status": "running",
        "probe_sent": len(send_events),
        "probe_received": len(received),
        "probe_samples": received,
    })


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
    except Exception:
        logger.exception("WS pipeline failed")
        raise


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
