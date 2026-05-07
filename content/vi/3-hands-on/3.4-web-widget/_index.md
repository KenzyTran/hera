---
title: "3.4 Web Widget"
date: 2025-01-01
weight: 4
---

## Mục tiêu phần này

Deploy widget HTML/JS lên S3+CloudFront, browser mở URL HTTPS, click record, allow microphone, nói chuyện với AgentCore Runtime đã deploy ở Phần 3.3. Mỗi học viên có CloudFront URL riêng vì widget hosting nằm trong Terraform của tài khoản học viên (Bước 1 Phần 3.3).

## Cấu trúc widget (frontend/)

```
frontend/
├── index.html               # record button + status pill + transcript area
├── app.js                   # 5-state machine + resolveWsUrl + heartbeat
├── styles.css               # Apple Store light: .btn-{idle,connecting,listening,speaking,error}
└── audio-capture-worklet.js # AudioWorklet: 48kHz mic -> anti-alias LPF -> 16kHz Int16
```

*Source: frontend/ — Phase 3 Plan 03-02*

Tối giản, không framework — single-folder gọn để host được trên S3+CloudFront hoặc GitHub Pages (WID-01). Region default cho mọi AWS API call vẫn `ap-northeast-1`; CloudFront edge thì global tự động.

## Vì sao cần presigner Lambda (D-25 Rule-4)

Vấn đề: browser KHÔNG SigV4-sign WebSocket upgrade trực tiếp được — Web `WebSocket` API không expose Authorization header config. Mà AgentCore Runtime `wss://...` data-plane endpoint REQUIRE SigV4 auth.

Solution: Lambda Function URL (presigner) chạy trong AWS, dùng IAM exec-role credentials, tạo SigV4-presigned WSS URL TTL 300s, trả `{"url": "wss://..."}` khi browser fetch. Flow:

1. Browser load widget từ CloudFront → click record.
2. Widget fetch presigner Function URL (`https://<id>.lambda-url.ap-northeast-1.on.aws/`).
3. Presigner trả `{"url": "wss://..."}` (SigV4-presigned, expires 300s).
4. Widget mở `WebSocket(wss://...)` — handshake authenticate qua presigned query string.

Đây là Plan 03-04 Rule-4 architectural deviation — bridges browser limitation với AgentCore SigV4 contract mà không cần shipping AWS credentials xuống browser.

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

Source tree giữ `__PRESIGN_URL__` placeholder và sentinel `ws://localhost:8080/ws` cho local dev. `bin/build-widget.sh` sed-replace lúc deploy chỉ trên dist copy — source tree không bao giờ bị mutate. `typeof __PRESIGN_URL__ !== "undefined"` guard giữ `docker compose up` ở Phần 3.2 hoạt động không đổi (D-27 local-dev unchanged).

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

Chrome/Edge/Safari browser AudioContext native rate thường 48 kHz; AudioWorklet xử lý anti-alias LPF + cursor-based decimation xuống 16 kHz Int16 trước khi gửi qua WSS — Sonic input format khớp đúng. Cursor carry fractional remainder qua quanta để không drift trên non-integer sample-rate ratios (e.g., 44.1 kHz native).

## 5-state record button (UX)

| State | Pill text | Button label | WID-06 error string |
|-------|-----------|--------------|---------------------|
| idle | disconnected | Record | — |
| connecting | connecting | Connecting... | — |
| listening | recording | Recording (click to stop) | — |
| speaking | connected | Agent speaking | — |
| error | error | Retry | "Couldn't reach the agent —" / "The agent didn't respond in time —" / "Microphone is muted —" |

*Source: frontend/app.js + frontend/styles.css — Phase 3 Plan 03-02*

State machine: single class swap `recordBtn.className = "btn btn-" + state` — per-state styling (color + animation) sống ở `styles.css` dưới `.btn-{idle,connecting,listening,speaking,error}`. WID-06 error strings verbatim từ UI-SPEC; em-dash giữ nguyên (Plan 03-02 rationale).

