# Stack Research — Hera AWS Voice Agent Workshop

**Domain:** AWS-native real-time voice AI agent (speech-to-speech) + Hugo workshop docs
**Researched:** 2026-05-04
**Overall confidence:** HIGH (locked decisions verified against current docs; supporting libs verified via Context7 / official AWS docs / Terraform Registry)

---

## TL;DR

Hera v1 is a Pipecat 1.1.0 (Python 3.12) container on ECS Fargate (x86_64, 1 vCPU / 2 GB starter) behind an Application Load Balancer with TLS, talking to Amazon Nova 2 Sonic (`amazon.nova-2-sonic-v1:0`) over `InvokeModelWithBidirectionalStream`, with a Bedrock Knowledge Base backed by S3 Vectors (Titan Text Embeddings v2 @ 1024 dim) for the Apple product catalog. Browser widget is plain HTML/JS using `getUserMedia` + AudioWorklet at 16 kHz mono PCM over a binary WebSocket. IaC is Terraform with `hashicorp/aws` ≥ 6.27 (native S3 Vectors + Bedrock KB resources), state in S3 + DynamoDB. Workshop docs stay on the existing Hugo + hugo-theme-learn scaffold per project decision.

The **production region is `ap-northeast-1`** (Tokyo) — confirmed Nova 2 Sonic availability. **Dev region is `us-east-1`** — also confirmed. Both regions have Titan Embeddings v2 and S3 Vectors GA.

---

## Recommended Stack

### Core Technologies — Voice Loop

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Amazon Nova 2 Sonic** | model id `amazon.nova-2-sonic-v1:0` (launched 2025-12-02, lifecycle Active, no EOL) | Speech-to-speech foundation model: ASR + reasoning + tool-use + TTS in one bidirectional stream | Locked. Single-model S2S beats cascaded ASR→LLM→TTS on latency; tool-use is native; same `InvokeModelWithBidirectionalStream` API as Sonic v1 so Pipecat adapter works unchanged; only AWS-native S2S option that fits "pure-AWS" constraint. 1M-token context, 64K output. |
| **Pipecat** | `pipecat-ai==1.1.0` (released 2026-04-27) with extras `[aws-nova-sonic,silero,websocket]` | Python orchestration framework: pipeline of `transport.input() → context_aggregator → AWSNovaSonicLLMService → transport.output()` | Locked. Has first-party `AWSNovaSonicLLMService` (`pipecat.services.aws.nova_sonic`) that handles the bidirectional event protocol, tool schema conversion, VAD, and context. Used in AWS's own reference architecture (`aws-samples/build-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock`). Active commits, 1.x line stable. |
| **Python** | 3.12 (3.12.x, latest patch) | Runtime for Pipecat container | Pipecat 1.1.0 requires `>=3.11`. AWS reference repo pins `>=3.12`. Use 3.12 for asyncio improvements + matching AWS samples. Avoid 3.13 in v1 — some C-extension wheels (audio libs) lag. |
| **uv** | latest (≥ 0.4) | Python package manager + lockfile | User CLAUDE.md mandates `uv`. Reproducible builds (`uv.lock`), 10–100x faster than pip in CI/Docker. `uv add "pipecat-ai[aws-nova-sonic,silero,websocket]"`. |
| **Silero VAD** | bundled via `pipecat-ai[silero]` | Voice activity detection — speech start/end | Standard for Pipecat. Nova Sonic also has its own VAD but Silero on the input side reduces wake-burst sent to Bedrock = lower token cost. Reference AWS blog uses it explicitly. |
| **boto3** | ≥ 1.35 (whichever ships with Pipecat 1.1) | AWS SDK for Bedrock Runtime + Bedrock Agent Runtime (KB Retrieve) | Required by Pipecat's `AWSNovaSonicLLMService`. Also used directly for the KB `Retrieve` tool implementation. |

