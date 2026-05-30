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


def init_tracing() -> bool:
    """Set up Pipecat OTEL tracing with Langfuse as the OTLP destination.

    Reads LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST from env.
    Must be called once at process boot before instantiating Langfuse().
    """
    global _INITIALIZED, _ENABLED
    if _INITIALIZED:
        return _ENABLED
    _INITIALIZED = True

    if not os.environ.get("LANGFUSE_SECRET_KEY"):
        logger.info("Tracing disabled (LANGFUSE_SECRET_KEY not set)")
        return False

    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from pipecat.utils.tracing.setup import setup_tracing

    pk = os.environ["LANGFUSE_PUBLIC_KEY"]
    sk = os.environ["LANGFUSE_SECRET_KEY"]
    host = os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com").rstrip("/")

    auth = base64.b64encode(f"{pk}:{sk}".encode()).decode()
    exporter = OTLPSpanExporter(
        endpoint=f"{host}/api/public/otel/v1/traces",
        headers={"Authorization": f"Basic {auth}"},
    )

    # On AgentCore Runtime the platform's ADOT layer already owns the global
    # TracerProvider (spans export to CloudWatch). OTel forbids overriding it,
    # so setup_tracing's set_tracer_provider() is a silent no-op there and the
    # Langfuse exporter never attaches. When a real SDK provider already exists,
    # add our exporter as an extra span processor so spans fan out to BOTH
    # CloudWatch and Langfuse. Fall back to setup_tracing locally (docker
    # compose), where no provider is installed yet.
    provider = trace.get_tracer_provider()
    if isinstance(provider, TracerProvider):
        provider.add_span_processor(BatchSpanProcessor(exporter))
        _ENABLED = True
    else:
        _ENABLED = setup_tracing("hera-agent", exporter=exporter)

    if _ENABLED:
        logger.info(f"Tracing enabled: Pipecat OTEL -> Langfuse ({host})")
    else:
        logger.warning("Pipecat setup_tracing returned False")
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
    if not _ENABLED:
        return
    from opentelemetry import trace

    provider = trace.get_tracer_provider()
    if hasattr(provider, "force_flush"):
        provider.force_flush()
