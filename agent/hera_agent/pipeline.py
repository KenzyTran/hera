"""Pipecat pipeline assembly for the Hera voice agent.

One PipelineTask per WebSocket connection (Pattern P1). The LLM is constructed
inside run_pipeline so that each connection gets its own AWSNovaSonicLLMService
instance and its own bidi stream to Sonic.

CRITICAL: AWSNovaSonicLLMService uses StaticCredentialsResolver internally. It
does NOT follow the boto3 default credential chain (Pitfall B). However, we DO
follow the boto3 default chain ourselves (env -> ~/.aws -> IMDSv2) and pass
the resolved credentials in as static kwargs. This makes the same code work in
both local docker-compose (env vars) and AgentCore Runtime (IMDSv2).
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
from pipecat.services.aws.nova_sonic.llm import AWSNovaSonicLLMService
from pipecat.services.aws.nova_sonic.session_continuation import (
    SessionContinuationParams,
)
from pipecat.transports.websocket.fastapi import (
    FastAPIWebsocketParams,
    FastAPIWebsocketTransport,
)

from hera_agent.config import AWS_REGION, HERA_VOICE
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
    session = boto3.Session()
    credentials = session.get_credentials()
    if credentials is None:
        raise NoCredentialsError()
    frozen = credentials.get_frozen_credentials()

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


async def run_pipeline(websocket: WebSocket) -> None:
    """Build and run a Pipecat pipeline for one WebSocket connection.

    AudioConfig defaults already satisfy AGT-07: 16 kHz mono Int16 input,
    24 kHz mono Int16 output. No explicit override needed.
    """
    transport = FastAPIWebsocketTransport(
        websocket=websocket,
        params=FastAPIWebsocketParams(
            audio_in_enabled=True,
            audio_out_enabled=True,
            add_wav_header=False,
            # Pipecat 1.1.0's FastAPIWebsocketTransport silently drops every
            # frame in both directions when serializer is None. Plan 02-02's
            # wire contract is raw 16 kHz Int16 LE PCM in / raw 24 kHz Int16
            # LE PCM out (Pattern 6 + Pattern 7), so we wire a pass-through
            # serializer that maps WS bytes <-> {Input,Output}AudioRawFrame.
            serializer=RawPCMSerializer(),
        ),
    )

    llm = build_llm()
    # cancel_on_interruption=False so barge-in does not waste an in-flight KB
    # call (Pitfall H). The KB call is cheap but the round-trip is ~400ms;
    # canceling and re-firing on every barge-in adds up.
    llm.register_function(
        "lookup_product",
        lookup_product_handler,
        cancel_on_interruption=False,
    )

    # Seed the context with a user-role kickoff message BEFORE the pipeline
    # starts. AWSNovaSonicLLMService._finish_connecting_if_context_available
    # only triggers an assistant response when the context already ends in a
    # user-role message at session-setup time (sent as interactive=True);
    # adding it from on_client_connected races with Sonic's connection setup
    # and the greeting never fires. Plan 02-02 AGT-04 latency probe revealed
    # this race.
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
        # Context already has a kickoff user message (seeded at construction).
        # LLMRunFrame triggers Sonic to consume the queued context and respond.
        await task.queue_frames([LLMRunFrame()])

    @transport.event_handler("on_client_disconnected")
    async def _on_disconnected(_t, _c) -> None:
        await task.cancel()

    await PipelineRunner(handle_sigint=False).run(task)
