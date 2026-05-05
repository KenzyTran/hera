"""Verify _kb_retrieve formats responses per D-18 contract."""

from hera_agent.tools import _kb_retrieve


def test_above_threshold_formats_chunks(mock_kb_client, sample_retrieve_response_high_score):
    """Three chunks above threshold are joined with double newlines, basename prefix."""
    mock_kb_client.retrieve.return_value = sample_retrieve_response_high_score

    result = _kb_retrieve("iPhone 13 Pro Max")

    # Top-1 first per D-18
    assert result.startswith("Source: iphone-13-pro-max.md\n")
    # Three chunks, two separators
    assert result.count("\n\n") == 2
    # All three sources present
    assert "Source: iphone-13-pro-max.md" in result
    assert "Source: apple-watch-series-11.md" in result
    # Stock numbers preserved verbatim
    assert "12 units" in result


def test_below_threshold_returns_sentinel(mock_kb_client, sample_retrieve_response_below_threshold):
    """All chunks below threshold yield the literal 'no relevant product info'."""
    mock_kb_client.retrieve.return_value = sample_retrieve_response_below_threshold

    result = _kb_retrieve("nonsense query")

    assert result == "no relevant product info"


def test_empty_results_returns_sentinel(mock_kb_client, sample_retrieve_response_empty):
    """Empty retrievalResults also yields the sentinel."""
    mock_kb_client.retrieve.return_value = sample_retrieve_response_empty

    result = _kb_retrieve("nothing matches")

    assert result == "no relevant product info"


def test_retrieve_called_with_correct_args(mock_kb_client, sample_retrieve_response_high_score):
    """boto3 retrieve receives the verify-kb.sh-compatible call shape (D-18)."""
    mock_kb_client.retrieve.return_value = sample_retrieve_response_high_score

    _kb_retrieve("MacBook Pro")

    mock_kb_client.retrieve.assert_called_once()
    call_kwargs = mock_kb_client.retrieve.call_args.kwargs
    assert call_kwargs["retrievalQuery"] == {"text": "MacBook Pro"}
    assert call_kwargs["retrievalConfiguration"] == {
        "vectorSearchConfiguration": {"numberOfResults": 3}
    }
    # knowledgeBaseId comes from env (conftest sets it to test-kb-id)
    assert call_kwargs["knowledgeBaseId"] == "test-kb-id"
