# Architecture Research

**Domain:** AWS-native real-time voice AI agent (browser-only channel, single-account, single-region for v1)
**Researched:** 2026-05-04
**Confidence:** HIGH for component layout and Bedrock/Pipecat integration; MEDIUM for VPC endpoint behaviour with Nova Sonic bidirectional streaming (see "Open Questions" below — needs validation in deploy phase).

---

## 1. Recommended Architecture for hera v1

### 1.1 System Overview (component diagram)

```
                               Browser (learner)
                       ┌────────────────────────────┐
                       │  static page (S3+CF or     │
                       │  served from same ALB)     │
                       │  ┌──────────────────────┐  │
                       │  │ web widget (HTML/JS) │  │
                       │  │  - getUserMedia mic  │  │
                       │  │  - PCM 16k/16-bit    │  │
                       │  │  - <audio> playback  │  │
                       │  │  - WSS client        │  │
                       │  └──────────┬───────────┘  │
                       └─────────────┼──────────────┘
                                     │   wss:// (TLS)
                                     │   binary frames (PCM in / PCM out)
                                     │   + small JSON control frames
                                     ▼
                  ┌────────────────────────────────────────┐
                  │      ACM cert + custom domain          │
                  │      (Route53 → ALB)                   │
                  └────────────────────────────────────────┘
                                     │
                                     ▼
            ┌────────────────────────────────────────────────┐
            │  Application Load Balancer (public subnets)    │
            │  - HTTPS:443 listener                          │
            │  - target group: type=ip, protocol=HTTP        │
            │  - WebSocket upgrade pass-through              │
            │  - idle_timeout = 3600s  (60s default kills WS)│
            │  - stickiness = lb_cookie  (per-conn affinity) │
            │  - deregistration_delay = 600s                 │
            └────────────────┬───────────────────────────────┘
                             │
                             ▼  HTTP/1.1 Upgrade → WebSocket
            ┌────────────────────────────────────────────────┐
            │   ECS Fargate service (private subnets)        │
            │   ┌─────────────┐ ┌─────────────┐              │
            │   │ Pipecat task│ │ Pipecat task│   ... N      │
            │   │ FastAPI+    │ │ FastAPI+    │              │
            │   │ uvicorn     │ │ uvicorn     │              │
            │   │  WS server  │ │  WS server  │              │
            │   │  Pipeline:  │ │             │              │
            │   │  WS in →    │ │             │              │
            │   │  Sonic LLM →│ │             │              │
            │   │  WS out     │ │             │              │
            │   └──────┬──────┘ └─────────────┘              │
            └──────────┼─────────────────────────────────────┘
                       │
              ┌────────┴───────────────────────────────┐
              │                                        │
              ▼ HTTPS (HTTP/2 bidi)                    ▼ HTTPS
  ┌─────────────────────────────┐         ┌─────────────────────────────┐
  │  bedrock-runtime endpoint   │         │  bedrock-agent-runtime      │
  │  InvokeModelWith            │         │  Retrieve / RetrieveAndGen  │
  │  BidirectionalStream        │         │  (Knowledge Base API)       │
  │  → amazon.nova-2-sonic-v1:0 │         │  → KB id (S3 Vectors)       │
  └─────────────────────────────┘         └──────────────┬──────────────┘
                                                         │
                                                         ▼
                                          ┌──────────────────────────────┐
                                          │  Bedrock Knowledge Base      │
                                          │  ┌───────────────────────┐   │
                                          │  │ Embed model:          │   │
                                          │  │ amazon.titan-embed-v2 │   │
                                          │  └──────────┬────────────┘   │
                                          │             │                │
                                          │  ┌──────────▼────────────┐   │
                                          │  │ S3 Vectors index      │   │
                                          │  │ (vector store)        │   │
                                          │  └───────────────────────┘   │
                                          │  ┌───────────────────────┐   │
                                          │  │ S3 source bucket      │   │
                                          │  │ apple-catalog/*.md    │   │
                                          │  └───────────────────────┘   │
                                          └──────────────────────────────┘

  Cross-cutting:
   - CloudWatch Logs (Pipecat stdout, ALB access logs to S3)
   - CloudWatch Metrics (ALB ActiveConnectionCount, ECS CPU/Mem,
     Bedrock invocation count) + alarms
   - ECR (Pipecat container image)
   - Secrets Manager (none required for v1 — IAM task role does auth)
   - IAM roles: task execution role + task role (Bedrock + KB perms)
```

### 1.2 Component Responsibilities

