"""Pipecat pipeline assembly for the Hera voice agent.

One PipelineTask per WebSocket connection (Pattern P1). The LLM is constructed
inside run_pipeline so that each connection gets its own AWSNovaSonicLLMService
instance and its own bidi stream to Sonic.

CRITICAL: AWSNovaSonicLLMService uses StaticCredentialsResolver internally. It
does NOT follow the boto3 default credential chain - access_key_id and
secret_access_key MUST be passed explicitly from os.environ (Pitfall B).
"""

import os

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
from hera_agent.tools import TOOLS, lookup_product_handler


def build_llm() -> AWSNovaSonicLLMService:
    """Construct AWSNovaSonicLLMService with explicit static credentials.

    transition_threshold_seconds=360 rotates the bidi stream ~120s before the
    ~480s Sonic stream cap, satisfying AGT-05 transparently.
    """
    return AWSNovaSonicLLMService(
        access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        session_token=os.getenv("AWS_SESSION_TOKEN"),
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

    context = LLMContext(tools=TOOLS)
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
        context.add_message({"role": "developer", "content": "Greet the user briefly."})
        await task.queue_frames([LLMRunFrame()])

    @transport.event_handler("on_client_disconnected")
    async def _on_disconnected(_t, _c) -> None:
        await task.cancel()

    await PipelineRunner(handle_sigint=False).run(task)
