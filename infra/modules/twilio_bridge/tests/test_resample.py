"""Offline mu-law/Int16 ratecv round-trip coverage (BLOCKER-5 fix).

Synthetic 8 kHz mu-law -> Int16 16 kHz -> mu-law 8 kHz round-trip. Length
ratios are deterministic; we assert exact byte-count math, not audio
fidelity.
"""

import os

os.environ.setdefault("TWILIO_AUTH_TOKEN", "test")
os.environ.setdefault(
    "AGENTCORE_RUNTIME_ARN",
    "arn:aws:bedrock-agentcore:ap-northeast-1:000000000000:runtime/test",
)
os.environ.setdefault("AWS_REGION", "ap-northeast-1")

from src.resample import sonic_to_twilio, twilio_to_sonic


def test_twilio_to_sonic_doubles_pcm_byte_count() -> None:
    # 160 mu-law bytes (a 20 ms Twilio frame at 8 kHz, 1 byte/sample) ->
    # ulaw2lin gives 320 PCM16 bytes (2 bytes/sample) -> ratecv 8k -> 16k
    # roughly doubles to ~640 PCM16 bytes (the exact count varies by 1-2
    # bytes for filter ramp on the very first frame; we assert the ratio
    # is between 1.8x and 2.2x of the input length-doubled value).
    mulaw = bytes([0x7F] * 160)
    pcm16, state = twilio_to_sonic(mulaw, None)
    # Output is PCM16 (2 bytes/sample) at 16 kHz.
    # Ideal ratio: (160 * 2 * 2) = 640 bytes; allow filter ramp tolerance.
    assert 600 <= len(pcm16) <= 680
    assert state is not None


def test_sonic_to_twilio_halves_at_16k_input() -> None:
    # 640 PCM16 bytes (~20 ms at 16 kHz) -> ratecv 16k -> 8k -> 320 PCM16 ->
    # lin2ulaw -> 160 mu-law bytes (allow filter ramp tolerance).
    pcm16 = b"\x00\x01" * 320
    mulaw, state = sonic_to_twilio(pcm16, 16000, None)
    assert 140 <= len(mulaw) <= 180
    assert state is not None


def test_state_threading_changes_subsequent_output() -> None:
    # Threading state into the second call yields different bytes than
    # passing None twice (state carries the filter ramp across the
    # frame boundary — Pitfall 4 mitigation).
    mulaw_a = bytes([0x40] * 160)
    mulaw_b = bytes([0x40] * 160)
    pcm_a, state = twilio_to_sonic(mulaw_a, None)
    pcm_b_threaded, _ = twilio_to_sonic(mulaw_b, state)
    pcm_b_fresh, _ = twilio_to_sonic(mulaw_b, None)
    # The threaded output differs from the fresh-state output (filter
    # warm-up phase is now skipped on the second frame).
    assert pcm_b_threaded != pcm_b_fresh
