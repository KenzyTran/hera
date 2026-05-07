"""Offline SigV4 header construction coverage (BLOCKER-5 fix).

Patches botocore credentials with a fixture access key + secret. Asserts
`_signed_upstream_headers` returns the expected SigV4 headers + the
custom session-id header.
"""

import os

os.environ.setdefault("TWILIO_AUTH_TOKEN", "test")
os.environ.setdefault(
    "AGENTCORE_RUNTIME_ARN",
    "arn:aws:bedrock-agentcore:ap-northeast-1:000000000000:runtime/test",
)
os.environ.setdefault("AWS_REGION", "ap-northeast-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

from src.bridge import _signed_upstream_headers


def test_signed_upstream_headers_present() -> None:
    headers = _signed_upstream_headers("CA-test-call-sid")
    # Authorization (SigV4), X-Amz-Date, and the AgentCore session-id
    # header MUST be present.
    keys_lower = {k.lower() for k in headers.keys()}
    assert "authorization" in keys_lower
    assert "x-amz-date" in keys_lower
    assert "x-amzn-bedrock-agentcore-runtime-session-id" in keys_lower


def test_signed_upstream_headers_session_id_value() -> None:
    headers = _signed_upstream_headers("CA-fixture-12345")
    # Find the session-id header (case-insensitive); value MUST equal
    # exactly the call_sid we passed in.
    for k, v in headers.items():
        if k.lower() == "x-amzn-bedrock-agentcore-runtime-session-id":
            assert v == "CA-fixture-12345"
            return
    raise AssertionError("session-id header missing")


def test_signed_upstream_headers_authorization_credential_format() -> None:
    # Smoke: Authorization header includes the access key id + region +
    # service strings (SigV4 canonical Credential field).
    headers = _signed_upstream_headers("CA-x")
    auth = next(v for k, v in headers.items() if k.lower() == "authorization")
    assert "AKIAIOSFODNN7EXAMPLE" in auth
    assert "ap-northeast-1" in auth
    assert "bedrock-agentcore" in auth
