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
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    pk = os.environ["LANGFUSE_PUBLIC_KEY"]
    sk = os.environ["LANGFUSE_SECRET_KEY"]
    host = os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com").rstrip("/")

    auth = base64.b64encode(f"{pk}:{sk}".encode()).decode()
    exporter = OTLPSpanExporter(
        endpoint=f"{host}/api/public/otel/v1/traces",
        headers={"Authorization": f"Basic {auth}"},
    )

    # The Langfuse exporter MUST land on the SAME global TracerProvider that
    # Pipecat's enable_tracing uses, regardless of init ordering. On AgentCore
    # the ADOT layer may install the global SDK provider before OR after this
    # runs. The old setup_tracing() fallback created a SEPARATE provider that
    # lost the global slot when ADOT initialized later, so Pipecat spans never
    # reached Langfuse (flaky, ordering-dependent). Here: attach to the existing
    # SDK provider if there is one; otherwise install one now and win the global
    # slot at import time. Either way Pipecat + our spans share this provider.
    provider = trace.get_tracer_provider()
    if not isinstance(provider, TracerProvider):
        provider = TracerProvider()
        trace.set_tracer_provider(provider)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    _PROVIDER = provider
    _ENABLED = True
    logger.info(
        f"Tracing enabled: Pipecat OTEL -> Langfuse ({host}) "
        f"provider={type(provider).__name__}"
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
