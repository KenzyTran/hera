---
title: "3.4 Web Widget"
date: 2025-01-01
weight: 4
---

## Goal of this section

Deploy the HTML/JS widget to S3+CloudFront, open the HTTPS URL in your browser, click record, allow microphone access, and talk to the AgentCore Runtime you deployed in Section 3.3. Each learner gets a unique CloudFront URL because widget hosting lives in the learner's own Terraform state (Step 1 of Section 3.3).

## Widget structure (frontend/)

```
frontend/
├── index.html               # record button + status pill + transcript area
├── app.js                   # 5-state machine + resolveWsUrl + heartbeat
├── styles.css               # Apple Store light: .btn-{idle,connecting,listening,speaking,error}
└── audio-capture-worklet.js # AudioWorklet: 48kHz mic -> anti-alias LPF -> 16kHz Int16
```

*Source: frontend/ — Phase 3 Plan 03-02*

Minimal, no framework — a small single-folder layout that hosts on S3+CloudFront or GitHub Pages (WID-01). The default region for any AWS API call is still `ap-northeast-1`; CloudFront edges are global automatically.

## Why a presigner Lambda is needed (D-25 Rule-4)

The problem: a browser CANNOT SigV4-sign a WebSocket upgrade directly — the Web `WebSocket` API does not expose Authorization-header configuration. But the AgentCore Runtime `wss://...` data-plane endpoint REQUIRES SigV4 auth.

The solution: a Lambda Function URL (presigner) running inside AWS, using its IAM exec-role credentials, mints SigV4-presigned WSS URLs with a TTL of 300s and returns `{"url": "wss://..."}` when the browser fetches it. Flow:

1. Browser loads the widget from CloudFront → user clicks Record.
2. Widget fetches the presigner Function URL (`https://<id>.lambda-url.ap-northeast-1.on.aws/`).
3. Presigner returns `{"url": "wss://..."}` (SigV4-presigned, expires in 300s).
4. Widget opens `WebSocket(wss://...)` — the handshake authenticates via the presigned query string.

This is the Plan 03-04 Rule-4 architectural deviation — it bridges the browser limitation and the AgentCore SigV4 contract without ever shipping AWS credentials down to the browser.

## app.js: presigner integration

```javascript
async function resolveWsUrl() {
  // Local dev path: no presign URL configured -> use the local-dev sentinel.
  if (!PRESIGN_URL) return WS_LOCAL_DEV_URL;
  // Production path: fetch a short-lived presigned WSS URL from the Lambda
  // Function URL. Failures here flow through the existing ws-connect-failed
  // WID-06 branch (D-28 trigger).
  const resp = await fetch(PRESIGN_URL, { method: "GET", cache: "no-store" });
  if (!resp.ok) throw new Error("presign fetch failed: HTTP " + resp.status);
  const body = await resp.json();
  if (!body.url) throw new Error("presign response missing url");
  return body.url;
}
```

*Source: frontend/app.js — Phase 3 Plan 03-04*

The source tree keeps the `__PRESIGN_URL__` placeholder and the `ws://localhost:8080/ws` sentinel for local dev. `bin/build-widget.sh` sed-replaces only on the dist copy at deploy time — the source tree is never mutated. The `typeof __PRESIGN_URL__ !== "undefined"` guard keeps `docker compose up` from Section 3.2 working unchanged (D-27 local-dev unchanged).

## Audio capture: 16 kHz Int16 PCM (frontend/audio-capture-worklet.js)

```javascript
class CaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.targetRate = 16000;
    // One-pole IIR LPF state. Cutoff ~7 kHz keeps the LPF below the 8 kHz
    // Nyquist limit of the 16 kHz target rate, so anything that could
    // alias is attenuated before decimation.
    this._lpfState = 0;
    this._lpfCoeff = Math.exp(-2 * Math.PI * 7000 / sampleRate);
    this._cursor = 0;
  }
  // process(): anti-alias LPF -> cursor-based decimation -> Int16 -> postMessage
}
```

*Source: frontend/audio-capture-worklet.js — Phase 2 Plan 02-02*

Chrome/Edge/Safari browser AudioContext native rate is typically 48 kHz; the AudioWorklet runs an anti-alias LPF + cursor-based decimation down to 16 kHz Int16 before sending over WSS — the Sonic input format matches exactly. The cursor carries the fractional remainder across quanta to avoid drift on non-integer sample-rate ratios (e.g., 44.1 kHz native).

## 5-state record button (UX)