| Component | Owns | Implementation |
|-----------|------|----------------|
| **Web widget** | Mic capture, audio playback, WSS connection lifecycle, push-to-talk UX | Plain HTML + JS using `getUserMedia` + `AudioWorklet` for PCM 16 kHz mono encode, native `WebSocket` API, `<audio>` or AudioBufferSourceNode for 24 kHz output. Hosted as static file (option A: S3+CloudFront, option B: served by Pipecat container at `/`) |
| **Static hosting** | Serve widget HTML/JS over HTTPS | v1 simplest: have FastAPI in Pipecat container serve `/static/index.html` and the same ALB handle both `/` and `/ws`. v1.1 split to S3+CloudFront if CORS / cache becomes a concern |
| **ALB** | TLS termination (ACM cert), WebSocket upgrade, sticky routing, public ingress | One ALB, `internet-facing`, in 2 public subnets across 2 AZs. HTTPS:443 listener forwards to one target group |
| **Pipecat task (ECS Fargate)** | Per-session orchestration: receive PCM from browser, push frames into Pipecat pipeline → `AWSNovaSonicLLMService`, receive PCM frames back, push to browser; execute tool calls (KB retrieve) | Python 3.12, `pipecat-ai[aws-nova-sonic]`, FastAPI app with `FastAPIWebsocketTransport` or `WebsocketServerTransport`, uvicorn ASGI server. Container image in ECR. Awaits `bedrock-runtime` HTTP/2 bidi stream |
| **Bedrock Nova 2 Sonic** | Real-time S2S: ASR + reasoning + TTS in one model | `amazon.nova-2-sonic-v1:0` via `InvokeModelWithBidirectionalStream`. Pipecat's `AWSNovaSonicLLMService` wraps this and auto-handles the ~8-minute session limit by buffering and reconnecting transparently |
| **Bedrock Knowledge Base** | RAG over Apple product catalog | KB id with embedding model `amazon.titan-embed-text-v2:0`, vector store = **S3 Vectors index**, source = S3 bucket of markdown files. Sonic calls it via tool/function call; Pipecat's `@llm.function()` decorator dispatches to `bedrock-agent-runtime:Retrieve` |
| **S3 source bucket** | Hold raw catalog documents (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4 spec sheets + stock counts) | Versioned bucket; KB ingestion job re-indexes when objects change |
| **S3 Vectors index** | Vector store for KB embeddings | Native S3 Vectors (no OpenSearch). Cost-optimized for small catalog |
| **CloudWatch** | Logs, metrics, alarms | Container stdout → log group `/ecs/hera/pipecat`. ALB access logs → S3. Alarms on `ActiveConnectionCount`, `TargetResponseTime`, ECS `CPUUtilization`, Bedrock 4xx/5xx |
| **ECR** | Container registry | Single private repo `hera/pipecat`, lifecycle policy keeps last 10 images |
| **Terraform** | IaC for everything above | Single root module orchestrating sub-modules: `network/`, `kb/`, `ecs/`, `alb/`, `widget/` |

---

## 2. Data Flow — End-to-End Trace of One Utterance

```
T+0ms     User clicks "speak", browser starts AudioWorklet capturing
          mic → 16 kHz / 16-bit / mono PCM frames (20–40 ms each).
T+~5ms    Browser opens (or re-uses) WSS to wss://hera.example.com/ws.
          ALB routes on cookie (sticky) → Fargate task #3.
          Pipecat task accepts upgrade, instantiates a new Pipeline
          for this connection if first message.
T+~5–500ms Browser streams binary PCM frames over WSS in real time.
          Each frame enters Pipecat as an InputAudioRawFrame.
          Pipecat's VAD (Silero or Sonic-internal) detects speech.
T+ASR     PCM frames are forwarded into the open
          InvokeModelWithBidirectionalStream HTTP/2 channel that
          AWSNovaSonicLLMService maintains to Bedrock. Sonic does
          ASR + reasoning incrementally; speculative transcript
          frames flow back upstream.
T+tool    If Sonic decides to call the lookup_product tool, Pipecat
          receives a function-call event. The @llm.function() handler
          calls bedrock-agent-runtime:Retrieve(KbId=…, query=…) over
          standard HTTPS. Result chunks are formatted and pushed back
          into the Sonic session via the result_callback.
T+TTS     Sonic generates response audio as 24 kHz / 16-bit / mono
          PCM, streamed back over the same HTTP/2 channel.
T+play    Pipecat receives OutputAudioRawFrame, forwards as binary
          WebSocket message to the browser. AudioWorklet buffers and
          plays through the user's speakers.
T+done    On end-of-turn, Sonic emits a content-end / utterance-end
          event. Pipecat keeps the WSS open and the Sonic session
          warm for the next user turn.
T+~8min   AWSNovaSonicLLMService proactively opens a new bidi stream
          before the 8-minute Bedrock session cap, buffers brief
          incoming audio during the seam, and resumes — invisible to
          user. (transition_threshold_seconds, default behaviour.)
T+hangup  Browser closes WSS (page unload or Stop button) → Pipecat
          tears down the Pipeline, closes the Bedrock stream,
          flushes logs.
```

Three loops, three latency budgets:

| Loop | Path | Target |
|------|------|--------|
| Voice loop (user→model→user) | mic → WSS → Pipecat → Bedrock bidi → Pipecat → WSS → speakers | < 1 s perceived end-of-utterance to first response audio |
| Tool loop | Sonic function call → Pipecat → KB Retrieve → Pipecat → Sonic | < 500 ms ideally; tolerable up to 1.5 s |
| Session continuity | Pipecat seam-stitching across 8-min Sonic boundary | Imperceptible to user (built into AWSNovaSonicLLMService) |

