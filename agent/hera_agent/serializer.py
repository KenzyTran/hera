"""Raw PCM frame serializer for the Hera Pipecat WebSocket transport.

The browser frontend (Plan 02-02) and headless probe send raw 16 kHz mono Int16
LE PCM as binary WS frames. Pipecat 1.1.0's FastAPIWebsocketTransport requires
a `serializer` to be set; if it is None, both `_receive_messages` and
`_write_frame` silently discard every frame so no audio crosses the boundary.

This serializer converts:
  - inbound binary WS frame bytes -> InputAudioRawFrame at the pipeline rate
  - outbound OutputAudioRawFrame.audio bytes -> raw binary WS frame

Text/control frames are not used; the contract is binary-audio only. This
matches the Pipecat add_wav_header=False contract and the Pattern 6/7 wire
format (16 kHz in / 24 kHz out, raw Int16 LE).
"""

from pipecat.frames.frames import (
    Frame,
    InputAudioRawFrame,
    OutputAudioRawFrame,
    StartFrame,
)
from pipecat.serializers.base_serializer import FrameSerializer


class RawPCMSerializer(FrameSerializer):
    """Pass-through serializer for raw Int16 LE PCM audio frames."""

    def __init__(self) -> None:
        super().__init__()
        self._input_sample_rate = 16000
        self._output_sample_rate = 24000

    async def setup(self, frame: StartFrame) -> None:
        """Capture pipeline-configured sample rates from the StartFrame."""
        self._input_sample_rate = frame.audio_in_sample_rate
        self._output_sample_rate = frame.audio_out_sample_rate

    async def serialize(self, frame: Frame) -> bytes | None:
        """Convert outbound OutputAudioRawFrame to raw bytes; ignore others."""
        if isinstance(frame, OutputAudioRawFrame):
            return frame.audio
        return None

    async def deserialize(self, data: str | bytes) -> Frame | None:
        """Convert inbound binary WS frame bytes to InputAudioRawFrame."""
        if isinstance(data, (bytes, bytearray)):
            return InputAudioRawFrame(
                audio=bytes(data),
                sample_rate=self._input_sample_rate,
                num_channels=1,
            )
        return None
