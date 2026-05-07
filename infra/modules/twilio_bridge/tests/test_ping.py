"""Smoke test: the FastAPI app boots and /ping returns the expected envelope.

No live AWS work. Sets dummy env vars before importing src.main so the
config.py module-import-time os.environ lookups succeed.
"""

import os

os.environ.setdefault("TWILIO_AUTH_TOKEN", "test-token")
os.environ.setdefault(
    "AGENTCORE_RUNTIME_ARN",
    "arn:aws:bedrock-agentcore:ap-northeast-1:000000000000:runtime/test",
)
os.environ.setdefault("AWS_REGION", "ap-northeast-1")

from fastapi.testclient import TestClient

from src.main import app

client = TestClient(app)


def test_ping_returns_healthy() -> None:
    resp = client.get("/ping")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "Healthy"
    assert isinstance(body["time_of_last_update"], int)
