"""Widget presigner Lambda handler.

The browser cannot SigV4-sign a WebSocket directly. This Lambda mints a
short-lived (TTL <= 5 min) SigV4-presigned WSS URL pointing at the AgentCore
Runtime data-plane endpoint. The widget fetches the URL via Function URL
(anonymous public, throttled by Lambda reserved concurrency = 5), then opens
the returned wss:// URL.

Wire format the widget receives:
    {"url": "wss://bedrock-agentcore.<region>.amazonaws.com/runtimes/<URL-ENCODED-ARN>/ws?qualifier=DEFAULT&X-Amz-Algorithm=...&X-Amz-Signature=..."}

Env vars (from Terraform):
- AGENTCORE_RUNTIME_ARN  -- the runtime ARN to invoke
- AWS_REGION             -- Lambda runtime injects this; we trust it
- CORS_ALLOW_ORIGIN      -- the single CloudFront origin
- PRESIGN_TTL_SECONDS    -- TTL on the presigned URL

boto3 ships with the python3.12 Lambda runtime so no deps are packaged.
"""

import json
import os
from urllib.parse import quote

from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest
from botocore.session import Session

REGION = os.environ["AWS_REGION"]
RUNTIME_ARN = os.environ["AGENTCORE_RUNTIME_ARN"]
CORS_ALLOW_ORIGIN = os.environ["CORS_ALLOW_ORIGIN"]
PRESIGN_TTL_SECONDS = int(os.environ["PRESIGN_TTL_SECONDS"])

SERVICE = "bedrock-agentcore"
HOST = f"bedrock-agentcore.{REGION}.amazonaws.com"

# AgentCore data-plane URL: the runtime ARN is URL-encoded into the path.
# `quote(arn, safe="")` percent-encodes EVERYTHING (including `:` and `/`).
ENCODED_ARN = quote(RUNTIME_ARN, safe="")
WSS_PATH = f"/runtimes/{ENCODED_ARN}/ws"
WSS_URL_BASE = f"wss://{HOST}{WSS_PATH}?qualifier=DEFAULT"
HTTPS_URL_BASE = f"https://{HOST}{WSS_PATH}?qualifier=DEFAULT"

_session = Session()


def _cors_headers() -> dict:
    return {
        "Access-Control-Allow-Origin": CORS_ALLOW_ORIGIN,
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Max-Age": "300",
        "Cache-Control": "no-store",
        "Content-Type": "application/json",
    }


def _presign_wss_url() -> str:
    """Compute a SigV4-presigned URL for the AgentCore /ws GET (upgrade).

    SigV4 signs the HTTPS form (the host is the same; only the scheme differs).
    After signing we swap https:// -> wss:// for the browser. AWS accepts both
    schemes for the data-plane WebSocket upgrade.
    """
    creds = _session.get_credentials().get_frozen_credentials()
    request = AWSRequest(method="GET", url=HTTPS_URL_BASE)
    signer = SigV4QueryAuth(creds, SERVICE, REGION, expires=PRESIGN_TTL_SECONDS)
    signer.add_auth(request)
    signed_https = request.url
    return "wss://" + signed_https[len("https://"):]


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if method == "OPTIONS":
        return {
            "statusCode": 204,
            "headers": _cors_headers(),
            "body": "",
        }

    if method != "GET":
        return {
            "statusCode": 405,
            "headers": _cors_headers(),
            "body": json.dumps({"error": "method not allowed"}),
        }

    url = _presign_wss_url()
    return {
        "statusCode": 200,
        "headers": _cors_headers(),
        "body": json.dumps({"url": url}),
    }
