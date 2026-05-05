// Hera Phase 2 - AudioWorklet that downsamples browser native rate (typically
// 48 kHz Float32) to 16 kHz Int16 mono PCM. The result is posted as an
// ArrayBuffer of Int16 samples that app.js sends as binary WS frames.
//
// Pitfall D: without this downsampling, Sonic receives audio at the wrong rate
// and returns empty or chipmunk-pitch transcripts.

class CaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.targetRate = 16000;
    // sampleRate is a global in worklet scope - the AudioContext's actual rate.
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || input.length === 0) return true;
    const channel = input[0]; // mono
    const ratio = sampleRate / this.targetRate;
    const outLen = Math.floor(channel.length / ratio);
    const out = new Int16Array(outLen);
    for (let i = 0; i < outLen; i++) {
      const s = channel[Math.floor(i * ratio)];
      out[i] = Math.max(-32768, Math.min(32767, Math.floor(s * 32767)));
    }
    this.port.postMessage(out.buffer, [out.buffer]);
    return true;
  }
}

registerProcessor("capture-processor", CaptureProcessor);
