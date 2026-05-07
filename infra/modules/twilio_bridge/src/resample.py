"""mu-law 8kHz <-> Int16 16kHz two-way resample (TWIL-01, D-59).

audioop on Python 3.13 comes from the audioop-lts PyPI shim. API is verbatim
identical to the stdlib audioop removed in 3.13 per PEP 594.

`audioop.ratecv` keeps a small filter state in its second return value. The
state MUST be threaded across frames within a call to avoid filter
discontinuities at frame boundaries (RESEARCH.md Pitfall 4 — clicks at
20ms boundaries). The per-call coroutine in bridge.py owns the state dict;
each call to twilio_to_sonic / sonic_to_twilio passes the previous state in
and stores the new state for the next frame.
"""

import audioop


def twilio_to_sonic(mulaw_8k: bytes, state: object | None) -> tuple[bytes, object]:
    """mu-law 8kHz inbound from Twilio -> Int16 16kHz to AgentCore upstream.

    Returns (pcm16_16k_bytes, new_state). Caller threads new_state into the
    next call.
    """
    pcm16_8k = audioop.ulaw2lin(mulaw_8k, 2)
    pcm16_16k, new_state = audioop.ratecv(pcm16_8k, 2, 1, 8000, 16000, state)
    return pcm16_16k, new_state


def sonic_to_twilio(
    pcm16_in: bytes, in_rate: int, state: object | None
) -> tuple[bytes, object]:
    """Int16 in_rate inbound from AgentCore -> mu-law 8kHz to Twilio.

    in_rate is 16000 or 24000 — Plan 06-03 dial-in smoke probes the actual
    AgentCore data-plane WSS framing rate and adjusts the caller side
    (CONTEXT.md D-59 open caveat). Returns (mulaw_8k_bytes, new_state).
    """
    pcm16_8k, new_state = audioop.ratecv(pcm16_in, 2, 1, in_rate, 8000, state)
    mulaw_8k = audioop.lin2ulaw(pcm16_8k, 2)
    return mulaw_8k, new_state