---

## 3. Networking & VPC Layout

### 3.1 VPC topology (single region — `ap-northeast-1` prod / `us-east-1` dev)

```
VPC 10.0.0.0/16
├── Public subnets   (2 AZs):  10.0.0.0/24,   10.0.1.0/24
│   ├── ALB (internet-facing)
│   ├── Internet Gateway
│   └── NAT Gateway (AZ-a)   ← v1 simplification: single NAT, not HA
├── Private subnets  (2 AZs):  10.0.10.0/24, 10.0.11.0/24
│   ├── Fargate tasks (ECS service)
│   └── VPC Interface Endpoints (see below)
└── Route tables
    ├── public  : 0.0.0.0/0 → IGW
    └── private : 0.0.0.0/0 → NAT (AZ-a)
```

### 3.2 Egress from Pipecat to AWS APIs — NAT vs VPC Endpoints

**Recommendation for v1:** Use **VPC Interface Endpoints (PrivateLink) for the AWS APIs Pipecat hits, plus a single NAT only for outbound non-AWS traffic** (pip installs at build time happen in CodeBuild/local, so the running task usually needs no general internet).

| Endpoint | Service name | Why needed |
|----------|-------------|------------|
| `bedrock-runtime` | `com.amazonaws.<region>.bedrock-runtime` | Nova Sonic `InvokeModelWithBidirectionalStream` |
| `bedrock-agent-runtime` | `com.amazonaws.<region>.bedrock-agent-runtime` | KB `Retrieve` calls |
| `ecr.api` + `ecr.dkr` | `com.amazonaws.<region>.ecr.api`, `…ecr.dkr` | Pull container image at task start |
| `s3` (gateway endpoint) | `com.amazonaws.<region>.s3` | ECR layer downloads (S3-backed) + ALB access logs |
| `logs` | `com.amazonaws.<region>.logs` | CloudWatch Logs from container |
| `secretsmanager` (optional) | `com.amazonaws.<region>.secretsmanager` | Future: API key for widget auth |

With these endpoints in place the Fargate task can run **without any outbound internet route** for normal operation, and the NAT gateway can be deleted in v1.1 once verified. For v1, keep one NAT to make initial debugging easier (e.g. external health pings).

**Why this matters:**
- Cost: NAT Gateway = $0.045/hr + $0.045/GB processed. Bedrock voice traffic over NAT is real money. Interface endpoints are $0.01/hr each + $0.01/GB but stay on AWS backbone.
- Security: Bedrock traffic never leaves the AWS network.
- Latency: Marginally lower and more deterministic than NAT.

**MEDIUM CONFIDENCE caveat:** AWS docs confirm `bedrock-runtime` has an interface endpoint, but I did not find an explicit AWS confirmation that `InvokeModelWithBidirectionalStream` (HTTP/2 long-lived) is fully supported via PrivateLink in every region. Validate by smoke-testing in dev (`us-east-1`) before relying on it in prod. If it turns out bidi streams need public egress in `ap-northeast-1`, fall back to NAT for `bedrock-runtime` only and keep PrivateLink for the rest. Flag this as a Phase 0 spike in the roadmap.

### 3.3 ALB configuration — non-defaults that matter for WebSockets

| Attribute | Default | hera value | Why |
|-----------|---------|-----------|-----|
| `idle_timeout.timeout_seconds` | 60 | **3600** | Default kills any WS that goes 60 s without bytes. A user pausing mid-conversation would drop. 1 h is generous and matches typical workshop session length. |
| `stickiness.enabled` | false | **true** (`lb_cookie`) | The HTTP Upgrade and the subsequent frames must hit the same task. Without stickiness, the upgrade succeeds but later frames can land on a different task that has no state. |
| `stickiness.duration_seconds` | n/a | 3600 | Match idle timeout. |
| `deregistration_delay.timeout_seconds` | 300 | **600** | When ECS replaces a task (deploy or scale-in), in-flight WS connections should drain. 10 min covers most conversations. |
| `routing.http2.enabled` | true | leave on | Browser→ALB is HTTP/2 capable; ALB→Fargate can be HTTP/1.1 for the WS upgrade — that's the supported path. |
| Health check path | `/` | `/healthz` | A cheap FastAPI route that returns 200 without spinning up a Pipecat pipeline. |
| `access_logs.enabled` | false | **true** → S3 | Required for debugging "why did this WS drop" and for the workshop's observability section. |

### 3.4 ACM cert

- Issue cert in **the ALB's region** (ACM is regional for ALB use).
- Cover one apex `hera.example.com` (or whatever workshop chooses).
- Validate via DNS (Route53 record). Terraform `aws_acm_certificate` + `aws_acm_certificate_validation`.
- For pure workshop scope, learners can also point ALB at the auto-generated `*.elb.amazonaws.com` and skip ACM (but then browser shows scary warnings on `wss://` — not great). v1 should require a real domain and include ACM in the module; the workshop docs hand-walk the domain step.

---

