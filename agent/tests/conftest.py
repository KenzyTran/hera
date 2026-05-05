"""Shared pytest fixtures for the hera_agent test suite.

KB_ID is read at module import time, so we set it via env BEFORE pytest collects
any test that imports hera_agent. This is the recommended pattern for testing
modules that fail-fast on missing required env vars (per AGENTS.md).
"""

import os
from unittest.mock import MagicMock

import pytest

# Set required env vars before any hera_agent.* import. pytest collects fixtures
# before test modules, so anything imported from hera_agent in a test file is
# evaluated AFTER this runs. Use os.environ.setdefault so a real env value wins
# (allows running tests against a dev KB if desired).
os.environ.setdefault("HERA_KB_ID", "test-kb-id")
os.environ.setdefault("HERA_KB_SCORE_THRESHOLD", "0.4")
os.environ.setdefault("AWS_REGION", "ap-northeast-1")


@pytest.fixture
def sample_retrieve_response_high_score():
    """Three results, all above the default 0.4 threshold."""
    return {
        "retrievalResults": [
            {
                "score": 0.86,
                "content": {"text": "iPhone 13 Pro Max 256GB Sierra Blue. Stock: 12 units."},
                "location": {"s3Location": {"uri": "s3://hera-kb-source-prod/catalog/iphone-13-pro-max.md"}},
            },
            {
                "score": 0.62,
                "content": {"text": "iPhone 13 Pro Max 1TB Graphite. Stock: 4 units."},
                "location": {"s3Location": {"uri": "s3://hera-kb-source-prod/catalog/iphone-13-pro-max.md"}},
            },
            {
                "score": 0.45,
                "content": {"text": "Apple Watch Series 11 GPS 45mm. Stock: 8 units."},
                "location": {"s3Location": {"uri": "s3://hera-kb-source-prod/catalog/apple-watch-series-11.md"}},
            },
        ]
    }


@pytest.fixture
def sample_retrieve_response_below_threshold():
    """All results below the 0.4 threshold (will be filtered out)."""
    return {
        "retrievalResults": [
            {
                "score": 0.3,
                "content": {"text": "Some weakly-matched chunk."},
                "location": {"s3Location": {"uri": "s3://hera-kb-source-prod/catalog/random.md"}},
            },
        ]
    }


@pytest.fixture
def sample_retrieve_response_empty():
    """KB returned no results at all."""
    return {"retrievalResults": []}


@pytest.fixture
def mock_kb_client(monkeypatch):
    """Replace tools._kb with a MagicMock; yields the mock for response wiring."""
    from hera_agent import tools

    fake = MagicMock()
    monkeypatch.setattr(tools, "_kb", fake)
    return fake
