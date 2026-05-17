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
from pathlib import PurePosixPath

import boto3

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


async def lookup_product_handler(params: FunctionCallParams) -> None:
    """Pipecat tool handler. Offloads sync boto3 to a thread (Pitfall F)."""
    result = await asyncio.to_thread(_kb_retrieve, params.arguments["query"])
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
