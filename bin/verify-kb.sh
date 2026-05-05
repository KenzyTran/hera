#!/usr/bin/env bash
# bin/verify-kb.sh - Phase 1 KB-04 verification script.
# Polls the Bedrock KB Retrieve API every 15s for up to 5 minutes until results appear with a score above threshold.
# Exits 0 on success (default) or when KB is unreachable (--invert mode for Phase 4 cleanup, D-16).
# Exits non-zero with a human-readable message on timeout, empty results, or access denied.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --kb-id ID          Knowledge Base ID. If omitted, read from terraform output.
  --region REGION     AWS region. Default: ap-northeast-1 (or HERA_REGION env var).
  --query JSON        Retrieval query as JSON. Default: {"text":"iPhone 13 Pro Max stock"}.
  --threshold N       Minimum top score for success. Default: 0.4 (or HERA_KB_SCORE_THRESHOLD env var).
  --invert            Phase 4 cleanup mode: success when KB is unreachable.
  --help              Show this message and exit.

Exit codes:
  0   Verification passed (results found above threshold, or in --invert mode KB is unreachable).
  1   Verification failed (timeout, empty results, or in --invert mode KB still responds).
  2   Argument error.

Examples:
  $(basename "$0")
  $(basename "$0") --kb-id ABCD1234EFGH
  $(basename "$0") --invert
EOF
}

# --- preflight: required tools ---
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found on PATH (RUNBOOK Pre-flight)" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq not found on PATH (RUNBOOK Pre-flight). Install: winget install jqlang.jq (Windows), brew install jq (macOS), apt-get install jq (Debian/Ubuntu)" >&2; exit 2; }

# --- defaults / args ---
REGION="${HERA_REGION:-ap-northeast-1}"
QUERY='{"text":"iPhone 13 Pro Max stock"}'
THRESHOLD="${HERA_KB_SCORE_THRESHOLD:-0.4}"
MAX_ATTEMPTS=20
SLEEP_SECONDS=15
KB_ID=""
INVERT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kb-id)     KB_ID="$2"; shift 2 ;;
    --region)    REGION="$2"; shift 2 ;;
    --query)     QUERY="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --invert)    INVERT=1; shift ;;
    --help|-h)   usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- resolve KB id from terraform if not supplied ---
if [[ -z "$KB_ID" ]]; then
  KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id 2>/dev/null || true)
  if [[ -z "$KB_ID" ]]; then
    echo "ERROR: --kb-id not provided and 'terraform -chdir=infra/envs/prod output -raw kb_id' failed" >&2
    echo "Run from the repo root, or pass --kb-id explicitly." >&2
    exit 2
  fi
fi

echo "verifying KB ${KB_ID} in ${REGION}"
echo "query: ${QUERY}"
echo "score threshold: ${THRESHOLD}"
echo "polling every ${SLEEP_SECONDS}s for up to $((MAX_ATTEMPTS * SLEEP_SECONDS))s"
if [[ "${INVERT}" == "1" ]]; then
  echo "mode: INVERT (cleanup verification - success when KB is unreachable)"
fi

# --- poll loop ---
for i in $(seq 1 "${MAX_ATTEMPTS}"); do
  RESP=$(aws bedrock-agent-runtime retrieve \
    --region "${REGION}" \
    --knowledge-base-id "${KB_ID}" \
    --retrieval-query "${QUERY}" \
    --retrieval-configuration '{"vectorSearchConfiguration":{"numberOfResults":3}}' \
    --output json 2>&1) || true

  if [[ "${INVERT}" == "1" ]]; then
    # cleanup-mode: any AccessDenied / NotFound means KB is gone (success)
    if echo "${RESP}" | grep -qiE 'AccessDenied|ResourceNotFound'; then
      echo "OK (cleanup): KB no longer accessible"
      echo "${RESP}" | head -3
      exit 0
    fi
    echo "attempt ${i}/${MAX_ATTEMPTS}: KB still responding; expected to be gone"
  else
    HITS=$(echo "${RESP}" | jq -r '.retrievalResults | length')
    TOP=$(echo "${RESP}" | jq -r '.retrievalResults[0].score // 0')
    echo "attempt ${i}/${MAX_ATTEMPTS}: hits=${HITS} top_score=${TOP}"

    if [[ "${HITS}" -gt 0 ]] && awk "BEGIN{exit !(${TOP} >= ${THRESHOLD})}"; then
      echo "OK: ${HITS} results returned, top score ${TOP} >= threshold ${THRESHOLD}"
      exit 0
    fi

    # Surface AccessDeniedException immediately (model access not enabled, or IAM mismatch)
    if echo "${RESP}" | grep -qi 'AccessDeniedException'; then
      echo "ERROR: AccessDeniedException - check Bedrock model access for amazon.titan-embed-text-v2:0 in ${REGION}, and the KB service role inline policy" >&2
      echo "${RESP}" | head -5 >&2
      exit 1
    fi
  fi

  sleep "${SLEEP_SECONDS}"
done

if [[ "${INVERT}" == "1" ]]; then
  echo "FAIL (cleanup): KB still responding after $((MAX_ATTEMPTS * SLEEP_SECONDS))s - destroy did not complete" >&2
else
  echo "FAIL: no qualifying results after $((MAX_ATTEMPTS * SLEEP_SECONDS))s" >&2
  echo "Possible causes: ingestion job not run, post-sync propagation lag exceeded 5min, model access not enabled, IAM misconfigured." >&2
fi
exit 1
