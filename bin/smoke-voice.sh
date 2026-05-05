#!/usr/bin/env bash
# bin/smoke-voice.sh - Phase 2 AGT-04 latency gate.
#
# Brings up the docker-compose stack, runs bin/_smoke_voice_probe.py against
# the live agent (which talks to live Bedrock Nova 2 Sonic + live Phase 1 KB),
# tears down. Exits 0 ONLY if the probe measured latency < 3.0s.
#
# Exit codes:
#   0   AGT-04 gate passed (measured latency < 3.0s)
#   1   gate failed (latency >= 3.0s, no inbound frame, or stack failed health)
#   2   preflight error (missing tools, env vars, or model access)
#
# Pattern: bin/verify-kb.sh (Phase 1 live-AWS verification).

set -euo pipefail

# --- preflight: required tools ---
command -v docker  >/dev/null 2>&1 || { echo "ERROR: docker not found on PATH" >&2; exit 2; }
command -v uv      >/dev/null 2>&1 || { echo "ERROR: uv not found on PATH (CLAUDE.md mandate)" >&2; exit 2; }
command -v curl    >/dev/null 2>&1 || { echo "ERROR: curl not found on PATH" >&2; exit 2; }
docker compose version >/dev/null 2>&1 || { echo "ERROR: docker compose v2 not found" >&2; exit 2; }

# --- required env vars ---
: "${AWS_ACCESS_KEY_ID:?ERROR: AWS_ACCESS_KEY_ID must be set in shell or .env}"
: "${AWS_SECRET_ACCESS_KEY:?ERROR: AWS_SECRET_ACCESS_KEY must be set in shell or .env}"
: "${HERA_KB_ID:?ERROR: HERA_KB_ID must be set. Run: terraform -chdir=infra/envs/prod output -raw kb_id}"

export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export HERA_KB_SCORE_THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"
export HERA_VOICE="${HERA_VOICE:-matthew}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

cleanup() {
  echo "tearing down docker compose stack"
  docker compose down >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "AGT-04 gate: docker compose up + scripted WS probe + teardown"
echo "  region=${AWS_REGION}  kb=${HERA_KB_ID}  voice=${HERA_VOICE}"

# Bring up the stack; wait for the agent healthcheck (max 60s, 2s interval).
docker compose up -d --build

STATUS=starting
for i in $(seq 1 30); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$(docker compose ps -q agent)" 2>/dev/null || echo "starting")
  if [[ "${STATUS}" == "healthy" ]]; then
    break
  fi
  sleep 2
done

if [[ "${STATUS}" != "healthy" ]]; then
  echo "FAIL: agent did not become healthy within 60s" >&2
  docker compose logs agent >&2
  exit 1
fi

# Sanity: /ping returns Healthy
curl -fsS http://localhost:8080/ping | grep -q '"status":"Healthy"' || {
  echo "FAIL: /ping did not return Healthy" >&2
  exit 1
}

# Run the latency probe inside agent/.venv so `import websockets` resolves
# (Plan 02-01 declared websockets as a dev-dep in agent/pyproject.toml).
# Same-line capture so `set -e` does not abort before we read $? and emit
# the diagnostic.
echo "running bin/_smoke_voice_probe.py against ws://localhost:8080/ws"
cd "${REPO_ROOT}/agent"
PROBE_RC=0
uv run python "${REPO_ROOT}/bin/_smoke_voice_probe.py" || PROBE_RC=$?
cd "${REPO_ROOT}"

if [[ ${PROBE_RC} -ne 0 ]]; then
  echo "FAIL: AGT-04 latency probe exit ${PROBE_RC}" >&2
  exit 1
fi

echo "OK: AGT-04 latency gate passed"
exit 0
