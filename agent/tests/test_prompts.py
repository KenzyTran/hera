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


def test_filler_words_absent_from_example_responses():
    """D-17: 'You:' example replies must not contain banned filler.

    The rule line that bans these words is allowed to mention them. The
    actual enforcement target is the example-response block: parse out the
    'You:' lines and assert no banned filler appears there.
    """
    banned = ("absolutely", "great question", "let me think")
    you_lines = [
        line for line in SYSTEM_PROMPT.splitlines()
        if line.strip().lower().startswith("you:")
    ]
    assert you_lines, "expected at least one 'You:' example line in prompt"
    for line in you_lines:
        lowered = line.lower()
        for word in banned:
            assert word not in lowered, (
                f"banned filler {word!r} found in example: {line!r}"
            )