## Bước 1: Build + deploy widget (bin/build-widget.sh)

```bash
bin/build-widget.sh
```

*Source: bin/build-widget.sh — Phase 3 Plan 03-02*

What it does:

- Reads `presign_url` từ `terraform output -raw presign_url` (populated sau Phần 3.3 Bước 3.5 second-pass apply).
- Copy `frontend/*` sang `dist/widget/` (source tree không bao giờ bị mutate).
- sed-replace `__PRESIGN_URL__` literal trong `dist/widget/app.js` qua temp file + `mv` (portable BSD/GNU sed).
- Sanity gate: `__PRESIGN_URL__` placeholder phải biến mất khỏi dist artifact — exit 3 nếu còn.
- `aws s3 sync dist/widget/ s3://<widget-bucket>/ --delete` (region `ap-northeast-1`).
- `aws cloudfront create-invalidation --paths /*` — `/*` count là 1 invalidation path, well within free tier 1000 path/tháng.

## Bước 2: Mở widget URL

```bash
terraform -chdir=infra/envs/prod output -raw widget_cloudfront_url
# https://<your-distribution>.cloudfront.net/
# -> mở trong browser desktop (Chrome/Firefox/Safari/Edge đều OK).
# -> click "Record" -> cho phép microphone access.
```

*Source: RUNBOOK.md (Phase 3 Step 4) — Phase 3 Plan 03-04*

![Widget UI — idle state](/images/3.4-web-widget/widget-idle-state.png)

{{% notice warning %}}
**HTTPS bắt buộc cho microphone:** browser CHỈ cho phép `getUserMedia()` access trong secure context — `https://` hoặc `localhost`. Nếu mở widget qua `http://<ip>:8000` (không HTTPS, không localhost), permission prompt KHÔNG hiện và `getUserMedia` reject ngay với `NotAllowedError`. CloudFront distribution của bạn đặt `viewer_protocol_policy=redirect-to-https` (Plan 03-01) tự redirect HTTP -> HTTPS nên path workshop OK. Nếu test local trên IP LAN, dùng `localhost` ở browser cùng máy (Phần 3.2 docker compose path) thay cho IP — đây là constraint của browser security model, không phải lỗi cấu hình.

*Source: frontend/app.js — Phase 3 Plan 03-02*
{{% /notice %}}

Test flow trong browser:

1. Click "Record" → button chuyển trạng thái `connecting` (gray spinner).
2. Browser hỏi microphone permission → click "Allow".
3. Status pill chuyển `recording` → button label "Recording (click to stop)".
4. Nói: "Do you have MacBook Pro?"
5. Sonic gọi `lookup_product` tool ở KB Phần 3.1 → button chuyển `speaking` → audio playback Apple-Store-style answer kèm stock + price.
6. Sonic xong → button quay về `listening` để bạn hỏi tiếp; hoặc click button để kết thúc → `idle`.

## Custom domain (deferred v2)

CloudFront default cert `*.cloudfront.net` đủ cho workshop scope — HTTPS-only enforced qua `viewer_protocol_policy=redirect-to-https`. CloudFront `MinimumProtocolVersion` silently downgrade từ `TLSv1.2_2021` (set trong Terraform) xuống `TLSv1` khi `CloudFrontDefaultCertificate=true` — đây là AWS-side override để maximize client reach (documented behavior, không phải regression).

Custom domain + ACM cert (kèm `MinimumProtocolVersion = TLSv1.2_2021` minimum) deferred v2 per D-26 — không phải v1 workshop scope.

## Tiếp theo

Widget đang live trên CloudFront URL của bạn ở `ap-northeast-1` origin/global edge. Phần 3.5 ship CloudWatch dashboard `hera-prod` (5 panels) + 2 op alarms + 1 billing alarm cross-region (us-east-1) để bạn theo dõi traffic + cost của agent + widget mà không cần manual `aws cloudwatch get-metric-statistics`.
