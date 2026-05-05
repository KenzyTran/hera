"""Verify config module reads env vars with documented defaults."""

import importlib

import pytest


def test_kb_id_required(monkeypatch):
    """KeyError raised when HERA_KB_ID is missing (fail-fast per AGENTS.md)."""
    monkeypatch.delenv("HERA_KB_ID", raising=False)
    # Force a reimport so the module-level os.environ["HERA_KB_ID"] runs again.
    import hera_agent.config
    with pytest.raises(KeyError, match="HERA_KB_ID"):
        importlib.reload(hera_agent.config)


def test_defaults_when_optional_missing(monkeypatch):
    """Optional vars use documented defaults when unset."""
    monkeypatch.setenv("HERA_KB_ID", "test-kb-id")
    monkeypatch.delenv("HERA_KB_SCORE_THRESHOLD", raising=False)
    monkeypatch.delenv("AWS_REGION", raising=False)
    monkeypatch.delenv("HERA_VOICE", raising=False)

    import hera_agent.config
    importlib.reload(hera_agent.config)

    assert hera_agent.config.KB_SCORE_THRESHOLD == 0.4
    assert hera_agent.config.AWS_REGION == "ap-northeast-1"
    assert hera_agent.config.HERA_VOICE == "matthew"
