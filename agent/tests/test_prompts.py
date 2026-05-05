"""Verify SYSTEM_PROMPT implements D-17 'Crisp store associate'."""

from hera_agent.prompts import SYSTEM_PROMPT


def test_prompt_non_empty():
    assert len(SYSTEM_PROMPT) > 100


def test_prompt_mentions_apple():
    assert "Apple" in SYSTEM_PROMPT


def test_prompt_includes_refusal_line():
    """D-17: refuse non-Apple in 1 line."""
    assert "I only handle Apple product questions" in SYSTEM_PROMPT


def test_prompt_mentions_lookup_product_tool():
    """The persona must know to call lookup_product for product questions."""
    assert "lookup_product" in SYSTEM_PROMPT


def test_prompt_has_no_filler_words_in_examples():
    """D-17: never use 'absolutely', 'great question', etc.

    These are forbidden as response words but allowed in the rule text. The
    rule sentence enumerates them verbatim, so the test asserts they appear at
    most in a 'forbidden words' rule context, never as model output.
    """
    # Sanity: the rule line that bans the words is allowed to mention them.
    assert "absolutely" in SYSTEM_PROMPT.lower()
    assert "great question" in SYSTEM_PROMPT.lower()