## 4. Sessions: Mapping Pipecat Process to User Session

### 4.1 The model: **shared task, isolated pipelines**

One Pipecat Fargate task hosts **many** WebSocket connections concurrently. Each WS connection gets its own `Pipeline` instance, its own pipeline task, and its own bidi stream to Bedrock. Tasks **do not** spin up per session — that would mean cold-start (~30 s pull + boot) on every "click to talk".

**Why not one task per session?**
- Fargate task boot is too slow for "click and talk" UX.
- Each task carries ~256–512 MB baseline overhead (Python, libraries) — wasteful per connection.
- ECS service auto-scaling reacts in 1–2 minute windows; per-session would fall behind a busy classroom.

**Why not a long-running connection pool / multiplexed Bedrock channel?**
- Bedrock bidi streams are 1:1 with a "session". Pipecat already manages this. Multiplexing would mean reimplementing Pipecat. Out of scope.

**Capacity model:** Each Pipecat task can comfortably host 5–20 concurrent voice sessions on `0.5 vCPU / 1 GB` Fargate sizing. The task is mostly I/O-bound (bytes between WSS and HTTP/2). Bedrock does the heavy compute. Validate the actual ceiling in load test (workshop probably hits 1–10 simultaneous learners; even 5 per task is luxurious headroom).

### 4.2 Autoscaling

- Service-level scaling on `ALBRequestCountPerTarget` is wrong for WS — a WebSocket counts as one "request" forever and never re-counts.
- Use `ECSServiceAverageCPUUtilization` target tracking (e.g. 60 %) **plus** a custom metric on `ActiveConnectionCount / desired_task_count` derived from CloudWatch math.
- Min capacity = 1 task. Max = 4 tasks for v1 (workshop). Step scaling, not target tracking, is friendlier for WS because it avoids thrashing.
- Scale-in cooldown ≥ deregistration delay so we don't kill tasks that still have connected users.

### 4.3 Per-session lifecycle inside one Pipecat task

```python
# Conceptual — actual Pipecat code uses FastAPIWebsocketTransport
@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    transport = FastAPIWebsocketTransport(ws, params=...)
    llm = AWSNovaSonicLLMService(
        region="ap-northeast-1",
        # IAM via task role — no key here
        settings=AWSNovaSonicLLMService.Settings(
            model="amazon.nova-2-sonic-v1:0",
            voice="...",
            system_instruction=APPLE_STORE_SYSTEM_PROMPT,
        ),
        tools=ToolsSchema(standard_tools=[lookup_product_tool]),
    )

    @llm.function("lookup_product")
    async def lookup_product(args, result_callback):
        resp = await retrieve_from_kb(args["query"])
        await result_callback(resp)

    pipeline = Pipeline([transport.input(), llm, transport.output()])
    task = PipelineTask(pipeline)
    await PipelineRunner().run(task)  # blocks until WS closes
```

One coroutine per connection. FastAPI/uvicorn runs them all on the same event loop in the same task. Memory cost per connection ≈ Pipeline buffers (single-digit MB) + Bedrock HTTP/2 stream state.

---

## 5. State Management

### 5.1 What state exists

| State | Lifetime | Lives in | Survives restart? |
|-------|----------|----------|-------------------|
| Audio buffers (in-flight PCM) | seconds | Pipecat pipeline frame queues | No — and shouldn't |
| Conversation history | per session | **Inside Sonic** (Bedrock manages it) + a small `OpenAILLMContext`-equivalent kept by `AWSNovaSonicLLMService` for session continuation | **Yes within the 8-min seam**; **No** across full task replacement |
| Tool definitions | static | Code | n/a |
| KB documents | hours/days | S3 + S3 Vectors | Yes |
| Auth / rate-limit counters | per IP / per minute | None in v1 | n/a |
| Workshop session metadata (e.g. "learner X spoke 12 min today") | persistent, future feature | Not present in v1 | — |

### 5.2 v1 decision: **no DynamoDB, no Redis**

Conversation context is held by Sonic itself, and Pipecat's auto-reconnect handles the only realistic interruption (8-min session cap). Adding DynamoDB now would:

- pull in another module learners must understand;
- introduce a write per turn (cost + latency);
- not actually buy resilience, because if a Fargate task dies the WSS dies too — the user reconnects and starts a fresh conversation either way.

**v1.1 / v2 trigger to revisit:** when the workshop adds (a) Twilio (phone hangup-resume should keep context), or (b) cross-session memory ("remember I'm shopping for a MacBook"), or (c) auth ("my last 5 conversations"). Then add DynamoDB with PK = `session_id` and a 7-day TTL.

### 5.3 What survives a Pipecat task restart

- KB documents and indexes — **unchanged**.
- Active conversations — **lost**. Browser receives WS close; widget should reconnect and start fresh. Acceptable for workshop. Workshop docs should explicitly tell learners "deploys end conversations".

### 5.4 What the Pipecat in-process state implies for deploys

