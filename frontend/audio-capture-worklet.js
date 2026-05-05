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
    // Running fractional read cursor carried across process() quanta. At
    // non-integer ratios (e.g. 44.1 kHz native -> 16 kHz, ratio ~= 2.756)
    // restarting at 0 each quantum drops the leftover fraction and slowly
    // drifts. Carrying _cursor preserves exact spacing between output
    // samples regardless of native rate.
    this._cursor = 0;
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

    // Pass 2: decimate to target rate using a running cursor so the
    // fractional remainder carries into the next quantum (no drift on
    // non-integer ratios). Math.round is symmetric for negative samples
    // (Math.floor biased one step low).
    const outSamples = [];
    while (this._cursor < channel.length) {
      const s = filtered[Math.floor(this._cursor)];
      outSamples.push(Math.max(-32768, Math.min(32767, Math.round(s * 32767))));
      this._cursor += ratio;
    }
    this._cursor -= channel.length; // carry fractional leftover into next quantum

    const out = new Int16Array(outSamples);
    this.port.postMessage(out.buffer, [out.buffer]);
    return true;
  }
}

registerProcessor("capture-processor", CaptureProcessor);
