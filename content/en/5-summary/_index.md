---
title: "Summary"
date: 2025-01-01
weight: 5
chapter: true
pre: "<b>5. </b>"
---

# Workshop Summary

Congratulations — you just deployed a voice chatbot to your own AWS account and talked to it through a browser. This chapter wraps up what you built, the real-world cost ballpark, and the v2 expansion roadmap.

## What you built

- Apple product catalog ingested into a Bedrock Knowledge Base on the S3 Vectors backend with Titan Text Embeddings v2 (1024-dim, float32, cosine).
- Pipecat 1.1.0 voice agent (Python 3.12) running locally + as a multi-arch container (linux/arm64, linux/amd64) + deployed to Amazon Bedrock AgentCore Runtime in `ap-northeast-1`.
- Web widget HTML/JS deployed to S3+CloudFront with a presigner Lambda Function URL bridging SigV4 WebSocket auth (browsers cannot sign WSS upgrades themselves).
- A CloudWatch dashboard `hera-prod` with 5 panels + 2 operational alarms + 1 billing alarm cross-region (the `us-east-1` AWS/Billing constraint).
- Cleanup runbook verified by `bin/cleanup-verify.sh` (19 read-only checks for $0 ongoing cost).

## Cost recap (D-54)

**Total for a 2-hour session with cleanup per Chapter 4: ballpark `~$2-5 USD`.** Without cleanup: add `~$5-15 USD/day` depending on AgentCore Runtime idle pattern and CloudFront request volume. The two main cost drivers are Bedrock Nova 2 Sonic streaming (per active conversation minute) and AgentCore Runtime (per active session-second).

A per-service breakdown will be added post-launch after the instructor pulls 24h Cost Explorer data from a real workshop session (04-HUMAN-UAT item #4 — paste-line at the end of Chapter 4). Once that data lands, a detailed per-service table will replace this paragraph — instructor's actual spend is the ground truth, not estimates.

*Source: D-54 ballpark + 04-HUMAN-UAT item #4 deferred — Phase 5 Plan 05-04*

**Important caveats:**

- AWS Free Tier resets monthly — the numbers above assume you still have free tier headroom.
- Cost Explorer takes up to 24 hours to update — the instant number at end-of-session may not reflect reality yet.
- AWS pricing changes periodically; bookmark `https://aws.amazon.com/bedrock/pricing/` for live numbers.

## Expansion (DOC-09)

You have a working voice loop. Here are 4 common expansion directions — all DEFERRED to v2 in the current workshop scope, but each has a roadmap and requirement IDs so you can build them yourself.

### Twilio Voice Channel (TWIL-01..03 — v2)

A Twilio phone number receives the call → Twilio Media Streams connects to the AgentCore endpoint instead of a browser → workshop chapter "Phone channel via Twilio". Bridge layer in between: Twilio sends μ-law 8kHz; Pipecat needs Int16 16kHz for Sonic — you have to resample inbound + outbound at the presigner or a dedicated Lambda. Reference: `https://www.twilio.com/docs/voice/twiml/stream`.

### Multi-language chatbot (I18N-01..02 — v2)

Auto-detect the user's spoken language (vi/en) + have Sonic emit Vietnamese audio when quality is acceptable. Sonic-vi quality is currently noticeably lower than Sonic-en (as of 2026-Q1) — wait for AWS to upgrade the voice model before shipping v2. The workshop docs are already bilingual (DOC-12 parity gate); the voice path is what still needs I18N work.

### Multi-agent routing (ADV-01 — v2)

An orchestrator agent routes to specialized agents (sales, support, billing) based on intent extracted from Sonic tool-use. The pattern is similar to `awslabs/agentcore-samples` workflow examples. You'll also need persistent agent state (DynamoDB, ADV-03 — conversation history persistent) so cross-agent context isn't lost on switch.

### Conversation history persistent (ADV-03 — v2)

A DynamoDB per-user session store for returning users; v1 is in-memory only (D-21 Phase 2 — `LLMContext` per WebSocket, freed on disconnect). v2 needs Cognito SSO (AUTH-01..02) to bind a user identity to the session, and a DynamoDB table with TTL to auto-expire history after N days.

## Other deferrals (v2 backlog)

- Cognito SSO + per-user quota (AUTH-01..02 — the current workshop is anonymous and AgentCore concurrency cap=2 is the gate).
- ECS Fargate alternative deployment chapter to compare AgentCore vs self-hosted (ADV-04).
- Hugo theme migration `hugo-theme-learn` → `hugo-theme-relearn` (THEME-01..02 — `hugo-theme-learn` is deprecated upstream but still works for v1).
- Custom domain + ACM cert instead of the default `*.cloudfront.net` (Phase 3 D-26 deferred — would also unlock TLSv1.2_2021 minimum instead of the TLSv1 auto-downgrade).
- Knowledge Base with RAG re-ranking (ADV-02 — extra Bedrock invocation per retrieve, latency vs precision trade-off).
- Bedrock Guardrails PII redaction (PROJECT.md Out of Scope v1 — the workshop uses demo Apple catalog data, no real PII).

Full tracking lives in `.planning/REQUIREMENTS.md` § v2 Requirements.

## Thanks

This workshop was built for AWS Cloud Clubs Vietnam, with the goal of helping Cloud Clubs members deploy a voice chatbot to their own AWS account end-to-end — not watching a demo, but actually shipping.

Reference architecture: the AWS blog post "Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1" (`https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/`) is the primary blueprint. Reference repo: `https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore`.

Issues / improvements: PR into the workshop repo on GitHub (URL from `config.toml` `baseURL`). The workshop is a living doc — pricing drift, AWS service updates, and Pipecat version bumps all need periodic re-verification.

## References

- `RUNBOOK.md` — full operator runbook (paste-style ops; each workshop chapter section points back to it).
- `.planning/PROJECT.md` — core value + locked stack rationale.
- `.planning/REQUIREMENTS.md` — 46 v1 requirements + v2 deferred backlog.
- `.planning/ROADMAP.md` — 5-phase plan + per-phase success criteria.
- AWS Bedrock pricing: `https://aws.amazon.com/bedrock/pricing/`.
- AgentCore Runtime docs: `https://docs.aws.amazon.com/bedrock-agentcore/`.
- Pipecat 1.1.0: `https://docs.pipecat.ai/`.
