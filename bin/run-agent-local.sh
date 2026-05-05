#!/usr/bin/env bash
# bin/run-agent-local.sh - Phase 2 local agent run (uv-based, no Docker).
# Plan 02-01 scope: native uv run for fast iteration. Plan 02-02 adds the
# docker compose path. Same env var contract.
#
# Exit codes:
#   0   agent started (or terminated cleanly)
#   1   runtime failure
#   2   preflight error (missing tools or env vars)

set -euo pipefail

# --- preflight: required tools ---
command -v uv >/dev/null 2>&1 || { echo "ERROR: uv not found on PATH (CLAUDE.md mandate; install: https://docs.astral.sh/uv/)" >&2; exit 2; }

# --- required env vars (fail-fast per AGENTS.md) ---
: "${AWS_ACCESS_KEY_ID:?ERROR: AWS_ACCESS_KEY_ID must be set in shell or .env}"
: "${AWS_SECRET_ACCESS_KEY:?ERROR: AWS_SECRET_ACCESS_KEY must be set in shell or .env}"
: "${HERA_KB_ID:?ERROR: HERA_KB_ID must be set. Run: terraform -chdir=infra/envs/prod output -raw kb_id}"

# --- defaults (mirror bin/verify-kb.sh and agent/.env.example) ---
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export HERA_KB_SCORE_THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"
export HERA_VOICE="${HERA_VOICE:-matthew}"

echo "starting hera-agent on http://localhost:8080 (/ping for health, /ws for voice)"
echo "  region=${AWS_REGION}  kb=${HERA_KB_ID}  voice=${HERA_VOICE}  threshold=${HERA_KB_SCORE_THRESHOLD}"

cd "$(dirname "$0")/../agent"
uv sync --frozen
exec uv run uvicorn hera_agent.main:app --host 0.0.0.0 --port 8080
