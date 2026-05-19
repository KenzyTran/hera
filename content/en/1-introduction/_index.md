---
title: "Introduction"
date: 2025-01-01
weight: 1
chapter: true
pre: "<b>1. </b>"
---

## What is voice AI

A voice agent is an AI service that runs as a real-time bidirectional audio stream: the user speaks into a microphone, audio is streamed up to a speech-to-speech model, the model responds with audio, the browser plays it back — all in under a second. Hera uses Amazon Nova 2 Sonic, an Amazon Bedrock speech-to-speech foundation model running in `ap-northeast-1`, with native tool-use that can call a Bedrock Knowledge Base inside the same stream.

## Why this stack

- **Amazon Nova 2 Sonic on Bedrock**: pure-AWS, low latency from Vietnam, per-minute billing, native tool-use for Knowledge Base lookup.
- **Amazon Bedrock AgentCore Runtime**: managed runtime, no VPC / ALB / NAT to debug, ARM64 image, credential injection via IMDSv2 — significantly simpler for workshop scope.
- **Pipecat 1.1.0**: the standard orchestrator for voice loops, ships `AWSNovaSonicLLMService`, transparently handles the 8-min Sonic stream cap (rotates the stream ~120s before the cap).
- **S3 Vectors + Titan v2**: cost-driven, around $0.10/month for a small catalog vs $200-400/month with OpenSearch Serverless.
- **Terraform `~> 6.27` + CDK Python for AgentCore Runtime**: hybrid IaC (D-24). Terraform 6.x already supports native `s3_vectors_storage_configuration` on `aws_bedrockagent_knowledge_base`, but AgentCore Runtime does not yet have full first-party Terraform resource coverage — CDK Python fills that gap for exactly one stack.

## High-level architecture

![Hera architecture — Pipecat on AgentCore Runtime + Bedrock Nova 2 Sonic + KB on S3 Vectors](/images/architecture-aws.png)

The browser captures 16 kHz Int16 mono audio via AudioWorklet. CloudFront serves the static widget (HTML/JS/CSS) from S3. The presigner Lambda mints a short-lived (300s) SigV4-signed WSS URL because browsers cannot sign WebSocket upgrades themselves. AgentCore Runtime runs the Pipecat container, opens a bidirectional stream to Nova 2 Sonic, calls the Bedrock Knowledge Base via `bedrock:Retrieve` when Sonic emits a tool_use, and streams 24 kHz audio back to the browser.

## Voice loop end-to-end

1. **User** clicks "record" on the widget and speaks.
2. **Browser** → **Presigner Lambda**: `POST /` to mint a SigV4-signed WSS URL.
3. **Presigner Lambda** → **Browser**: returns `{"url": "wss://..."}` (TTL 300 s).
4. **Browser** → **AgentCore Runtime**: WSS upgrade with that URL, then streams 16 kHz Int16 audio frames.
5. **AgentCore Runtime (Pipecat)** → **Nova 2 Sonic**: opens a bidirectional stream and forwards the audio.
6. **Sonic** → **Runtime**: emits `tool_use(lookup_product)` when it detects a product question.
7. **Runtime** → **Bedrock KB** (`bedrock-agent-runtime.retrieve`): queries top-3 chunks from S3 Vectors.
8. **KB** → **Runtime**: returns chunks (text + score + source).
9. **Runtime** → **Sonic**: sends `tool_result` back into the stream.
10. **Sonic** → **Runtime**: streams the 24 kHz audio reply.
11. **Runtime** → **Browser**: forwards audio frames.
12. **Browser** → **User**: plays the audio, ending one turn (~3 s end-to-end).

## Default region

The workshop default is `ap-northeast-1` (Tokyo) for every snippet, every screenshot, every `--region` flag. Reason: best latency to Vietnam, and Nova 2 Sonic + AgentCore Runtime + Bedrock Knowledge Base + S3 Vectors are all available there. If you live in another region, Nova 2 Sonic + AgentCore are also available in `us-east-1`, `us-west-2`, and `eu-north-1`. Switch by editing the `region` variable in `infra/envs/prod/terraform.tfvars` (Section 3.1 walks through this).

## Prerequisites before you start

### AWS Account

- You need an AWS Account. If you don't have one, [create one here](https://aws.amazon.com/free/).
- Use an IAM user with Administrator access (workshop scope, not production); do not use the root account.

### Required knowledge

- Basic understanding of AWS Console + IAM.
- Basic networking (VPC, subnet) and Terraform / Docker familiarity.

### Core tools

| Tool | Description |
|------|-------------|
| AWS CLI v2 | Command line interface |
| Terraform >= 1.9 | IaC primary |
| uv | Python package manager (NOT pip) |
| Docker Desktop | Multi-arch buildx |
| jq | JSON parser |
| Browser | Chrome/Firefox/Safari (HTTPS required for microphone) |

Chapter 2 Preparation has detailed paste-block installers per platform.

{{% notice warning %}}
**Cost:** This workshop may incur a small charge (~$2-5 USD for a 2-hour session). Run Chapter 4 Cleanup right after the session to tear back down to $0.
{{% /notice %}}

## Workshop conventions

- Source snippets carry a footer line `*Source: <repo-relative-path> — Phase X Plan XX-XX*` (D-42). If drift happens, grep the footer and re-paste from the source file.
- AWS Console screenshots are annotated (red box + arrow + label) at the choke points where the UI is unavoidable (D-44 — Bedrock model access, Billing Alerts toggle, AgentCore quota request).
- Chatbot speech is English (Sonic is strongest in en); workshop documentation is bilingual vi/en.
- Chapter 4 Cleanup is mandatory — if you don't tear down, the AgentCore Runtime + Bedrock KB keep accruing per-hour-active charges.

{{% notice warning %}}
**Bilingual parity (DOC-12):** every PR that edits workshop content must commit
vi+en together. CI runs `bin/check-i18n-parity.sh` before the Hugo build — if
`content/vi` and `content/en` diverge in `_index.md` count, the build fails.
This convention prevents a "Vietnamese-only / English-not-yet-translated"
state shipping to production.

*Source: bin/check-i18n-parity.sh — Phase 5 Plan 05-01*
{{% /notice %}}

## References

- AWS blog: [Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/) — Hera's blueprint architecture.
- Reference repo: [aws-samples/sample-nova-sonic-websocket-agentcore](https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore) — bidirectional streaming + WebSocket + auth + tool use.
- Hugo theme: [hugo-theme-learn](https://learn.netlify.app/en/) (deprecated upstream but still functional for v1; migration to relearn deferred to v2).