- Use ECS rolling deploy with `minimumHealthyPercent=100`, `maximumPercent=200`. New tasks come up, register healthy, then old tasks deregister (deregistration delay 600 s lets in-flight conversations finish or time out).
- Don't use blue/green for v1 — overkill, and ALB target group switch would still cut active WS.

---

## 6. Build Order — Dependency-Ordered Phases

### 6.1 The dependency graph

```
                  (terraform skeleton, AWS account, Bedrock model access)
                                       │
              ┌────────────────────────┴─────────────────────────┐
              │                                                  │
              ▼                                                  ▼
     [A] Knowledge Base                              [B] Network + ECR
       - S3 source bucket                               - VPC, subnets, IGW, NAT
       - S3 Vectors index                               - VPC endpoints
       - Bedrock KB id                                  - Sec groups
       - test: Retrieve via CLI                         - ECR repo
              │                                                  │
              └─────────────────┬────────────────────────────────┘
                                ▼
                    [C] Pipecat container (local)
                       - FastAPI + WS endpoint
                       - AWSNovaSonicLLMService wired
                       - tool function calls KB
                       - test: local browser → local container → real Bedrock
                                ▼
                    [D] ECS service + ALB
                       - task def with task role (Bedrock+KB perms)
                       - ALB, target group, ACM cert, listener
                       - test: HTTPS curl /healthz
                                ▼
                    [E] Web widget
                       - mic capture, WSS client, audio playback
                       - hosted at / on Pipecat container OR S3+CF
                       - test: real conversation through public URL
                                ▼
                    [F] Observability + alarms
                       - log group, metric filters
                       - dashboards: sessions, p50/p95, error rate
                       - alarms
                                ▼
                    [G] terraform destroy verification
                       - clean teardown
                       - workshop "Cleanup" section
```

### 6.2 Why this order

1. **KB first (parallel with Network)** because: the KB id is an input to Pipecat config; KB ingestion has its own latency you'd rather discover early; KB can be built and tested with the AWS CLI alone, no compute needed.
2. **Network/ECR before ECS** because: ECS task def requires VPC + subnets + ECR image to exist.
3. **Local Pipecat container before ECS** because: every minute of debugging in Fargate costs ~5 minutes of feedback loop (push → deploy → check logs). Get the container working end-to-end against real Bedrock + real KB on your laptop first. This is the highest-leverage phase.
4. **ECS+ALB after container works** because: deploying a known-good container to ECS is mostly mechanical; debugging Bedrock connectivity and TLS interleaved is painful.
5. **Widget last among build steps** because: Pipecat can be tested with a tiny CLI WS client (or `websocat`) before a real browser widget exists. Avoids tangling browser issues (autoplay policy, AudioWorklet quirks) with backend issues.
6. **Observability before sign-off** because: the workshop needs to teach how to diagnose problems, which requires real metrics flowing.
7. **Cleanup verified before declaring done** because: leaving a NAT GW or Bedrock KB behind costs the learner real money, and "I followed the workshop and got a $30 bill" is the worst possible outcome.

### 6.3 Suggested phase shapes for the roadmap

- **Phase 0 — Spike: Bedrock bidi over PrivateLink in `ap-northeast-1`.** Hours of effort, removes a risk that would force re-architecture. (See "MEDIUM CONFIDENCE" note in §3.2.)
- **Phase 1 — Knowledge Base end-to-end** (steps A above).
- **Phase 2 — Pipecat container, locally driven** (step C).
- **Phase 3 — Networking + ECS + ALB deploy** (steps B + D).
- **Phase 4 — Web widget + custom domain** (step E).
- **Phase 5 — Observability + alarms** (step F).
- **Phase 6 — Workshop docs (Hugo content)** — runs in parallel from Phase 2 onward; its "Hands-on" content trails real implementation by one phase.
- **Phase 7 — Cleanup, cost audit, smoke test from a fresh AWS account** (step G).

---

## 7. Failure Modes per Component

The workshop "what to teach about debugging" column is the load-bearing part — it informs PITFALLS.md and the Hugo Phần 3 / Phần 5 content.

