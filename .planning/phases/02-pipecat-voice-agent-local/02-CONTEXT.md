# Phase 2: Pipecat Voice Agent (Local) - Context

**Gathered:** 2026-05-05
**Status:** Ready for research and planning

<domain>
## Phase Boundary

A Pipecat 1.1.0 voice agent (Python ≥3.11) runs on a developer's laptop inside a Docker Compose stack and proves the full voice loop: browser microphone → WebSocket → Pipecat agent → Amazon Nova 2 Sonic (Bedrock bidirectional streaming) → tool `lookup_product()` → live Phase 1 Knowledge Base (`BKXE19AH89` in `ap-northeast-1`) → spoken Apple Store answer back through speakers, in <3s p95 from end-of-utterance. The container image produced here is the same artifact Phase 3 will push to ECR for AgentCore Runtime deployment — local dev and AgentCore deploy share one Pipecat codebase and one transport (WebSocket).

In scope: Pipecat agent code, system prompt, tool implementation, browser test page, Dockerfile, docker-compose for local, IAM managed policy for the consumer role (output only — not attached to anything in Phase 2). Out of scope: AgentCore deploy, public HTTPS endpoint, observability dashboards, billing alarms, any DynamoDB or persistent state.

</domain>

<canonical_refs>
## Canonical References

Downstream agents (researcher, planner, executor) MUST read these:

- `.planning/PROJECT.md` — project core value, locked stack, scope rules
- `.planning/REQUIREMENTS.md` — AGT-01..AGT-08 are this phase's requirement IDs
- `.planning/ROADMAP.md` — Phase 2 goal and 5 success criteria (lines covering Phase 2)
- `.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md` — Phase 1 decisions, especially D-10 (consumer role deferred) and D-13 (zero IAM wildcards)
- `.planning/phases/01-knowledge-base-foundation/01-VERIFICATION.md` — live KB id, ARN, evidence top score 0.86
- `.planning/phases/01-knowledge-base-foundation/01-03-verify-and-sync-SUMMARY.md` — live KB id `BKXE19AH89`, S3 Vectors index attributes, retrieve API shape
- `RUNBOOK.md` — operational commands; phase 2 may extend with agent run/test sections
- `infra/envs/prod/outputs.tf` — kb_arn, kb_id, source_bucket_name (terraform outputs phase 2 reads)
- `CLAUDE.md` — project mandates: no emojis, uv only, concise docstrings
- `AGENTS.md` — coding philosophy: simple, incremental, root-cause debugging, no defensive programming

External references:
- AWS blog: Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1 (https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/)
- Reference repo: https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore — same WSS transport pattern; codebase shape to learn from but not directly fork
- Pipecat docs: https://docs.pipecat.ai/ (1.1.0)
- Pipecat AWSNovaSonicLLMService: handles 8-min Sonic stream cap transparently per AGT-05 — phase 2 does NOT implement reconnect logic manually

</canonical_refs>

<decisions>
## Implementation Decisions

(Numbering continues from Phase 1 D-16. Phase 2 starts at D-17.)

### Persona and system prompt
- **D-17:** Persona is "**Crisp store associate**" — minimal pleasantries, get to the answer fast. Greeting: short opener like "Hi, what can I check for you?". Product replies: 1-2 sentences plus the relevant stock numbers. Refuse non-Apple questions in 1 line: "I only handle Apple product questions — anything else?". Tone is direct but courteous; never uses filler ("absolutely", "great question"). System prompt seeds 2-3 example Q/A pairs that exhibit this style.

### Tool `lookup_product()` schema and KB response shape
- **D-18:** Tool signature is `lookup_product(query: str) -> str`. Single string param — no filter argument in v1.
  - Calls Bedrock KB Retrieve (boto3 `bedrock-agent-runtime`) with `numberOfResults=3` and a config-driven `score_threshold` (default `0.4`, matching `bin/verify-kb.sh` and Phase 1 decision space).
  - Filters chunks below threshold. If zero chunks survive, return the literal string `"no relevant product info"` so Sonic refuses gracefully.
  - For surviving chunks, format each as `Source: <basename of s3 uri>\n<chunk text>` and join with `\n\n` separators. Top-1 first.
  - The threshold is read from an env var `HERA_KB_SCORE_THRESHOLD` (default `0.4`), same env var name shape as `bin/verify-kb.sh` for operator consistency.
  - The KB ID is read from env var `HERA_KB_ID` at agent startup (no terraform shell-out at runtime). Local dev sets it manually or via `docker compose --env-file`. Phase 3 wires it via AgentCore env injection.

