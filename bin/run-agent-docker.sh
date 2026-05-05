#!/usr/bin/env bash
# bin/run-agent-docker.sh - Phase 2 local agent run via docker compose.
# Companion to bin/run-agent-local.sh (uv-native path). Same env var contract;
# different runtime. This path matches what Phase 3 deploys to AgentCore.
#
# Exit codes:
#   0   stack started (or terminated cleanly)
#   1   runtime failure
#   2   preflight error (missing tools or env vars)

set -euo pipefail

# --- preflight: required tools ---
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found on PATH (install Docker Desktop or Engine 20.10+)" >&2; exit 2; }
docker compose version >/dev/null 2>&1 || { echo "ERROR: docker compose v2 not found (the bundled 'docker compose' subcommand, NOT the legacy 'docker-compose' binary)" >&2; exit 2; }
docker buildx version >/dev/null 2>&1 || { echo "ERROR: docker buildx not found (bundled with Docker 20.10+)" >&2; exit 2; }

# --- required env vars (fail-fast per AGENTS.md) ---
: "${AWS_ACCESS_KEY_ID:?ERROR: AWS_ACCESS_KEY_ID must be set in shell or .env}"
: "${AWS_SECRET_ACCESS_KEY:?ERROR: AWS_SECRET_ACCESS_KEY must be set in shell or .env}"
: "${HERA_KB_ID:?ERROR: HERA_KB_ID must be set. Run: terraform -chdir=infra/envs/prod output -raw kb_id}"

# --- defaults (mirror bin/run-agent-local.sh and agent/.env.example) ---
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export HERA_KB_SCORE_THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"
export HERA_VOICE="${HERA_VOICE:-matthew}"

cd "$(dirname "$0")/.."

echo "starting hera-agent stack via docker compose"
echo "  region=${AWS_REGION}  kb=${HERA_KB_ID}  voice=${HERA_VOICE}  threshold=${HERA_KB_SCORE_THRESHOLD}"
echo "  agent     -> http://localhost:8080  (/ping for health, /ws for voice)"
echo "  frontend  -> http://localhost:8000  (open in Chrome/Edge)"

exec docker compose up --build
