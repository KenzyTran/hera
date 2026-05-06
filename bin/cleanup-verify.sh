#!/usr/bin/env bash
# bin/cleanup-verify.sh - Phase 4 cleanup verification (D-37, D-39).
# Runs AFTER operator-driven `cdk destroy` then `terraform destroy`.
# Exits 0 when ALL phase 1/2/3/4 resources are gone; exits 1 with a counter
# summary if any leftover detected.
#
# Read-only: never invokes destroy commands. Never calls Cost Explorer (D-38 -
# 24h ingestion lag + $0.01/request fee; Cost Explorer paste-line lives in
# RUNBOOK Phase 4 section as a 24h-deferred manual step).
#
# Resource list verbatim from .planning/phases/04-*/04-RESEARCH.md section D
# (CONTEXT D-37 + Plan 04-02 observability additions).
#
# Usage:  bash bin/cleanup-verify.sh
# Reads:  HERA_REGION (default ap-northeast-1)
# Effect: 19 read-only AWS API calls; prints OK / FAIL per resource + final tally.

set -euo pipefail

# --- preflight: required tools ---
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found on PATH (RUNBOOK Pre-flight)" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq not found on PATH (RUNBOOK Pre-flight). Install: winget install jqlang.jq (Windows), brew install jq (macOS), apt-get install jq (Debian/Ubuntu)" >&2; exit 2; }

# --- defaults ---
REGION="${HERA_REGION:-ap-northeast-1}"
BILLING_REGION="us-east-1"            # AWS/Billing service constraint (Phase 4 D-35).

# windows-bash: log-group names start with `/`; MSYS_NO_PATHCONV=1 disables Git Bash path mangling (PITFALL G.8).

PASS_COUNT=0
FAIL_COUNT=0

# Multi-error-name alternation covers AWS CLI error spellings across services (RESEARCH section D + A4):
GONE_REGEX='ResourceNotFound|NoSuchEntity|NotFound|RepositoryNotFound|NoSuchDistribution|NoSuchBucket|does not exist|404'

echo "cleanup-verify against ${REGION} (billing in ${BILLING_REGION})"
echo "----------------------------------------"

# Helper: check that a describe/get call returns an error matching GONE_REGEX.
_check_gone() {
  local label="$1"; shift
  local resp
  resp=$("$@" 2>&1) || true
  if echo "${resp}" | grep -qiE "${GONE_REGEX}"; then
    echo "OK: ${label} is gone"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: ${label} still exists"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# Helper: check that a length(@) query returns 0.
# 2>/dev/null (NOT 2>&1) keeps stderr deprecation banners from leaking into the
# count variable on Windows Git Bash / older AWS CLI v2 builds (plan-check MED-3).
# Whitespace is stripped before the equality test so a trailing newline never
# misfires the literal "0" comparison.
_check_count_zero() {
  local label="$1"; shift
  local count
  count=$("$@" 2>/dev/null || echo "ERR")
  count="${count//[[:space:]]/}"
  if [[ "${count}" == "0" ]]; then
    echo "OK: ${label} count = 0"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: ${label} count = ${count}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# --- 1. KB ---
_check_gone "KB BKXE19AH89" \
  aws bedrock-agent get-knowledge-base --knowledge-base-id BKXE19AH89 --region "${REGION}"

# --- 2. S3 Vectors index ---
_check_gone "S3 Vectors index hera-kb-index" \
  aws s3vectors get-index --vector-bucket-name hera-kb-vectors-prod --index-name hera-kb-index --region "${REGION}"

# --- 3. S3 Vectors bucket ---
_check_gone "S3 Vectors bucket hera-kb-vectors-prod" \
  aws s3vectors get-vector-bucket --vector-bucket-name hera-kb-vectors-prod --region "${REGION}"

# --- 4. KB source bucket (D-37) ---
_check_gone "S3 source bucket hera-kb-source-prod" \
  aws s3api head-bucket --bucket hera-kb-source-prod --region "${REGION}"

# --- 5. AgentCore Runtime ---
_check_gone "AgentCore Runtime hera_agent-GIsf2P4ImD" \
  aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id hera_agent-GIsf2P4ImD --region "${REGION}"

# --- 6. CDK CFn stack hera-agentcore ---
_check_gone "CFn stack hera-agentcore" \
  aws cloudformation describe-stacks --stack-name hera-agentcore --region "${REGION}"

# (Tasks 2 + 3 of this plan extend with checks 7-19 + final summary.)
echo "----------------------------------------"
echo "Partial run (Task 1 of 04-03): ${PASS_COUNT} pass / ${FAIL_COUNT} fail (6 of 19 checks)"
exit 0  # Task 1 only ships 6 checks; final exit code logic ships in Task 2.