| Component | Failure | What user sees | Diagnosis | Workshop teaches |
|-----------|---------|----------------|-----------|------------------|
| **Browser mic permission** | User denied / no HTTPS | Widget says "no mic" or `getUserMedia` rejects | Browser console | HTTPS is mandatory for `getUserMedia` outside `localhost`; ACM cert must be valid |
| **WSS handshake to ALB** | Cert mismatch, wrong DNS | Widget never connects, browser console shows TLS error | Browser network tab, `openssl s_client` | DNS → ALB binding, ACM cert in same region as ALB |
| **ALB → ECS** | No healthy targets | 502/503 from ALB | ALB target group "unhealthy", ECS event log | Health check path, security group ingress 443 → 8080 |
| **ALB idle timeout** | Conversation drops at minute 1 of silence | WS closes mid-session, audio stops | ALB access logs, browser sees code 1006 | Set `idle_timeout=3600`; this is the single most common WS-on-ALB pitfall |
| **Sticky sessions off** | Random "model didn't hear you" mid-conversation | Audio appears to send but model doesn't react | ALB access logs show different target IDs for same conn | `lb_cookie` stickiness on target group |
| **Pipecat task OOM** | Task killed, all sessions on it die | Widget reconnect required | CloudWatch container insights, ECS task stop reason | Monitor mem; bump task memory; suspect long-running coroutine leak |
| **Bedrock model not enabled** | First Sonic call returns `AccessDeniedException` | Widget connects, hears no response | CloudWatch logs in Pipecat container | Bedrock console → Model access → enable Nova 2 Sonic in the chosen region (this is the #1 surprise from the AWS doc set) |
| **Wrong region** | Pipecat in `ap-southeast-1` calling Sonic | `ResourceNotFoundException` or connection refused | Logs | Sonic only in `us-east-1`, `us-west-2`, `ap-northeast-1`, `eu-north-1` (per project doc) |
| **Bedrock 8-min session cap** | If misconfigured, mid-conversation cutoff | Should be invisible if Pipecat's auto-continuation is on | Pipecat logs show "session transition" event | Auto-continuation is on by default in `AWSNovaSonicLLMService`; teach what it is so learners aren't confused by the seam log line |
| **Bedrock throttling** | `ThrottlingException` on InvokeModelWithBidi | Conversation can't start, or KB tool call fails | CloudWatch Bedrock metrics, Pipecat logs | Service quotas; how to request increase; exponential backoff in tool callbacks |
| **KB ingestion failure** | KB returns empty for valid query | Bot says "I don't have information about that" for known products | KB ingestion job status in console | Check sync job; verify embedding model access; verify S3 source bucket permissions |
| **KB query authz** | Pipecat task missing `bedrock:Retrieve` | Tool callback throws | CloudWatch | Task IAM role: `bedrock:Retrieve` on the KB ARN, plus `bedrock:InvokeModelWithBidirectionalStream` on the Sonic model |
| **VPC endpoint missing/misconfigured** | Pipecat hangs trying to reach Bedrock | Long timeout then `EndpointConnectionError` | VPC flow logs, route table | Either add interface endpoint with private DNS enabled, or ensure NAT route works |
| **NAT gateway saturated** | Slowness during workshop with 30 learners | Latency p95 climbs | NAT GW metrics | Move Bedrock traffic off NAT to PrivateLink; or add NAT in second AZ |
| **Single NAT AZ outage** | Half of tasks lose egress | Some sessions fail randomly | NAT health, route table | v1 trade-off; v2 add HA NAT |
| **Container image pull fail at scale-out** | New task stuck in `PROVISIONING` | Slow scale-up | ECS events | ECR endpoint or NAT bandwidth; add `s3` gateway + `ecr.dkr`/`ecr.api` endpoints |
| **Browser autoplay policy** | First TTS chunk silent until user gesture | Bot seems mute on first turn | Browser console | UI must put first audio playback behind the "click to talk" user gesture (already implied by widget design) |
| **PCM format mismatch** | Sonic returns audio but distorted/garbled | Robotic noise or pitch shift | Compare browser sample rate to widget config | Input must be 16 kHz mono int16; output 24 kHz mono int16 — both confirmed in Pipecat docs |

---

## 8. Cost Shape per Session

Workshop scale: assume 50 learners × 30 min talk-time on demo day. That's 25 user-hours = 1,500 user-minutes per workshop run.

Per-session cost components, ranked by likely magnitude:

| Component | Driver | Cost per minute (rough) | Per 30-min session | Notes |
|-----------|--------|-------------------------|---------------------|-------|
| **Nova 2 Sonic** | Speech tokens in + out, both directions are billable | ~$0.017/min combined | ~$0.51 | Per project research: $0.003/1k input + $0.012/1k output (speech) (rounded; verify on AWS Nova pricing page at deploy time) |
| **Fargate compute** | Task vCPU + memory hours (amortized over concurrent sessions) | ~$0.04/hr per task @ 0.5 vCPU/1 GB; if 5 sessions/task, ~$0.008/hr/session = $0.0001/min | ~$0.004 | Negligible per-session. Always-on baseline (1 task 24/7) ≈ $30/mo. |
| **Bedrock KB Retrieve** | Number of tool calls × embedding cost + tiny query fee | ~$0.0001 per Retrieve call (Titan-v2 embed + S3 Vectors query) | ~$0.001 (10 calls/session) | Pricing dominated by embedding model. S3 Vectors per-query is sub-cent. |
| **S3 Vectors storage** | Index size (small for catalog) | ~$0.06 / GB-month (verify) | ~$0 per session | ~50 docs ≈ small kilobytes; storage is essentially free at this scale |
| **S3 source bucket** | Catalog markdown | trivial | ~$0 | |
| **ALB** | Hourly + LCU (connection count, new conn rate, bytes) | ~$0.025/hr base; LCU ~$0.008 | ~$0.0001 | Always-on cost is $18/mo regardless of usage |
| **NAT Gateway** (if used) | Hourly + GB processed | $0.045/hr + $0.045/GB; voice traffic via NAT could be 10–30 MB/session = ~$0.001 | ~$0.001 | Eliminate by using PrivateLink for Bedrock (recommended) |
| **VPC Interface Endpoints** | Hourly + GB | ~$0.01/hr each + $0.01/GB | ~$0 per session | ~$30/mo always-on for 4 endpoints in 2 AZs (8 ENIs). Trade for NAT. |
| **CloudWatch Logs** | Ingestion + retention | $0.50/GB ingest, $0.03/GB-mo storage | ~$0.001 | Be careful with verbose logging at scale |
| **CloudWatch Metrics** | Custom metrics | $0.30/metric-month for first 10k | ~$0 | |
| **ACM cert** | Free for ALB | — | $0 | |
| **Route53** | $0.50/hosted zone/month + queries | trivial | $0 | |
| **ECR** | $0.10/GB/month storage; pulls free in-region | trivial | $0 | |

**Per-session ballpark: ~$0.51 for a 30-minute conversation.** Sonic is ~99% of variable cost. Workshop full-run (50 × 30 min): ~$25 in Bedrock, plus ~$50/mo always-on infra (1 Fargate task + ALB + endpoints + log retention).

**Implications for workshop:**
- "Always-on" cost (~$50/mo) is the single most important number for learners, because they may forget to `terraform destroy` after class. Cleanup phase must be explicit and verified.
- Sonic minutes are the variable cost lever. If a learner accidentally leaves a session open all day, that's ~$25.
- Encourage learners to `terraform destroy` immediately after the demo. The workshop "Phần 4 Cleanup" must list everything and a verification checklist.

---

## 9. Alignment & Deviations from the AWS Pipecat Blueprint

The reference AWS blog (Part 1 + Part 2) describes the blueprint; hera makes these deliberate choices:

| Topic | AWS blog default | hera v1 | Reason |
|-------|------------------|---------|--------|
| Voice path | Cascaded (Transcribe + Polly + Nova Pro) in Part 1; unified Sonic in Part 2 | **Unified Sonic only** | Lower latency, fewer moving parts, one IAM scope, matches "pure-AWS native S2S" goal |
| Transport | Daily WebRTC (browser SDK) | **Plain WSS to ALB** | Daily is a third-party dependency outside AWS; learners would need a Daily account. WSS is fully AWS-stack and the workshop teaches transferable load-balancing skills |
| Frontend hosting | S3 + CloudFront with Cognito auth | **Static page served from Pipecat container at `/`** in v1; CloudFront optional in v1.1 | One fewer module to deploy; Cognito explicitly out of scope per project doc |
| IaC | CDK (per Part 2 sample repo) | **Terraform** | User preference, locked |
| Tools | Pipecat Flows + custom Python | **`@llm.function()` calling KB Retrieve directly** | Simpler; we have one tool, not a flow graph |
| Region | `us-east-1` examples | **`ap-northeast-1` prod, `us-east-1` dev** | Latency from VN; both have Sonic |
| Knowledge base | Not detailed in blog | **Bedrock KB + S3 Vectors** | Cost-driven choice locked at project level |
| Telephony | Twilio shown in Part 2 | **Out of scope** (v2) | Project doc |

These deviations are aligned with the blueprint's intent (cost-effective, AWS-native voice agent) — they swap implementation details that the blog leaves open.

---

## 10. Patterns to Follow / Anti-Patterns to Avoid

### Patterns

**P1 — Static frontend served by the same container in v1.** Two reasons: (1) avoids CORS between widget origin and WS origin, (2) one Terraform module instead of two. Promote to S3+CF in v1.1 if widget gets bigger or needs cache.

**P2 — IAM task role only; no static creds.** `AWSNovaSonicLLMService` will pick up the ECS task role automatically. Never bake AWS keys into the image or `.env`. Workshop teaches this explicitly.

**P3 — Health check decoupled from Pipeline.** `/healthz` returns 200 without touching Bedrock. Otherwise health checks themselves rack up Sonic invocations.

**P4 — Widget owns session_id, not server.** Widget generates a UUID at page load, sends as query string `wss://…/ws?sid=abc`. Logs are searchable by `sid`. Cheap, no DB needed.

**P5 — Function tools return small, focused snippets.** KB Retrieve gets `numberOfResults=3`. Sonic context is small; flooding it with 10 docs hurts latency and quality.

### Anti-Patterns

**AP1 — Per-session ECS task.** Cold starts (~30 s) ruin UX. Share tasks across sessions.

**AP2 — Storing conversation in DynamoDB on every turn for v1.** Adds latency, cost, and complexity for no current benefit. Sonic holds it.

**AP3 — API Gateway WebSocket for this.** API GW WS has a 10-minute idle limit and 2-hour max connection — incompatible with always-on conversational UX, plus per-message charges add up. Use ALB.

**AP4 — Lambda for Pipecat orchestration.** 15-min limit, no persistent process model, cold starts. Already excluded by project decision; mention so learners don't try.

**AP5 — One ALB per environment.** Fine for v1 (we have one prod + one dev). Don't shard further until you have a reason.

**AP6 — Forgetting to set `idle_timeout` on the ALB.** WS will work for 60 s and then "mysteriously disconnect". This is the canonical WS-on-ALB bug; it must be in the workshop's pitfalls section.

**AP7 — Health check path that hits Sonic.** Real story across many AWS+ML samples — well-meaning health check ends up costing $X/month and causing throttling.

---

## 11. Scaling Considerations

| Scale | Adjustment |
|-------|------------|
| 1–5 concurrent (workshop demo) | 1 Fargate task, 1 ALB, 2 AZ public + private. As designed. |
| 5–50 concurrent (full classroom) | Service auto-scales to 4 tasks. Verify each task can hold ~10–15 sessions in load test. Increase max if needed. |
| 50–500 concurrent (out of v1 scope) | Move widget to CloudFront (cache static assets), shard ALB by region, request Bedrock concurrency quota increase, add HA NAT (or PrivateLink-only egress), DynamoDB for session metadata. |
| 500+ concurrent | Out of scope. Different product. |

**First bottleneck:** Bedrock concurrent stream quota per account/region (default is conservative — request a raise before any real demo day). **Second bottleneck:** Fargate task vCPU on the Pipecat side once sessions/task exceeds ~20.

---

## 12. Open Questions / Spike Items

1. **Bedrock bidi over PrivateLink in `ap-northeast-1`** (§3.2). Confirm with a smoke test in dev. If unsupported, fall back to NAT for `bedrock-runtime` only. Hours, not days, to validate.
2. **Pipecat task capacity ceiling** for shared-pipeline model. Need a synthetic load test (5, 10, 20 concurrent sessions) on `0.5 vCPU / 1 GB` to set autoscaling thresholds. Cheap to run; do it before workshop dry-run.
3. **Custom domain + ACM** workshop UX. Some learners may not own a domain. Consider providing a fallback path that uses the ALB DNS + a self-signed warning page, so they can finish even without a domain. (Workshop concern, not architecture.)
4. **Widget audio reconnection logic.** When Pipecat's session-continuation seam happens (every 8 min), is the audio dropout < 1 second as advertised? Validate; if not, document the seam in workshop and consider adding "thinking…" filler.

---

## 13. Sources

- AWS blog — Building intelligent AI voice agents with Pipecat and Amazon Bedrock — Part 1 — https://aws.amazon.com/blogs/machine-learning/building-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock-part-1/ (HIGH — primary blueprint)
- AWS blog — Part 2 (Nova Sonic unified) — https://aws.amazon.com/blogs/machine-learning/building-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock-part-2/ (HIGH — Sonic-specific guidance)
- AWS samples repo — `aws-samples/build-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock` — https://github.com/aws-samples/build-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock (HIGH — confirms ECS Fargate + S3+CloudFront topology used in AWS's own CDK reference)
- Pipecat — AWS Nova Sonic service docs — https://docs.pipecat.ai/server/services/s2s/aws (HIGH — session continuation, tools, audio formats)
- Pipecat — `aws_nova_sonic` API reference — https://reference-server.pipecat.ai/en/stable/api/pipecat.services.aws_nova_sonic.html (HIGH)
- Pipecat — FastAPI WebSocket transport — https://docs.pipecat.ai/server/services/transport/fastapi-websocket (HIGH — exact transport hera will use)
- AWS docs — InvokeModelWithBidirectionalStream — https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_InvokeModelWithBidirectionalStream.html (HIGH)
- AWS docs — Nova Sonic getting started / bidirectional streaming — https://docs.aws.amazon.com/nova/latest/userguide/speech-bidirection.html (HIGH)
- AWS docs — Bedrock VPC interface endpoints — https://docs.aws.amazon.com/bedrock/latest/userguide/vpc-interface-endpoints.html (HIGH — confirms `bedrock-runtime` PrivateLink endpoint exists; bidi caveat is MEDIUM)
- AWS docs — S3 Vectors with Bedrock Knowledge Bases — https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-bedrock-kb.html (HIGH)
- AWS blog — Cost-effective RAG with Bedrock KB + S3 Vectors — https://aws.amazon.com/blogs/machine-learning/building-cost-effective-rag-applications-with-amazon-bedrock-knowledge-bases-and-amazon-s3-vectors/ (HIGH)
- Amazon Nova pricing — https://aws.amazon.com/nova/pricing/ (HIGH — for Sonic per-token rates; verify at deploy time)
- WebSocket.org — AWS ALB WebSocket configuration — https://websocket.org/guides/infrastructure/aws/alb/ (MEDIUM — community source; corroborates AWS docs on idle timeout + sticky sessions)
- Tech Holding — WebSocket on AWS with ALB and ECS — https://techholding.co/blog/aws-websocket-alb-ecs (MEDIUM — corroborating)
- Subaud.io — Building a WebSocket Server with Fargate and CDK — https://subaud.io/blog/building-a-websocket-server-with-fargate-and-cdk/ (MEDIUM — confirms target group + sticky pattern)

---

*Architecture research for: AWS-native voice AI agent (web channel only) workshop & demo system*
*Researched: 2026-05-04*