### Core Technologies — Knowledge Base & Vectors

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Amazon Bedrock Knowledge Base** | Service (no version) — managed | Fully-managed RAG ingestion + retrieval over S3 source docs | Locked. Saves writing chunker, embedder, indexer, syncer. Direct integration with S3 Vectors. `Retrieve` API returns chunks with citations — ideal as a Pipecat tool. |
| **Amazon S3 Vectors** | GA 2025-12-02 | Vector store backing the KB | Locked (cost). Pay-as-you-go: $0.06/GB-month storage + $2.50/M queries + $0.20/GB PUT. For a workshop catalog (≤ a few thousand vectors) this is **pennies/month** vs OpenSearch Serverless ~$200–400/month minimum. Sub-second cold, ~100ms warm latency — fine for non-streaming tool calls. |
| **Titan Text Embeddings v2** | model id `amazon.titan-embed-text-v2:0` | Embeds chunks into 1024-dim float vectors | Recommended. Available in **both** ap-northeast-1 and us-east-1 (Cohere Embed v3 is also available in both, but Titan is cheaper at $0.00002 / 1K tokens vs $0.0001 / 1K for Cohere — 5× cost difference). 8,192 token context, supports 256/512/1024 dims (use 1024 for v1 — accuracy first; switch to 256 later if storage cost matters). Floating-point only with S3 Vectors (binary not supported). |
| **Bedrock KB chunking** | Default fixed-size chunking (300 tokens, 20% overlap) | Auto-chunk S3 source docs | Default works for product catalog Markdown. Avoid hierarchical chunking with S3 Vectors — parent-child relationships go into non-filterable metadata and can blow the 1 KB / 35-key metadata cap. |

