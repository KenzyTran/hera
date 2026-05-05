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

    // One-pole IIR LPF state. Cutoff ~7 kHz keeps the LPF below the 8 kHz
    // Nyquist limit of the 16 kHz target rate, so anything that could
    // alias is attenuated before decimation. Without this, energy in
    // 8-24 kHz folds back into voice band and degrades Sonic ASR.
    this._lpfState = 0;
    this._lpfCoeff = Math.exp(-2 * Math.PI * 7000 / sampleRate);
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || input.length === 0) return true;
    const channel = input[0]; // mono
    const ratio = sampleRate / this.targetRate;

    // Pass 1: anti-alias LPF over the whole quantum.
    const a = this._lpfCoeff;
    let y = this._lpfState;
    const filtered = new Float32Array(channel.length);
    for (let i = 0; i < channel.length; i++) {
      y = a * y + (1 - a) * channel[i];
      filtered[i] = y;
    }
    this._lpfState = y;

    // Pass 2: decimate to target rate. Math.round is symmetric for
    // negative samples (Math.floor biased one step low).
    const outLen = Math.floor(channel.length / ratio);
    const out = new Int16Array(outLen);
    for (let i = 0; i < outLen; i++) {
      const s = filtered[Math.floor(i * ratio)];
      out[i] = Math.max(-32768, Math.min(32767, Math.round(s * 32767)));
    }
    this.port.postMessage(out.buffer, [out.buffer]);
    return true;
  }
}

registerProcessor("capture-processor", CaptureProcessor);
