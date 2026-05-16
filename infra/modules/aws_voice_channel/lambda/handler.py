"""Hera voice lookup Lambda.

Lex V2 fulfillment hook for FallbackIntent of bot hera-product-lookup-prod.
Reads caller transcript from event.inputTranscript, calls Bedrock KB
Retrieve cross-region against BKXE19AH89 in ap-northeast-1, formats a
one-sentence answer, and returns it via BOTH sessionAttributes.answer (so
Connect Play Prompt can read $.Lex.SessionAttributes.answer per D-69
addendum) AND messages[].content (Lex conversation log fidelity).
"""

import os

import boto3

KB_ID = os.environ["KB_ID"]
KB_REGION = os.environ["KB_REGION"]
NUM_RESULTS = int(os.environ.get("NUM_RESULTS", "3"))

_kb = boto3.client("bedrock-agent-runtime", region_name=KB_REGION)


def _retrieve(query: str) -> str:
    """Return top-1 KB document text, or empty string on no results."""
    resp = _kb.retrieve(
        knowledgeBaseId=KB_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={
            "vectorSearchConfiguration": {"numberOfResults": NUM_RESULTS}
        },
    )
    results = resp.get("retrievalResults", [])
    if not results:
        return ""
    return results[0]["content"]["text"]


def _format_answer(query: str, kb_text: str) -> str:
    """Answer combining KB content excerpt + stock status word.

    Catalog markdown uses 'Stock: In stock' / 'Stock: Out of stock'. We grep
    for the keywords case-insensitively; default to 'available' when the
    document is found but no stock keyword is present. The excerpt is the
    first sentence-like fragment of the KB chunk (stripped of markdown
    headers + bullet syntax) so callers hear product info, not just status.
    """
    lowered = kb_text.lower()
    if "in stock" in lowered:
        status = "in stock"
    elif "out of stock" in lowered:
        status = "out of stock"
    else:
        status = "available"

    cleaned = " ".join(
        line.lstrip("#-* \t")
        for line in kb_text.splitlines()
        if line.strip()
    )
    excerpt = cleaned[:240].rsplit(". ", 1)[0]
    if not excerpt.endswith("."):
        excerpt = excerpt + "."
    return f"{excerpt} It is {status}."


def lambda_handler(event, context):
    """Lex V2 fulfillment entrypoint."""
    transcript = event.get("inputTranscript", "").strip()

    if not transcript:
        answer = "Sorry, I could not hear you."
    else:
        kb_text = _retrieve(transcript)
        if kb_text:
            answer = _format_answer(transcript, kb_text)
        else:
            answer = f"Sorry, I do not have information about {transcript}."

    intent_name = event["sessionState"]["intent"]["name"]

    return {
        "sessionState": {
            "dialogAction": {"type": "Close"},
            "intent": {"name": intent_name, "state": "Fulfilled"},
            "sessionAttributes": {"answer": answer},
        },
        # W-3 / Pitfall 8: single-space placeholder content prevents audible
        # double-playback if Connect ever reads messages[] instead of the
        # session attribute. Lex response-shape validity preserved.
        "messages": [
            {"contentType": "PlainText", "content": " "},
        ],
    }