### Core Technologies — Compute & Networking

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **ECS Fargate** | Platform `LATEST` (currently 1.4.0+ Linux), x86_64 | Serverless container compute for Pipecat | Locked. Pipecat sessions are long-running stateful WebSocket processes — Lambda 15-min cap and 6 MB payload kill it. Fargate is simpler than EKS for a workshop; no node management. **x86_64 over ARM** for v1 — some audio C-extensions (silero ONNX runtime) have less mature Graviton wheels; ARM saves ~20% but workshop simplicity wins. |
| **Fargate task size (starter)** | 1 vCPU / 2 GB (one Pipecat session per task, scale tasks horizontally) | Per-session compute | One Sonic session is light on CPU (audio framing + bedrock streaming) but Silero ONNX needs ~500 MB and Python overhead is real. 1 vCPU / 2 GB = $0.04048×1 + $0.004445×2 ≈ **$0.049/hour** per task in us-east-1; ap-northeast-1 is ~10–15% higher. Workshop students should expect ~$0.06/hr / running task in Tokyo. |
| **Application Load Balancer (ALB)** | aws_lb type `application` | Public TLS ingress, WebSocket upgrade, path routing | ALB over NLB: ALB does TLS termination with ACM, native WS upgrade (HTTP/1.1 `Upgrade: websocket`), path-based routing for `/health` vs `/ws`, and integrates with Cognito/WAF later. NLB is needed only for raw TCP or extreme connection counts — overkill for a workshop. WebSocket is **inherently sticky** at ALB once the 101 upgrade completes (no cookie needed); enable target-group stickiness only if you also expose stateless HTTP routes. |
| **AWS Certificate Manager (ACM)** | Service | Free TLS certs for the ALB | Required for `wss://`. Free, auto-renew, DNS-validated via Route 53. |
| **Route 53** | Service | DNS for ALB hostname | Optional in v1 (can use the ALB's `*.elb.amazonaws.com` for raw demo) but recommended for workshop polish — costs ~$0.50/hosted-zone/month. |
| **VPC** | aws_vpc | Network isolation | 2 public subnets (ALB) + 2 private subnets (Fargate) across 2 AZs. **Skip NAT Gateway in v1** — use VPC Interface Endpoints for `bedrock-runtime`, `bedrock-agent-runtime`, `s3`, `logs`, `ecr.api`, `ecr.dkr`, `secretsmanager`. NAT is $32+/month per AZ; endpoints are $7.20/endpoint/month and far cheaper at workshop scale. Endpoint service name: `com.amazonaws.<region>.bedrock-runtime` (with private DNS enabled). |
| **CloudWatch Logs** | Log group `/ecs/hera-pipecat`, retention 7 days (workshop) | Container stdout + Pipecat logs | 7-day retention keeps cost trivial. Long retention = students forget and pay for it. |
| **CloudWatch Metrics** | Default Bedrock + ECS metrics | Built-in `ModelInvocations`, `InvocationLatency` from Bedrock; `CPUUtilization`, `RunningTaskCount` from ECS | Alarms: KB retrieval latency p95 > 1s, Bedrock 5xx rate > 1%, Fargate task count = 0. |

### Core Technologies — Browser Widget

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Vanilla HTML/JS** | n/a | Widget UI | No framework needed. ~300 LOC: one button, one status div, one `<audio>` element for playback. Workshop value is the loop, not React. |
| **`navigator.mediaDevices.getUserMedia`** | Browser API (current Chrome/Edge/Firefox/Safari) | Capture mic | Standard. Request `{ audio: { sampleRate: 16000, channelCount: 1, echoCancellation: true, noiseSuppression: true } }`. |
| **Web Audio API + AudioWorklet** | Browser API | Resample/frame mic audio to 16-bit PCM @ 16 kHz mono | AudioWorklet runs on the audio thread (low jitter), gives 128-sample chunks, no main-thread blocking. Convert Float32 → Int16 in the processor, post via `MessagePort` to main thread, send as **binary WebSocket frames** (ArrayBuffer) — 33% smaller than base64 JSON. Don't use deprecated `ScriptProcessorNode`. |
| **Native WebSocket** | Browser API (`new WebSocket(wssUrl)`) | Bidirectional audio transport | No socket.io / sockjs needed — Pipecat speaks raw WebSocket. Use `binaryType = 'arraybuffer'`. |
| **Audio playback** | `AudioContext.decodeAudioData` or streaming via `AudioBufferSourceNode` queue | Play 24 kHz PCM coming back from Sonic | Sonic outputs **24 kHz** mono 16-bit PCM (Pipecat default). Browser AudioContext can mix at 48 kHz natively — let it upsample. |

### Core Technologies — Pipecat Frame Serialization

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **`WebsocketServerTransport` (Pipecat)** | bundled | Server-side WS transport, browser-friendly | Use this, **not** `FastAPIWebsocketTransport` — that one is documented as Twilio-shaped (8 kHz, Twilio serializer). `WebsocketServerTransport` runs its own asyncio WS server, supports ProtobufFrameSerializer, and handles single-client-per-connection (each Fargate task = one session = one client). |
| **`ProtobufFrameSerializer`** | bundled | Encode Pipecat `Frame` objects on the wire | Pipecat's default cross-language serializer. The browser widget sends raw PCM binary frames (Pipecat parses them as audio frames automatically when no protobuf header is present), and Pipecat sends back protobuf-wrapped audio frames the widget unwraps. Alternative: write a tiny custom serializer that does raw-PCM both ways — lower workshop complexity. **Recommendation: raw PCM both directions** (no protobuf in v1) — keep the widget code minimal. |

### Core Technologies — Infrastructure-as-Code

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Terraform** | CLI ≥ 1.9 | IaC | Locked. |
| **`hashicorp/aws` provider** | `~> 6.27` (latest as of research is 6.42, released 2026-04-22) | All AWS resources | **6.27 is the floor** — that's where `aws_bedrockagent_knowledge_base` gained the `s3_vectors_storage_configuration` block (resolved issue #43438 / PR #45465). Earlier versions only support OpenSearch Serverless / Pinecone / RDS storage and would force CLI/null_resource workarounds. Pin `~> 6.27` to allow patch+minor upgrades, lock major. |
| **`aws_s3vectors_vector_bucket`** | provider resource | S3 vector bucket | Native resource. Supports `force_destroy = true` (essential for workshop cleanup), `encryption_configuration { sse_type = "AES256" }`. |
| **`aws_s3vectors_index`** | provider resource | Vector index inside the bucket | Native resource with `dimension = 1024`, `distance_metric = "cosine"`, `data_type = "float32"`. |
| **`aws_bedrockagent_knowledge_base`** | provider resource | The KB tying it all together | Configure `storage_configuration { type = "S3_VECTORS", s3_vectors_configuration { ... } }` and `vector_knowledge_base_configuration { embedding_model_arn = "arn:aws:bedrock:<region>::foundation-model/amazon.titan-embed-text-v2:0" }`. |
| **State backend: S3 + DynamoDB** | n/a | Remote state w/ locking | S3 bucket with versioning + SSE-S3 + lifecycle rule for old versions; DynamoDB table `hera-tf-locks` with `LockID` PK, `BillingMode = PAY_PER_REQUEST`. **Workshop variant:** local state file is acceptable — document remote state as a "next step" so students aren't blocked on a chicken-and-egg bootstrap. |
| **Module structure** | n/a | Composability | `modules/network` (VPC, subnets, endpoints), `modules/knowledge_base` (S3 source bucket, vector bucket, index, KB, IAM role), `modules/pipecat_service` (ECR repo, ECS cluster, task def, service, ALB, target group, listener, ACM, IAM task/exec roles, log group). One root `main.tf` per environment (`envs/dev`, `envs/prod`). |
| **Tagging strategy** | n/a | Cost allocation + cleanup | Default tags via `provider` block: `Project = "hera"`, `Environment = var.environment`, `ManagedBy = "terraform"`, `Workshop = "fcj-voice-ai"`. Lets students filter Cost Explorer to verify zero charges after `terraform destroy`. |

### Core Technologies — Workshop Docs

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Hugo** | extended ≥ 0.140 | Static site generator | Already scaffolded per PROJECT.md. |
| **hugo-theme-learn** | git submodule (current pin) | Theme | **Locked by PROJECT.md "✓ existing"**. Note: upstream `matcornic/hugo-theme-learn` is officially deprecated; `mcshelby/hugo-theme-relearn` v9.0.3 (2026-01-01) is the maintained successor with same shortcodes and richer multilingual support. **For v1 do NOT swap themes** — that's scope creep against the locked decision. **Flag for v2**: a one-shot migration to `hugo-theme-relearn` is low-risk and unblocks future Hugo upgrades. See PITFALLS.md. |
| **GitHub Actions** | `actions/checkout@v4`, `peaceiris/actions-hugo@v3`, `peaceiris/actions-gh-pages@v4` | Build + deploy Hugo to GitHub Pages | Already scaffolded. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `loguru` | latest (Pipecat dep) | Structured logging | Pipecat ships with it; configure JSON sink to stdout for CloudWatch. |
| `python-dotenv` | latest | Local dev env loading | Local-only; in Fargate use Secrets Manager / Parameter Store via task-def `secrets`. |
| `opentelemetry-sdk` + `opentelemetry-exporter-otlp` | latest matching Pipecat | Distributed tracing | Optional v1 polish — Pipecat has `setup_tracing()` and decorators (`traced_llm`, `traced_tts`). Export to AWS X-Ray via the AWS Distro for OpenTelemetry (ADOT) sidecar in the Fargate task definition. |
| `pytest` + `pytest-asyncio` | latest | Tests for Pipecat tool functions | Unit-test the KB `Retrieve` tool with a mocked `bedrock-agent-runtime` client. |
| `ruff` | latest | Lint + format | Fast, replaces black + flake8 + isort. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **AWS CLI v2** | Manual KB sync, debugging, `aws bedrock list-foundation-models` to verify Sonic access | Workshop preparation step requires this. |
| **Docker** | Build the Pipecat image | Multi-stage: `python:3.12-slim` base, install via `uv`, copy app, `CMD ["uv", "run", "python", "-m", "hera.server"]`. Use `--platform=linux/amd64` if students are on Apple Silicon. |
| **`amazon/aws-cli` Docker image** | Bootstrap KB ingestion job in CI without installing AWS CLI on students' machines | Optional — for workshop, native AWS CLI is fine. |
| **Pre-commit hooks** | `terraform fmt`, `terraform validate`, `ruff check` | Standard hygiene. |

---

## Installation

```bash
# Pipecat container (Python side, managed via uv)
uv init hera-pipecat --python 3.12
uv add "pipecat-ai[aws-nova-sonic,silero,websocket]"
uv add boto3 loguru
uv add --dev pytest pytest-asyncio ruff

# Browser widget — no install. Vanilla HTML + JS in /widget/index.html.

# Terraform
# (no install command; pin in versions.tf)
# terraform { required_version = ">= 1.9" }
# required_providers { aws = { source = "hashicorp/aws", version = "~> 6.27" } }

# Hugo workshop docs — already scaffolded (existing repo state).
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| **Pipecat** | LiveKit Agents (Python) | LiveKit ships its own Nova 2 Sonic plugin and is excellent for WebRTC-first workloads. Choose it if v2 wants WebRTC over WebSocket; for v1 Pipecat is closer to the AWS reference architecture. |
| **Pipecat** | Custom asyncio + boto3 | If you want zero framework overhead and full control over the bidirectional stream event protocol. **Don't** — re-implementing event handling, VAD, tool dispatch, and context management is weeks of work and the workshop wants to teach the *concept*, not the plumbing. |
| **Nova 2 Sonic** | Cascade: Transcribe (ASR) → Nova Pro (LLM) → Polly (TTS) | If you need fine-grained control over each stage or features Sonic doesn't expose (custom voice cloning, very specific TTS prosody). Locked-out per project decision; cascade has higher latency (3+ round trips) than S2S. |
| **S3 Vectors** | OpenSearch Serverless | Locked-out per project. Use OSS only if you need hybrid keyword+vector search, > 100ms warm-cold acceptable, or ≥ 100M vectors. Min cost ~$200–400/month. |
| **S3 Vectors** | Aurora pgvector | Use if you already run Postgres for app data and want one DB. Higher fixed cost ($60+/month for smallest serverless v2). Not justified at workshop scale. |
| **S3 Vectors** | Pinecone, Weaviate Cloud | Out of "AWS-native" scope per project constraint. |
| **Titan Embeddings v2** | Cohere Embed Multilingual v3 | If catalog ever needs non-English semantic search (Vietnamese product descriptions). 5× more expensive but stronger multilingual recall. v1 is English-only chatbot, so Titan wins. |
| **ECS Fargate** | EKS + Karpenter | Use for very high concurrency (>1000 simultaneous Sonic sessions) where bin-packing matters. Workshop scope ≤ 10 concurrent students. EKS adds cluster + networking complexity that obscures the lesson. |
| **ECS Fargate** | EC2 ASG | Cheaper at sustained scale (~30% savings with Compute Savings Plans), but adds AMI/userdata/SSM management. Skip for workshop. |
| **ALB** | API Gateway WebSocket | API GW WS has 2-hour idle timeout cap and per-message overhead. Sonic sessions are commonly < 5 min so timeout isn't the blocker — billing is: API GW charges per message ($1.00 / 1M) and audio is many small frames. ALB is per-LCU which is cheaper for high-frame-rate audio. |
| **ALB** | NLB | Use NLB for very-high-connection counts (>50K) or when TLS termination must happen on the target. Adds complexity (separate TLS, no path routing). |
| **VPC Endpoints** | NAT Gateway | NAT is simpler (one route), but $32+/month per AZ standing charge dwarfs endpoint cost at workshop usage. Endpoints also keep Bedrock traffic off the public internet (security win for the docs to highlight). |
| **Vanilla JS widget** | React + a WebRTC SDK | Use if you have an existing app to embed into. For a workshop demo, vanilla JS keeps the build chain simple (no node_modules, no bundler) and the audio code visible in one file. |
| **`hashicorp/aws` provider** | `hashicorp/awscc` provider (CloudFormation-backed) | `awscc_s3vectors_vector_bucket` existed before the native `aws_*` resources merged. Now that 6.27+ has native support, use the native ones — better drift detection, faster plans. |
| **Terraform** | AWS CDK / SAM | Locked-out per project. CDK is great for TypeScript shops; Terraform fits "declarative, large community, easy to teach in workshop." |
| **hugo-theme-learn** | hugo-theme-relearn 9.x | Defer to v2 milestone. relearn is the actively maintained fork with bug fixes and Hugo-compat updates. Migration is mechanical (theme submodule swap, minor frontmatter tweaks) but out of v1 scope. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `amazon.nova-sonic-v1:0` (v1) | Per project context, EOL'd in 2026. Fewer features (manual assistant-response trigger), no polyglot voices, no async tool calls, no 8 kHz telephony optimization. | `amazon.nova-2-sonic-v1:0` |
| `FastAPIWebsocketTransport` for browser | Documented and audio-shaped for telephony (Twilio/Telnyx) at 8 kHz with provider-specific serializers. Works for browser but the defaults will mislead students. | `WebsocketServerTransport` from `pipecat.transports.websocket.server` |
| AWS Lambda for Pipecat | 15-min execution cap + Lambda Web Adapter cannot maintain a stateful WS session beyond timeout. Cold start kills first-syllable latency. | ECS Fargate |
| `ScriptProcessorNode` (browser) | Deprecated since 2014; runs on main thread, jitter under load. | `AudioWorklet` |
| Base64 audio in JSON over WebSocket | 33% bandwidth overhead, JSON parse cost on every chunk. | Binary WebSocket frames (ArrayBuffer) |
| OpenSearch Serverless for KB at workshop scale | $200–400/month minimum. Workshop catalog has < 100 vectors. | S3 Vectors |
| Hierarchical chunking with S3 Vectors | Parent-child relationship goes into non-filterable metadata; easy to exceed the 1 KB / 35-key per-vector cap. Causes silent ingestion failures. | Default fixed-size chunking (300 tokens, 20% overlap) |
| Binary Titan v2 embeddings with S3 Vectors | S3 Vectors integration with Bedrock KB requires **floating-point** vectors — binary not supported (per S3 Vectors KB integration limitations doc). | 1024-dim float32 |
| NAT Gateway in v1 workshop VPC | $32–35/month per AZ per gateway, students forget to destroy it, surprise bill on Monday. | VPC Interface Endpoints |
| `actions/checkout@v3` and older | Out of support. | `actions/checkout@v4` |
| ARM Fargate (Graviton) for v1 | Saves 20% but Silero ONNX wheels and some Pipecat audio deps have less mature ARM support; debugging architecture issues mid-workshop is a nightmare. | x86_64 (`runtime_platform { cpu_architecture = "X86_64" }`) |
| Long-lived AWS access keys baked into the container | Security antipattern; workshop should teach IAM roles. | ECS Task Role with `bedrock:InvokeModelWithBidirectionalStream` + `bedrock:InvokeModel` (for embeddings during ingestion) + `bedrock-agent-runtime:Retrieve` scoped to the KB ARN |
| Public S3 source bucket for KB | Data exfiltration risk + tutorial gets cargo-culted into prod. | Private bucket, read access via the Bedrock KB service role only |
| `aws_iam_role_policy` inline in workshop modules | Hard to audit; students copy-paste. | `aws_iam_policy` + `aws_iam_role_policy_attachment` separation, with the JSON in a `templatefile()` so the doc shows the exact policy. |

---

## Stack Patterns by Variant

**If region must be `us-east-1` (dev):**
- All locked components available. Slightly cheaper Fargate (~10% lower than Tokyo).
- Use this for the workshop's "first deploy" because students often run from US laptops and round-trip to us-east-1 is acceptable.

**If region must be `ap-northeast-1` (Tokyo prod):**
- All locked components available (Sonic, Titan v2, S3 Vectors, KB).
- Best end-user latency for VN/SEA students.
- Fargate ~10–15% pricier than us-east-1; budget accordingly in the workshop cost section.

**If region is anything else:**
- Verify Sonic regional availability first. Sonic is **only** in us-east-1, us-west-2, eu-north-1, ap-northeast-1 as of 2025-12-02.
- ap-southeast-1 (Singapore) and ap-southeast-2 (Sydney) **do not** have Sonic — would force cross-region calls and break private-VPC-endpoint design.

**If browser is replaced by Twilio Voice (v2):**
- Swap `WebsocketServerTransport` → `FastAPIWebsocketTransport` with `TwilioFrameSerializer`.
- Audio drops to 8 kHz μ-law (Twilio Media Streams native).
- Add Twilio account SID + auth token in Secrets Manager; webhook URL points to the Pipecat ALB.
- KB, Sonic, Fargate, Terraform layers unchanged — that's the v1 architecture's selling point.

**If concurrency target rises above ~50 sessions:**
- Move from "1 task per session" to "1 task hosts N sessions" (requires Pipecat process pool, more complex).
- Or: keep 1-session-per-task and scale ECS service via target tracking on `RunningTaskCount`. ALB will distribute new connections to fresh tasks; existing WS connections stay sticky on their original task.
- Re-evaluate ARM Fargate for cost savings.

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `pipecat-ai==1.1.0` | Python 3.11–3.13; `boto3>=1.35` | Pin minor `~=1.1` until Pipecat 1.2 ships and you can re-test. |
| `pipecat-ai[aws-nova-sonic]` | `aws-sdk` async libs (aiobotocore via `aioboto3` style) bundled in extra | Don't mix with manually-pinned conflicting `boto3` versions. |
| `hashicorp/aws ~> 6.27` | Terraform CLI ≥ 1.9 | Earlier provider versions lack `s3_vectors_storage_configuration` for KB. |
| `hashicorp/aws 6.x` (any) | `terraform-aws-modules/vpc/aws ~> 5.x` | The community VPC module's 5.x major matches AWS provider 6.x. |
| Bedrock KB + S3 Vectors | Region must support **both** S3 Vectors AND the chosen embedding model AND Sonic | All four locked regions (us-east-1, us-west-2, eu-north-1, ap-northeast-1) qualify. |
| Titan Embeddings v2 (1024 dim) | S3 Vectors index with `dimension = 1024`, `data_type = "float32"` | Binary type unsupported with S3 Vectors+KB. |
| `WebsocketServerTransport` | `ProtobufFrameSerializer` OR raw PCM bytes | One client per server instance — fits the 1-task-per-session deployment. |
| ACM cert | Must be in **same region** as ALB | Cross-region certs only work for CloudFront. |
| ECS Fargate platform `LATEST` | x86_64 + Linux | Don't pin platform version explicitly unless you hit a known bug; `LATEST` gets free perf bumps. |
| Hugo extended | hugo-theme-learn (existing pin) | Submodule pin is the source of truth — don't bump theme in v1. |

---

## Cost Notes (workshop-relevant — students need to budget)

These are rough order-of-magnitude figures. Always verify with the AWS Pricing Calculator. All in USD.

**Fixed monthly cost while resources exist (idle, no conversation):**
- Fargate task **stopped**: $0
- ALB: $0.0225/hour idle + LCU ≈ **$17/month** standing
- VPC Interface Endpoints (×7 endpoints × 2 AZ × $0.01/hr ≈ ): ~**$100/month** if all kept up. **Recommendation for workshop:** create endpoints in **only 1 AZ** for v1 (~$50/month) or use NAT in single AZ (~$32/month + $0.045/GB) — both cheaper than full HA.
- S3 Vectors: $0.06/GB-month — for ~100 product vectors @ 1024 dim float32 (~4 KB each) = 400 KB, **< $0.01/month** storage.
- S3 source bucket + Terraform state bucket: pennies.
- Route 53 zone (optional): $0.50/month
- CloudWatch logs (7-day retention, low volume): pennies.

**Per-conversation cost (one student, 5-minute chat):**
- Nova 2 Sonic at ~$0.017/minute combined input+output speech tokens × 5 min ≈ **$0.085/conversation**
- Bedrock KB Retrieve calls: 5 calls × very small fee (rolled into KB pricing — embedding the query @ Titan v2 ~$0.00002/1K tokens, plus S3 Vectors query at $2.50/M = negligible)
- Fargate task running 10 minutes: 1 vCPU + 2 GB ≈ **$0.008**
- ALB LCU: rounding error
- **Total ≈ $0.10/conversation**

**One-time KB ingestion cost (Apple catalog, ~10 product Markdown files):**
- Titan v2 embedding ~5K tokens @ $0.00002 / 1K = **$0.0001** total. Free at workshop scale.

**Workshop guidance to put in docs:**
- "Run-through cost: < $1 if you complete in one sitting and `terraform destroy` afterward."
- "Idle cost if you forget the ALB and endpoints up overnight: ~$2/day. Set a Budget alarm at $5."
- "OpenSearch Serverless alternative would have cost ~$10/day instead — that's why we use S3 Vectors."

---

## Confidence Assessment

| Claim | Confidence | Source |
|-------|------------|--------|
| Nova 2 Sonic model id `amazon.nova-2-sonic-v1:0` | HIGH | AWS Bedrock model card (current docs page fetched 2026-05-04) |
| Nova 2 Sonic available in us-east-1, us-west-2, eu-north-1, ap-northeast-1 | HIGH | AWS Bedrock model card regional availability table |
| Pipecat 1.1.0 released 2026-04-27, Python ≥ 3.11 | HIGH | PyPI fetch + Context7 |
| Pipecat `AWSNovaSonicLLMService` ships with `voice` (matthew/tiffany/amy), `region`, tool support | HIGH | Pipecat docs site + Context7 adapter docs |
| Pipecat default audio rates 16 kHz in / 24 kHz out | HIGH | Pipecat `StartFrame` defaults via Context7 |
| S3 Vectors GA 2025-12-02, 14 regions, 2B vectors/index | HIGH | AWS What's New announcement |
| S3 Vectors pricing ($0.06/GB-month, $0.20/GB PUT, $2.50/M queries + tiered TB charge) | HIGH | AWS S3 pricing page |
| S3 Vectors + Bedrock KB requires float32, 1 KB metadata, 35 keys, no hybrid search | HIGH | AWS S3 Vectors KB integration docs |
| Titan Embeddings v2 model id `amazon.titan-embed-text-v2:0`, 256/512/1024 dim, $0.00002 / 1K tokens | HIGH | AWS Bedrock KB supported embeddings + Bedrock pricing |
| Titan v2 available in ap-northeast-1 + us-east-1 | HIGH | Bedrock KB supported embeddings region table |
| Cohere Embed v3 priced at $0.0001 / 1K tokens (5× Titan) | MEDIUM | AWS Bedrock pricing page (verified) |
| `hashicorp/aws ~> 6.27` introduced `s3_vectors_storage_configuration` for KB | MEDIUM-HIGH | GitHub issue #43438 closed via PR #45465, milestone v6.27.0; resource pages exist on registry |
| `aws_s3vectors_vector_bucket` and `aws_s3vectors_index` are native Terraform resources | HIGH | Terraform registry resource pages confirmed |
| Fargate us-east-1 pricing $0.04048/vCPU-hr + $0.004445/GB-hr | HIGH | AWS Fargate pricing + multiple pricing trackers |
| ALB natively handles WebSocket; sticky once 101 upgrade completes | HIGH | AWS ELB sticky-session docs |
| Bedrock VPC endpoint service name `com.amazonaws.<region>.bedrock-runtime` | HIGH | AWS Bedrock VPC interface endpoints doc |
| hugo-theme-learn deprecated; hugo-theme-relearn 9.0.3 (2026-01-01) is successor | HIGH | matcornic/hugo-theme-learn README + mcshelby/hugo-theme-relearn release page |
| Nova Sonic pricing $0.0034/1K input speech tokens, $0.0136/1K output (~$0.017/min) | MEDIUM | Multiple secondary sources (Medium/CostBench/CloudThat); not directly listed on AWS Bedrock pricing HTML page (may be in dynamic pricing widget). Verify in AWS Calculator before publishing workshop cost section. |
| Browser AudioWorklet @ 16 kHz with binary WS frames is the standard pattern | HIGH | web.dev media patterns + AWS Transcribe streaming sample blog + multiple production references |

---

## Sources

### Authoritative (HIGH confidence)
- AWS Bedrock model card — Nova 2 Sonic: https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-2-sonic.html
- AWS Bedrock InvokeModelWithBidirectionalStream API: https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_InvokeModelWithBidirectionalStream.html
- AWS announcement — Nova 2 Sonic launch: https://aws.amazon.com/blogs/aws/introducing-amazon-nova-2-sonic-next-generation-speech-to-speech-model-for-conversational-ai/
- AWS announcement — S3 Vectors GA: https://aws.amazon.com/about-aws/whats-new/2025/12/amazon-s3-vectors-generally-available/
- AWS docs — S3 Vectors with Bedrock KB integration + limitations: https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-bedrock-kb.html
- AWS docs — Bedrock KB supported embedding models: https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base-supported.html
- AWS docs — Bedrock VPC interface endpoints: https://docs.aws.amazon.com/bedrock/latest/userguide/vpc-interface-endpoints.html
- AWS blog — Building cost-effective RAG with KB + S3 Vectors: https://aws.amazon.com/blogs/machine-learning/building-cost-effective-rag-applications-with-amazon-bedrock-knowledge-bases-and-amazon-s3-vectors/
- AWS reference — Pipecat + Bedrock voice agents: https://aws.amazon.com/blogs/machine-learning/building-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock-part-1/
- AWS samples repo: https://github.com/aws-samples/build-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock
- AWS samples — Nova 2 Sonic S2S: https://github.com/aws-samples/amazon-nova-samples/tree/main/speech-to-speech/amazon-nova-2-sonic
- Pipecat docs — AWS Nova Sonic service: https://docs.pipecat.ai/server/services/s2s/aws
- Pipecat docs — WebSocket Server Transport: https://docs.pipecat.ai/server/services/transport/websocket-server
- Pipecat PyPI: https://pypi.org/project/pipecat-ai/
- Pipecat repo: https://github.com/pipecat-ai/pipecat
- Context7 library `/pipecat-ai/pipecat` — `AWSNovaSonicLLMService`, `WebsocketServerTransport`, `TransportParams`, `setup_tracing`, `traced_llm/tts/stt` decorators
- Context7 library `/pipecat-ai/docs` — adapter and service signatures
- AWS ELB sticky sessions docs: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/sticky-sessions.html
- Terraform AWS provider 6.0 GA: https://www.hashicorp.com/en/blog/terraform-aws-provider-6-0-now-generally-available
- Terraform `aws_s3vectors_vector_bucket`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3vectors_vector_bucket
- Terraform `aws_bedrockagent_knowledge_base`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_knowledge_base
- GitHub issue #43438 — S3 Vectors in Bedrock KB (terraform-provider-aws): https://github.com/hashicorp/terraform-provider-aws/issues/43438
- AWS Fargate pricing: https://aws.amazon.com/fargate/pricing/
- AWS Bedrock pricing: https://aws.amazon.com/bedrock/pricing/
- Hugo Relearn theme: https://github.com/McShelby/hugo-theme-relearn
- Hugo Learn theme (deprecated): https://github.com/matcornic/hugo-theme-learn

### Secondary / verification (MEDIUM confidence)
- Nova Sonic per-minute pricing references: https://costbench.com/software/llm-api-providers/amazon-bedrock/, https://medium.com/@sid.rampally/build-real-time-voice-ai-apps-with-amazon-nova-sonic-on-bedrock-ea8c56248760
- Fargate 2026 pricing: https://leanopstech.com/blog/aws-ecs-fargate-pricing-2026/
- Browser PCM streaming patterns: https://web.dev/patterns/media/microphone-process, https://aws.amazon.com/blogs/machine-learning/stream-multi-channel-audio-to-amazon-transcribe-using-the-web-audio-api/

---

*Stack research for: AWS-native voice agent (Pipecat + Nova 2 Sonic + Bedrock KB on S3 Vectors, ECS Fargate, Terraform)*
*Researched: 2026-05-04*
