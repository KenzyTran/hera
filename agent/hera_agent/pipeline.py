"""Pipecat pipeline assembly for the Hera voice agent.

One PipelineTask per WebSocket connection (Pattern P1). The LLM is constructed
inside the pipeline builder so that each connection gets its own
AWSNovaSonicLLMService instance and its own bidi stream to Sonic.

Supports two transports:
- Browser (raw PCM via RawPCMSerializer on /ws)
- Twilio (mu-law 8kHz via TwilioFrameSerializer on /twilio)
"""

import boto3
from botocore.exceptions import NoCredentialsError

from fastapi import WebSocket

from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.frames.frames import LLMRunFrame
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.aggregators.llm_response_universal import (
    LLMContextAggregatorPair,
    LLMUserAggregatorParams,
)
from pipecat.serializers.twilio import TwilioFrameSerializer
from pipecat.services.aws.nova_sonic.llm import AWSNovaSonicLLMService
from pipecat.services.aws.nova_sonic.session_continuation import (
    SessionContinuationParams,
)
from pipecat.transports.websocket.fastapi import (
    FastAPIWebsocketParams,
    FastAPIWebsocketTransport,
)

from hera_agent.config import (
    AWS_REGION,
    HERA_VOICE,
    TWILIO_ACCOUNT_SID,
    TWILIO_AUTH_TOKEN,
)
from hera_agent.prompts import SYSTEM_PROMPT
from hera_agent.serializer import RawPCMSerializer
from hera_agent.tools import TOOLS, lookup_product_handler


def build_llm() -> AWSNovaSonicLLMService:
    """Construct AWSNovaSonicLLMService, bridging boto3 default chain to static creds.

    transition_threshold_seconds=360 rotates the bidi stream ~120s before the
    ~480s Sonic stream cap, satisfying AGT-05 transparently.

    Credential resolution: boto3 default chain (env vars -> ~/.aws -> IMDSv2).
    Resolved per-call so a long-running process picks up rotated IMDS creds.
    """
    from loguru import logger as _log

    session = boto3.Session()
    credentials = session.get_credentials()
    if credentials is None:
        raise NoCredentialsError()
    frozen = credentials.get_frozen_credentials()

    try:
        ident = session.client("sts", region_name=AWS_REGION).get_caller_identity()
        _log.info(
            f"Pipeline identity: account={ident['Account']} arn={ident['Arn']}"
        )
    except Exception as e:
        _log.exception(f"get_caller_identity failed: {e}")

    return AWSNovaSonicLLMService(
        access_key_id=frozen.access_key,
        secret_access_key=frozen.secret_key,
        session_token=frozen.token,
        region=AWS_REGION,
        settings=AWSNovaSonicLLMService.Settings(
            voice=HERA_VOICE,
            system_instruction=SYSTEM_PROMPT,
        ),
        session_continuation=SessionContinuationParams(
            transition_threshold_seconds=360,
        ),
    )


async def _build_and_run(transport) -> None:
    """Build and run a Pipecat pipeline with the given transport."""
    llm = build_llm()
    llm.register_function(
        "lookup_product",
        lookup_product_handler,
        cancel_on_interruption=False,
    )

    context = LLMContext(
        messages=[{"role": "user", "content": "Hello."}],
        tools=TOOLS,
    )
    user_agg, asst_agg = LLMContextAggregatorPair(
        context,
        user_params=LLMUserAggregatorParams(vad_analyzer=SileroVADAnalyzer()),
    )

    pipeline = Pipeline([
        transport.input(),
        user_agg,
        llm,
        transport.output(),
        asst_agg,
    ])

    task = PipelineTask(
        pipeline,
        params=PipelineParams(
            enable_metrics=True,
            enable_usage_metrics=True,
        ),
    )

    @transport.event_handler("on_client_connected")
    async def _on_connected(_t, _c) -> None:
        await task.queue_frames([LLMRunFrame()])

    @transport.event_handler("on_client_disconnected")
    async def _on_disconnected(_t, _c) -> None:
        await task.cancel()

    await PipelineRunner(handle_sigint=False).run(task)


async def run_pipeline(websocket: WebSocket) -> None:
    """Browser channel: raw 16 kHz Int16 LE PCM in / 24 kHz out."""
    transport = FastAPIWebsocketTransport(
        websocket=websocket,
        params=FastAPIWebsocketParams(
            audio_in_enabled=True,
            audio_out_enabled=True,
            add_wav_header=False,
            serializer=RawPCMSerializer(),
        ),
    )
    await _build_and_run(transport)


async def run_twilio_pipeline(
    websocket: WebSocket, stream_sid: str, call_sid: str
) -> None:
    """Twilio channel: mu-law 8 kHz from Twilio, resampled by TwilioFrameSerializer."""
    serializer = TwilioFrameSerializer(
        stream_sid=stream_sid,
        call_sid=call_sid,
        account_sid=TWILIO_ACCOUNT_SID,
        auth_token=TWILIO_AUTH_TOKEN,
    )
    transport = FastAPIWebsocketTransport(
        websocket=websocket,
        params=FastAPIWebsocketParams(
            audio_in_enabled=True,
            audio_out_enabled=True,
            add_wav_header=False,
            serializer=serializer,
        ),
    )
    await _build_and_run(transport)
