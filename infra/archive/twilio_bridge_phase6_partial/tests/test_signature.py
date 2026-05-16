"""Offline X-Twilio-Signature validator coverage (BLOCKER-5 fix).

Tests `validate_twilio_signature` with a known-good HMAC computed inline
from a fixed auth token + URL, plus tampered + missing variants. No network,
no Twilio account.
"""

import base64
import hashlib
import hmac
import os
from unittest.mock import MagicMock

import pytest

os.environ.setdefault("TWILIO_AUTH_TOKEN", "fixture-token")
os.environ.setdefault(
    "AGENTCORE_RUNTIME_ARN",
    "arn:aws:bedrock-agentcore:ap-northeast-1:000000000000:runtime/test",
)
os.environ.setdefault("AWS_REGION", "ap-northeast-1")

from src.config import validate_twilio_signature

# Read the actual token in use — the validator was initialised at module
# import time (src.config._VALIDATOR), so the HMAC fixture must agree with
# whatever value `os.environ` carried at that point. Other tests in the
# suite set TWILIO_AUTH_TOKEN before this module is imported (collection
# order is filesystem-sorted: test_ping.py, test_resample.py, test_signature.py,
# test_upstream.py), so we read it here rather than hardcode "fixture-token".
AUTH_TOKEN = os.environ["TWILIO_AUTH_TOKEN"]
URL = "https://abc123.ap-northeast-1.awsapprunner.com/twilio"


def _twilio_sig(url: str, params: dict, token: str) -> str:
    # Twilio HMAC convention: URL + sorted (key||value) concatenated, HMAC-SHA1, base64.
    s = url + "".join(k + params[k] for k in sorted(params))
    digest = hmac.new(token.encode("utf-8"), s.encode("utf-8"), hashlib.sha1).digest()
    return base64.b64encode(digest).decode("ascii")


def _make_ws(url: str, signature: str) -> MagicMock:
    ws = MagicMock()
    ws.url = url
    ws.headers = {"x-twilio-signature": signature}
    return ws


def test_valid_signature_passes() -> None:
    sig = _twilio_sig(URL, {}, AUTH_TOKEN)
    ws = _make_ws(URL, sig)
    # Returns None on success (no raise).
    validate_twilio_signature(ws)


def test_tampered_url_rejects() -> None:
    # Compute signature for original URL, present a different URL.
    sig = _twilio_sig(URL, {}, AUTH_TOKEN)
    ws = _make_ws(URL.replace("/twilio", "/twiliox"), sig)
    with pytest.raises(PermissionError):
        validate_twilio_signature(ws)


def test_missing_signature_rejects() -> None:
    ws = MagicMock()
    ws.url = URL
    ws.headers = {}
    with pytest.raises(PermissionError):
        validate_twilio_signature(ws)