### Browser ↔ Pipecat transport
- **D-19:** **WebSocket (WSS)** end-to-end. Browser opens a WebSocket to the Pipecat agent at `ws://localhost:8080/ws` for local dev (later WSS at the AgentCore endpoint in Phase 3). Mirror of `aws-samples/sample-nova-sonic-websocket-agentcore` reference repo. Reasons: (a) same transport in local + AgentCore avoids two implementations, (b) Pipecat 1.1.0 has a first-class WebSocket transport, (c) WebRTC's lower latency does not justify SDP/ICE plumbing complexity at this scope. Phase 3 inherits this choice — no transport refactor between phases.

### Container shape and local run UX
- **D-20:** Local dev UX is `docker compose up`. The compose file ships **two services**:
  - `agent` — Pipecat container, ports 8080:8080 (WSS endpoint at `/ws`, optional `/healthz` GET).
    Base image `ghcr.io/astral-sh/uv:python3.11-slim` (uv official) so the build inherits uv at the OS level.
    Reads `HERA_KB_ID`, `HERA_KB_SCORE_THRESHOLD`, `AWS_REGION`, and standard AWS credential env vars (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` or the developer's `~/.aws` mounted read-only).
  - `frontend` — `nginx:alpine` serving a minimal static `index.html` + JS at port `8080` of the host (host port differs to avoid clash; e.g. `frontend` on host `:8000`, `agent` on host `:8080`).
  - The HTML page has: a record button, AudioWorklet for 16 kHz mono Int16 capture, WebSocket client to `agent`, audio sink for 24 kHz response playback, and a live transcript panel for debugging.
  - This is the SAME container image Phase 3 will push to ECR — no second build path for production. The compose file is local-only.

### Conversation state (AGT-06 — implicit lock from REQUIREMENTS)
- **D-21:** Per-session conversation history lives in **Pipecat's in-process pipeline state** (no DynamoDB, no Redis, no disk). When the WebSocket closes, the session is gone. This is the v1 contract; multi-turn coherence WITHIN a session is preserved via the Sonic bidirectional stream which carries its own short-context memory.

### IAM consumer role (resolves Phase 1 D-10)
- **D-22:** Phase 2 ships a Terraform-managed **IAM managed policy** named `hera-kb-retrieve-prod` containing exactly one statement: `Action: bedrock:Retrieve`, `Resource: <kb_arn>` (the live KB ARN read from Phase 1's terraform output). **Zero wildcards** (per D-13). This policy is **NOT attached** to any role in Phase 2 — Phase 3 attaches it to the AgentCore execution role when that role is created.
  - Local dev does NOT use this policy. The agent runs with the developer's AWS credentials (boto3 default chain). Workshop documents both: "use your own creds for local testing; the Terraform-managed policy ships ready for AgentCore in Phase 3".
  - The policy lives in a new module `infra/modules/kb_consumer_policy/` (or extends `modules/knowledge_base/`) — planner decides exact placement during Phase 2 plan-phase.
  - Output added to `infra/envs/prod/outputs.tf`: `kb_retrieve_policy_arn`.

### Latency target alignment with success criterion #1 (<3s p95 end-of-utterance → first audio chunk)
- **D-23:** Acceptable latency budget for local-dev test (single-user, same machine):
  - Sonic round-trip: ~1.0–1.5s (network + model)
  - KB Retrieve: ~0.2–0.5s
  - WebSocket overhead: ~0.05–0.1s
  - Tool dispatch + format: ~0.05s
  - Headroom: ~0.5–0.8s
  - Total budget supports <3s p95. If local test misses target, root-cause first (per AGENTS.md) — never relax to >3s. Likely culprits: AWS region not `ap-northeast-1`, Sonic stream cold start, or Pipecat default buffer too large.

### What is explicitly NOT decided here (defer to research / planning)
- Pipecat package layout (single `main.py` vs `hera_agent/__init__.py` package) — planner picks based on test file shape and conventions.
- Logging library and format — default to Python `logging` with structured JSON formatter unless researcher finds a Pipecat-recommended pattern.
- VAD threshold and barge-in behavior — accept Pipecat 1.1.0 defaults unless test shows issues.
- Concrete system-prompt token count and example Q/A wording — author the prompt during execution; D-17 specifies the persona, not the exact tokens.
- Whether to add a `/healthz` endpoint or rely on WSS upgrade success — recommended: simple `/healthz` returning HTTP 200 for dockerfile HEALTHCHECK directive, but planner decides.

</decisions>

<code_context>
## Reusable Assets and Patterns

**Greenfield for Python/agent code.** No existing Python source in the repo. Phase 1 introduced only Terraform (`infra/`), bash (`bin/verify-kb.sh`), and markdown (`catalog/`, `RUNBOOK.md`). No prior agent or web-frontend code to extend.

**What can be reused from Phase 1:**
- `infra/modules/knowledge_base/` — existing module exports `kb_arn`, `kb_id`, `source_bucket_name`, `data_source_id`. Phase 2's Terraform additions consume these via `module.knowledge_base.kb_arn` reference. No new variables needed beyond optional `policy_name_prefix` for the consumer policy.
- `infra/envs/prod/outputs.tf` — adds `kb_retrieve_policy_arn` (new) alongside existing `kb_arn`, `kb_id`, `source_bucket_name`, `data_source_id`.
- `RUNBOOK.md` — extend with new sections: "Local agent setup (Phase 2)", "First voice test", "Cleanup local Docker resources". Same operational pattern (paste-ready commands, no emojis, English).
- `bin/verify-kb.sh` — same boto3 call shape (`bedrock-agent-runtime retrieve`) is what `lookup_product()` does in Python. Threshold env var name (`HERA_KB_SCORE_THRESHOLD`) reused for operator consistency. Region env var (`HERA_REGION`) too.

**Patterns to honor (from Phase 1 and project mandates):**
- Atomic commits per task with conventional-commit prefixes scoped to plan id (e.g., `feat(02-01): ...`)
- No emojis anywhere
- `uv` package manager exclusively (`uv add X`, `uv run X`)
- Concise docstrings, sparing other comments
- Root-cause debugging — no `try/except` papering over real errors (Phase 1 verify-kb.sh `2>/dev/null || echo 0` lesson, commit `f78a39a`)
- Region default `ap-northeast-1`, override `us-east-1` (D-14 from Phase 1)

**Reference codebase patterns to study but not fork blindly:**
- `https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore` — main.py shape, WebSocket handler, AWSNovaSonicLLMService config, system prompt structure. Researcher should pull the exact Pipecat 1.1.0 API surface from `pipecat-ai/pipecat` repo to verify versioned call signatures.

</code_context>

<deferred>
## Deferred Ideas

(None raised during this discussion. Add here if any scope-creep ideas surface during research/planning so they get parked into the roadmap backlog instead of dropping.)

</deferred>

<success_signals>
## What Success Looks Like (for downstream agents)

When research and planning complete, the executor should be able to produce a phase deliverable that satisfies all 5 ROADMAP success criteria:

1. Developer asks "Do you have MacBook Pro?" into a local browser microphone → Sonic calls `lookup_product()` against KB `BKXE19AH89` → spoken Apple Store answer through speakers in <3s p95 from end-of-utterance.
2. Audio correct end-to-end: 16 kHz mono Int16 in, 24 kHz mono out, no chipmunk effect, no silent transcription failure.
3. Conversations >8 min do not visibly break (Pipecat's `AWSNovaSonicLLMService` handles the Sonic stream cap, no manual reconnect code).
4. Persona stays "Crisp store associate" English-only; per-session state in-memory only.
5. Container image builds reproducibly with `uv` lockfile and is ready to push to ECR for Phase 3 AgentCore deploy.

</success_signals>
