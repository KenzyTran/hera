# Hera — Project Instructions

This is an FCJ workshop + AWS voice agent demo project. Planning artifacts live in `.planning/`.

## Read first (in order)

1. `.planning/PROJECT.md` — what we're building, core value, scope, locked decisions
2. `.planning/REQUIREMENTS.md` — 46 v1 requirements (KB / AGT / DEP / WID / OBS / DEM / DOC) with REQ-ID traceability to phases
3. `.planning/ROADMAP.md` — 5-phase plan, success criteria per phase
4. `.planning/STATE.md` — current position in workflow

## Locked stack (do not re-litigate)

- **Voice**: Amazon Nova 2 Sonic on Bedrock (NOT Gemini, NOT ElevenLabs)
- **Compute**: Amazon Bedrock AgentCore Runtime (NOT ECS Fargate, NOT Lambda)
- **Orchestrator**: Pipecat 1.1.0 (Python ≥3.11)
- **Vector store**: S3 Vectors + Titan v2 embeddings (NOT OpenSearch Serverless)
- **IaC**: Terraform `~> 6.27` primary, hybrid CDK/CLI fallback only if AgentCore Terraform support has gaps
- **Region**: `ap-northeast-1` prod, `us-east-1` dev
- **Channel v1**: web widget (browser microphone). Twilio is v2.
- **Chatbot language**: English only. Workshop docs: vi/en bilingual.

## Project conventions

- Python: `uv` only (`uv add X`, `uv run X`). Never `pip install`, never `python3 X`.
- No emojis in code, logs, or print statements.
- Concise docstrings, sparing comments outside docstrings.
- Hugo theme is `hugo-theme-learn` (deprecated upstream — migration to relearn is v2 work).
- Workshop content lives in `content/{vi,en}/` mirroring each other 1:1.

## GSD workflow

This project uses Get-Shit-Done v1 (`.planning/`). Config: YOLO mode, coarse granularity, parallel execution, quality model profile, research+plan-check+verifier all enabled.

Standard next step: `/gsd-plan-phase 1` to plan the Knowledge Base Foundation phase.

## Reference material

- `raw_content.txt` — Vietnamese transcript of an ElevenLabs+n8n+Gemini voice agent tutorial. Used as **use case reference only** (Apple Store support, 3-SKU catalog). The implementation is AWS-native, NOT a port.
- AWS blog: [Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/)
- Reference repo: [aws-samples/sample-nova-sonic-websocket-agentcore](https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore)
