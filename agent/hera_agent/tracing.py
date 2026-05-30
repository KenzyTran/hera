"""OpenTelemetry tracing setup — wires Pipecat's OTEL pipeline into Langfuse.

Pipecat 1.2 emits conversation/turn/service spans natively when
PipelineTask(enable_tracing=True). Langfuse v3 ingests OTLP traces at
/api/public/otel/v1/traces. We install one OTLP HTTP exporter on the global
TracerProvider BEFORE Langfuse SDK initializes; both Pipecat and any manual
Langfuse spans (e.g. lookup_product in tools.py) share the same trace.

No-op when LANGFUSE_SECRET_KEY is unset. Idempotent.
"""

import base64
import os

from loguru import logger

_INITIALIZED = False
_ENABLED = False
_PROVIDER = None


def init_tracing() -> bool:
    """Set up Pipecat OTEL tracing with Langfuse as the OTLP destination.

    Reads LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST from env.
    Must be called once at process boot before instantiating Langfuse().
    """
    global _INITIALIZED, _ENABLED, _PROVIDER
    if _INITIALIZED:
        return _ENABLED
    _INITIALIZED = True

    if not os.environ.get("LANGFUSE_SECRET_KEY"):
        logger.info("Tracing disabled (LANGFUSE_SECRET_KEY not set)")
        return False

    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import SimpleSpanProcessor
    from pipecat.utils.tracing.setup import setup_tracing

    pk = os.environ["LANGFUSE_PUBLIC_KEY"]
    sk = os.environ["LANGFUSE_SECRET_KEY"]
    host = os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com").rstrip("/")

    auth = base64.b64encode(f"{pk}:{sk}".encode()).decode()
    exporter = OTLPSpanExporter(
        endpoint=f"{host}/api/public/otel/v1/traces",
        headers={"Authorization": f"Basic {auth}"},
    )

    # Ensure a real SDK TracerProvider owns the global slot -- Pipecat's
    # enable_tracing emits into the global provider. If AgentCore's ADOT layer
    # already installed one, keep it (our spans then fan out to CloudWatch too);
    # otherwise let Pipecat's setup_tracing install one (it also wires Pipecat's
    # own tracing). setup_tracing uses a BatchSpanProcessor internally, which we
    # deliberately do NOT rely on for export (see below) -- we pass no exporter.
    provider = trace.get_tracer_provider()
    if not isinstance(provider, TracerProvider):
        setup_tracing("hera-agent")
        provider = trace.get_tracer_provider()

    if not isinstance(provider, TracerProvider):
        logger.warning("Tracing disabled: no SDK TracerProvider available")
        return False

    # SimpleSpanProcessor exports each span synchronously the instant it ends.
    # BatchSpanProcessor (setup_tracing's default) batches and ships on a 5s
    # timer / on shutdown -- but AgentCore freezes the microVM the moment the WS
    # closes, so batched spans only reach Langfuse when the VM next wakes (the
    # "previous session's trace appears only after a redeploy" symptom). Synchronous
    # export ships every span while the VM is still running the session.
    provider.add_span_processor(SimpleSpanProcessor(exporter))
    _PROVIDER = provider
    _ENABLED = True
    logger.info(
        f"Tracing enabled: Pipecat OTEL -> Langfuse ({host}) "
        f"provider={type(provider).__name__} processor=SimpleSpanProcessor"
    )
    return _ENABLED


def is_enabled() -> bool:
    """Whether OTEL tracing was successfully initialized."""
    return _ENABLED


def flush() -> None:
    """Force-flush pending spans to Langfuse.

    Call at session end. AgentCore Runtime is a microVM that gets frozen /
    reaped shortly after a session goes idle, so the BatchSpanProcessor's
    timed export may never fire and queued spans are lost. force_flush() on
    the active TracerProvider (which holds the Langfuse OTLP exporter attached
    in init_tracing) drains the queue synchronously before the VM suspends.
    """
    if not _ENABLED or _PROVIDER is None:
        return
    if hasattr(_PROVIDER, "force_flush"):
        ok = _PROVIDER.force_flush()
        logger.info(f"Tracing flush: force_flush returned {ok}")
