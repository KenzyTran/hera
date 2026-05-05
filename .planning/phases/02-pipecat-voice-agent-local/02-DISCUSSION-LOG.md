# Phase 2: Pipecat Voice Agent (Local) — Discussion Log

**Date:** 2026-05-05
**Mode:** standard discuss-phase (no flags)
**Areas selected:** 4 of 4 (all gray areas)

This log is the human-readable trail of what was asked, what was offered, and what the user picked. The canonical decisions live in `02-CONTEXT.md` — this file exists for audits and retrospectives only and is NOT consumed by downstream agents.

## Pre-loaded Context

Read before identifying gray areas:
- `.planning/PROJECT.md` (locked stack: Pipecat 1.1.0, Nova 2 Sonic, S3 Vectors, AgentCore, ap-northeast-1)
- `.planning/REQUIREMENTS.md` (AGT-01..AGT-08)
- `.planning/STATE.md` (Phase 1 just closed, KB BKXE19AH89 live)
- `.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md` (Phase 1 D-01..D-16, especially D-10 deferred consumer role)
- `CLAUDE.md` (no emojis, uv only, English chatbot, Hugo theme deprecated)
- `AGENTS.md` (simple, incremental, root-cause)

## Pre-locked Decisions Inherited

These were already decided and NOT re-asked:
- Pipecat 1.1.0 + Python ≥3.11 + uv (CLAUDE.md)
- AWSNovaSonicLLMService for Nova 2 Sonic (AGT-01, AGT-05)
- 16 kHz Int16 in / 24 kHz out (AGT-07)
- English-only chatbot (CLAUDE.md, AGT-02)
- In-memory session state, no DynamoDB (AGT-06)
- Container ready for ECR push to Phase 3 (AGT-08)
- Phase 2 owns the `bedrock:Retrieve` consumer IAM (D-10 deferred from Phase 1)
- Live KB ARN target: `arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89`

## Gray Areas Presented

User chose all 4 of:
1. Persona + system prompt
2. Tool `lookup_product()` schema + KB response shape
3. Browser ↔ Pipecat transport for local dev
4. Container shape + local run UX

## Q&A Trail

### Area 1 — Persona

**Q:** Apple Store assistant nói theo phong cách nào?
**Options:**
- Crisp store associate — minimal pleasantries, direct answers, 1-line refusal
- Friendly store guide — warmer, acknowledge customer goal, suggest alternatives
- Premium concierge — formal, polished, longer responses

**User pick:** Crisp store associate

**Captured as D-17.** No follow-up needed — exact greeting wording and example Q/A pairs are author-time choices during execution.

### Area 2 — Tool schema and KB response shape

**Q:** Pipecat trả KB chunks về Sonic theo shape nào?
**Options:**
- Top-1 chunk only, raw text (lightweight, weak on cross-product)
- Top-3 chunks, gated score >= 0.4 (matches verify-kb.sh threshold)
- Top-3 + structured dict {text, source, score}
- Show me examples first

**User pick:** Top-3 chunks, gated score >= 0.4

**Captured as D-18.** Format: `Source: <basename>\n<text>` joined with `\n\n`. If zero survive threshold, return literal `"no relevant product info"`. Threshold env var `HERA_KB_SCORE_THRESHOLD` matches `bin/verify-kb.sh` for operator consistency.

### Area 3 — Browser ↔ Pipecat transport

**Q:** Transport giữa browser và Pipecat agent local?
**Options:**
- WebSocket (match aws-samples/sample-nova-sonic-websocket-agentcore + AgentCore likely WSS)
- WebRTC (Pipecat default for browser, lower latency, more complex setup)
- WebSocket local + plan to switch in Phase 3 if needed

**User pick:** WebSocket (match reference repo + AgentCore)

**Captured as D-19.** End-to-end WSS, no transport refactor between phases. Local URL `ws://localhost:8080/ws`.

### Area 4 — Container + local run UX

**Q:** Lúc dev local muốn test, học viên chạy lệnh gì?
**Options:**
- `docker compose up` — 2-service stack, agent + frontend
- `uv run python -m hera_agent` + browser open file:// (no docker for dev, container only for ECR)
- `docker run` with FastAPI inside container hosting the HTML page

**User pick:** docker compose up

**Captured as D-20.** Two services in `docker-compose.yml`: `agent` (Pipecat container, base `ghcr.io/astral-sh/uv:python3.11-slim`) and `frontend` (`nginx:alpine` static HTML/JS). Same `agent` image is what Phase 3 pushes to ECR. Compose file is local-only.

## Implicit / Inferred Decisions (no user question)

These were decided from project context without asking, with reasoning noted in CONTEXT.md:
- **D-21** — In-memory session state (re-states AGT-06 lock for clarity).
- **D-22** — IAM consumer role shape: managed policy `hera-kb-retrieve-prod`, NOT attached in Phase 2; Phase 3 attaches to AgentCore execution role; local dev uses developer credentials.
- **D-23** — Latency budget split for the <3s p95 success criterion.

## Deferred to Research / Planning

- Pipecat package layout (single file vs package)
- Logging library + format choice
- VAD threshold tuning
- Exact system-prompt token wording and example Q/A pairs
- Decision on `/healthz` endpoint vs WSS upgrade as healthcheck signal

## Deferred Ideas (scope-creep parking lot)

None raised during this discussion.
