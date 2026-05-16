"""Environment configuration + Twilio webhook signature validation.

AWS_REGION + AGENTCORE_RUNTIME_ARN come from App Runner runtime_environment_variables
(Plan 06-01 IaC). TWILIO_AUTH_TOKEN comes from runtime_environment_secrets injecting
a Secrets Manager value (D-67) — operator paste-style (RUNBOOK Phase 6).

The X-Twilio-Signature validator is `twilio.request_validator.RequestValidator`
per Twilio docs (do NOT hand-roll HMAC — RESEARCH.md "Don't Hand-Roll").
"""

import os

from fastapi import WebSocket
from twilio.request_validator import RequestValidator

AWS_REGION: str = os.environ.get("AWS_REGION", "ap-northeast-1")
AGENTCORE_RUNTIME_ARN: str = os.environ["AGENTCORE_RUNTIME_ARN"]
TWILIO_AUTH_TOKEN: str = os.environ["TWILIO_AUTH_TOKEN"]

_VALIDATOR = RequestValidator(TWILIO_AUTH_TOKEN)


def validate_twilio_signature(websocket: WebSocket) -> None:
    """Verify X-Twilio-Signature on the WS upgrade. Raise on failure (D-67).

    Twilio's signature canonicalization sometimes differs from the URL
    FastAPI sees by exactly one trailing '/' character (Twilio docs explicit
    gotcha). Try BOTH forms before rejecting.
    """
    signature = websocket.headers.get("x-twilio-signature", "")
    url = str(websocket.url).replace("ws://", "https://").replace("wss://", "https://")
    if _VALIDATOR.validate(url, {}, signature):
        return
    if _VALIDATOR.validate(url + "/", {}, signature):
        return
    raise PermissionError("invalid X-Twilio-Signature")
