"""Verify config module reads env vars with documented defaults."""

import importlib


def test_kb_id_defaults_to_prod(monkeypatch):
    """KB_ID falls back to the prod default (BKXE19AH89) when HERA_KB_ID is unset.

    Plan 03-05 baked the prod KB id in so AgentCore Runtime (no env injection)
    boots correctly. Local docker-compose env vars still override.
    """
    monkeypatch.delenv("HERA_KB_ID", raising=False)
    import hera_agent.config
    importlib.reload(hera_agent.config)
    assert hera_agent.config.KB_ID == "BKXE19AH89"


def test_kb_id_env_override(monkeypatch):
    """HERA_KB_ID env var overrides the baked-in prod default."""
    monkeypatch.setenv("HERA_KB_ID", "test-kb-id")
    import hera_agent.config
    importlib.reload(hera_agent.config)
    assert hera_agent.config.KB_ID == "test-kb-id"


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