| State | Pill text | Button label | WID-06 error string |
|-------|-----------|--------------|---------------------|
| idle | disconnected | Record | — |
| connecting | connecting | Connecting... | — |
| listening | recording | Recording (click to stop) | — |
| speaking | connected | Agent speaking | — |
| error | error | Retry | "Couldn't reach the agent —" / "The agent didn't respond in time —" / "Microphone is muted —" |

*Source: frontend/app.js + frontend/styles.css — Phase 3 Plan 03-02*

State machine: a single class swap `recordBtn.className = "btn btn-" + state` — per-state styling (color + animation) lives in `styles.css` under `.btn-{idle,connecting,listening,speaking,error}`. The WID-06 error strings are verbatim from UI-SPEC; the em-dash is preserved (Plan 03-02 rationale).

## Step 1: Build + deploy the widget (bin/build-widget.sh)

```bash
bin/build-widget.sh
```

*Source: bin/build-widget.sh — Phase 3 Plan 03-02*

What it does:

- Reads `presign_url` from `terraform output -raw presign_url` (populated after Section 3.3 Step 3.5 second-pass apply).
- Copies `frontend/*` into `dist/widget/` (the source tree is never mutated).
- sed-replaces the `__PRESIGN_URL__` literal in `dist/widget/app.js` via temp-file + `mv` (portable BSD/GNU sed).
- Sanity gate: the `__PRESIGN_URL__` placeholder must be gone from the dist artifact — exit 3 if it survives.
- `aws s3 sync dist/widget/ s3://<widget-bucket>/ --delete` (region `ap-northeast-1`).
- `aws cloudfront create-invalidation --paths /*` — `/*` counts as one invalidation path, well within the free-tier 1000 paths/month.

## Step 2: Open the widget URL

```bash
terraform -chdir=infra/envs/prod output -raw widget_cloudfront_url
# https://<your-distribution>.cloudfront.net/
# -> open in a desktop browser (Chrome/Firefox/Safari/Edge all work).
# -> click "Record" -> allow microphone access.
```

*Source: RUNBOOK.md (Phase 3 Step 4) — Phase 3 Plan 03-04*

![Widget UI — idle state](/images/3.4-web-widget/widget-idle-state.png)

{{% notice warning %}}
**HTTPS is required for microphone access:** the browser only allows `getUserMedia()` in a secure context — `https://` or `localhost`. If you open the widget over `http://<ip>:8000` (no HTTPS, no localhost), the permission prompt does NOT appear and `getUserMedia` rejects immediately with `NotAllowedError`. Your CloudFront distribution sets `viewer_protocol_policy=redirect-to-https` (Plan 03-01) so it redirects HTTP -> HTTPS automatically — the workshop path is fine. If you test locally on a LAN IP, use `localhost` from a browser on the same machine (Section 3.2 docker compose path) rather than the IP — this is a browser security-model constraint, not a misconfiguration.

*Source: frontend/app.js — Phase 3 Plan 03-02*
{{% /notice %}}

Browser test flow:

1. Click "Record" → the button transitions to `connecting` (gray spinner).
2. The browser asks for microphone permission → click "Allow".
3. Status pill flips to `recording` → button label becomes "Recording (click to stop)".
4. Say: "Do you have MacBook Pro?"
5. Sonic calls the `lookup_product` tool against the Section 3.1 KB → button flips to `speaking` → audio plays back the Apple-Store-style answer with stock + price.
6. Sonic finishes → button returns to `listening` so you can ask another question; or click the button to end → `idle`.

## Custom domain (deferred to v2)

The default CloudFront cert `*.cloudfront.net` is enough for the workshop scope — HTTPS-only is enforced via `viewer_protocol_policy=redirect-to-https`. CloudFront `MinimumProtocolVersion` silently downgrades from `TLSv1.2_2021` (set in Terraform) to `TLSv1` when `CloudFrontDefaultCertificate=true` — this is an AWS-side override to maximize client reach (documented behavior, not a regression).

A custom domain + ACM cert (which would unlock the `TLSv1.2_2021` minimum) is deferred to v2 per D-26 — not in v1 workshop scope.

## What's next

The widget is live on your CloudFront URL with `ap-northeast-1` origin and global edges. Section 3.5 ships the CloudWatch dashboard `hera-prod` (5 panels) + 2 operational alarms + 1 billing alarm cross-region (us-east-1) so you can monitor agent + widget traffic and cost without poking at `aws cloudwatch get-metric-statistics` by hand.
