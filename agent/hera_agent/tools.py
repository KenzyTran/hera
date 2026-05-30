"""KB lookup tool for the Hera Pipecat agent.

Mirrors bin/verify-kb.sh semantics: numberOfResults=3, score threshold from env
(default 0.4), filters chunks below threshold, returns 'no relevant product info'
when no chunk survives. boto3 is sync; the async handler dispatches it via
asyncio.to_thread to avoid blocking the Pipecat event loop (Pitfall F).

No try/except around the boto3 call - per AGENTS.md, let exceptions propagate.
boto3 raises AccessDeniedException, ResourceNotFoundException, ThrottlingException
as native types; Pipecat logs them and returns a tool error frame to Sonic, which
gracefully tells the user there was a problem.
"""

import asyncio
import json
import os
from pathlib import PurePosixPath

import boto3
from opentelemetry import trace

from pipecat.adapters.schemas.function_schema import FunctionSchema
from pipecat.adapters.schemas.tools_schema import ToolsSchema
from pipecat.services.llm_service import FunctionCallParams

from hera_agent.config import AWS_REGION, KB_ID, KB_SCORE_THRESHOLD

_kb = boto3.client("bedrock-agent-runtime", region_name=AWS_REGION)


def _kb_retrieve(query: str) -> str:
    """Call Bedrock KB Retrieve and format the response.

    Returns the literal string 'no relevant product info' if no chunk has a
    score >= KB_SCORE_THRESHOLD. Otherwise joins surviving chunks with blank
    lines, each prefixed by 'Source: <basename of s3 uri>'.
    """
    resp = _kb.retrieve(
        knowledgeBaseId=KB_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": 3}},
    )
    chunks = [
        r for r in resp.get("retrievalResults", [])
        if r.get("score", 0) >= KB_SCORE_THRESHOLD
    ]
    if not chunks:
        return "no relevant product info"
    return "\n\n".join(
        f"Source: {PurePosixPath(r['location']['s3Location']['uri']).name}\n{r['content']['text']}"
        for r in chunks
    )


_LANGFUSE_ENABLED = bool(os.environ.get("LANGFUSE_SECRET_KEY"))

# Manual tool spans go through the GLOBAL OpenTelemetry tracer -- the same
# provider Pipecat's enable_tracing uses -- NOT the Langfuse SDK client. The
# Langfuse SDK keeps its own isolated TracerProvider, so spans created with it
# land in a SEPARATE trace from the Pipecat conversation/turn spans (that was
# the cause of the fragmented standalone "lookup_product" trace). Using the
# global tracer makes lookup_product / kb_retrieve nest under the active turn
# span -> one end-to-end waterfall. The Langfuse OTLP exporter is attached to
# this provider in tracing.init_tracing().
_tracer = trace.get_tracer("hera.tools")


def _lf_attrs(span, *, input=None, output=None, metadata=None, obs_type=None) -> None:
    """Set Langfuse-recognised OTel span attributes (input / output / metadata)."""
    if obs_type is not None:
        span.set_attribute("langfuse.observation.type", obs_type)
    if input is not None:
        span.set_attribute("langfuse.observation.input", json.dumps(input))
    if output is not None:
        span.set_attribute("langfuse.observation.output", json.dumps(output))
    for key, value in (metadata or {}).items():
        span.set_attribute(f"langfuse.observation.metadata.{key}", value)


async def lookup_product_handler(params: FunctionCallParams) -> None:
    """Pipecat tool handler. Offloads sync boto3 to a thread (Pitfall F)."""
    query = params.arguments["query"]

    if _LANGFUSE_ENABLED:
        # Outer span = the tool call as the agent sees it; nests under the turn.
        with _tracer.start_as_current_span("lookup_product") as outer:
            _lf_attrs(outer, obs_type="tool", input={"query": query},
                      metadata={"tool": "lookup_product"})
            # Inner span = the Bedrock KB Retrieve sub-call (S3 Vectors backend).
            with _tracer.start_as_current_span("kb_retrieve") as inner:
                _lf_attrs(inner, input={"query": query},
                          metadata={"kb_id": KB_ID, "threshold": KB_SCORE_THRESHOLD})
                result = await asyncio.to_thread(_kb_retrieve, query)
                chunk_count = (
                    0 if result == "no relevant product info"
                    else result.count("Source:")
                )
                _lf_attrs(inner, output={"chunks": chunk_count, "chars": len(result)})
            _lf_attrs(outer, output={"chunks": chunk_count})
    else:
        result = await asyncio.to_thread(_kb_retrieve, query)

    await params.result_callback({"product_info": result})


lookup_product_schema = FunctionSchema(
    name="lookup_product",
    description=(
        "Look up Apple product information (specs, pricing, stock) from the "
        "live store knowledge base. Call this whenever the user asks about a "
        "specific product, price, or availability. Pass the user's question "
        "verbatim or a short rewrite as the query."
    ),
    properties={
        "query": {
            "type": "string",
            "description": "The product question to look up. Free text, English.",
        },
    },
    required=["query"],
)

TOOLS = ToolsSchema(standard_tools=[lookup_product_schema])
