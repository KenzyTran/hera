#!/usr/bin/env bash
# bin/cleanup-verify-twilio.sh - Phase 6 Twilio bridge cleanup verification (D-62, D-63).
# Runs AFTER operator: (1) released Twilio number + deleted TwiML Bin in console,
# (2) terraform destroy in infra/envs/prod, (3) deleted Secrets Manager secret.
# Read-only: never invokes destroy commands. Mirrors bin/cleanup-verify.sh
# pattern verbatim (Pattern S6/S7/S8).
#
# Resource list verbatim from .planning/phases/06-*/06-PATTERNS.md
# bin/cleanup-verify-twilio.sh table + CONTEXT.md `<specifics>` cleanup section.
#
# Usage:
#   export TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#   export TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#   bash bin/cleanup-verify-twilio.sh
#
# Reads:  HERA_REGION (default ap-northeast-1), TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN
# Effect: ~9 read-only API calls (AWS + Twilio); prints OK/FAIL per resource + final tally.

set -euo pipefail

# --- preflight: required tools ---
command -v aws  >/dev/null 2>&1 || { echo "ERROR: aws CLI not found on PATH (RUNBOOK Pre-flight)" >&2; exit 2; }
command -v jq   >/dev/null 2>&1 || { echo "ERROR: jq not found on PATH. Install: winget install jqlang.jq (Windows), brew install jq (macOS), apt-get install jq (Debian/Ubuntu)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found on PATH (Twilio REST checks need it)" >&2; exit 2; }

# --- preflight: required env vars (Twilio side) ---
: "${TWILIO_ACCOUNT_SID:?ERROR: paste TWILIO_ACCOUNT_SID before running (Twilio Console -> Account -> API keys & tokens)}"
: "${TWILIO_AUTH_TOKEN:?ERROR: paste TWILIO_AUTH_TOKEN before running}"

REGION="${HERA_REGION:-ap-northeast-1}"
PASS_COUNT=0
FAIL_COUNT=0

# ServiceNotFound added for App Runner; rest mirrors bin/cleanup-verify.sh.
GONE_REGEX='ResourceNotFound|NoSuchEntity|NotFound|RepositoryNotFound|ServiceNotFound|does not exist|404|ServiceNotFoundException'

echo "cleanup-verify-twilio against ${REGION} + Twilio account ${TWILIO_ACCOUNT_SID:0:8}..."
echo "----------------------------------------"

# --- helpers: identical to bin/cleanup-verify.sh ---
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

# --- 1. App Runner service hera-twilio-bridge-prod ---
_check_count_zero "App Runner service hera-twilio-bridge-prod" \
  aws apprunner list-services \
    --query "ServiceSummaryList[?ServiceName=='hera-twilio-bridge-prod'] | length(@)" \
    --output text \
    --region "${REGION}"

# --- 2. App Runner auto-scaling configuration hera-twilio-bridge-asc-prod ---
_check_count_zero "App Runner auto-scaling configuration hera-twilio-bridge-asc-prod" \
  aws apprunner list-auto-scaling-configurations \
    --query "AutoScalingConfigurationSummaryList[?AutoScalingConfigurationName=='hera-twilio-bridge-asc-prod'] | length(@)" \
    --output text \
    --region "${REGION}"

# --- 3. ECR repo hera-twilio-bridge ---
_check_gone "ECR repo hera-twilio-bridge" \
  aws ecr describe-repositories --repository-names hera-twilio-bridge --region "${REGION}"

# --- 4. IAM role hera-twilio-bridge-instance-prod ---
_check_gone "IAM role hera-twilio-bridge-instance-prod" \
  aws iam get-role --role-name hera-twilio-bridge-instance-prod

# --- 5. IAM role hera-twilio-bridge-access-prod ---
_check_gone "IAM role hera-twilio-bridge-access-prod" \
  aws iam get-role --role-name hera-twilio-bridge-access-prod

# --- 6. CW log group /aws/apprunner/hera-twilio-bridge-prod ---
_check_count_zero "CW log group /aws/apprunner/hera-twilio-bridge-prod" \
  env MSYS_NO_PATHCONV=1 aws logs describe-log-groups \
    --log-group-name-prefix /aws/apprunner/hera-twilio-bridge-prod \
    --region "${REGION}" \
    --query 'logGroups | length(@)' --output text

# --- 7. Secrets Manager secret hera/twilio/auth-token ---
# Operator deletes this manually (it's their Twilio token; not Terraform-owned).
# Asserting gone closes T-06-01-04 once the operator has dropped it.
_check_gone "Secrets Manager secret hera/twilio/auth-token" \
  aws secretsmanager describe-secret --secret-id hera/twilio/auth-token --region "${REGION}"

# --- 8. Twilio incoming phone numbers tagged for hera-twilio-bridge ---
TWILIO_API="https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}"
TWILIO_AUTH="${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}"

NUMBERS_COUNT=$(curl -s -u "${TWILIO_AUTH}" "${TWILIO_API}/IncomingPhoneNumbers.json" \
  | jq '[.incoming_phone_numbers[] | select(.friendly_name | test("hera"; "i"))] | length' 2>/dev/null \
  || echo "ERR")
if [[ "${NUMBERS_COUNT}" == "0" ]]; then
  echo "OK: Twilio IncomingPhoneNumbers (hera-tagged) count = 0"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: Twilio IncomingPhoneNumbers (hera-tagged) count = ${NUMBERS_COUNT}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- 9. Twilio TwiML Bins tagged for hera ---
# The TwiML Bins API endpoint can vary across Twilio account regions.
# https://serverless.twilio.com/v1/TwimlBins is the documented public endpoint
# but may return 404 for accounts that have never created a TwiML Bin
# (which our cleanup target is). Treat 404 as OK (zero TwiML Bins).
TWIML_RESP=$(curl -sw "\n%{http_code}" -u "${TWILIO_AUTH}" "https://serverless.twilio.com/v1/TwimlBins" 2>/dev/null || echo "ERR")
TWIML_HTTP="$(echo "$TWIML_RESP" | tail -n1)"
TWIML_BODY="$(echo "$TWIML_RESP" | sed '$d')"
if [[ "$TWIML_HTTP" == "404" ]]; then
  echo "OK: Twilio TwiML Bins endpoint 404 (no bins remain on account)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  TWIML_COUNT=$(echo "$TWIML_BODY" | jq '[.twiml_bins[]? | select(.friendly_name | test("hera"; "i"))] | length' 2>/dev/null || echo "ERR")
  if [[ "${TWIML_COUNT}" == "0" ]]; then
    echo "OK: Twilio TwiML Bins (hera-tagged) count = 0"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: Twilio TwiML Bins (hera-tagged) count = ${TWIML_COUNT}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
fi

# --- final summary + cleanup-contract hints on FAIL ---
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "----------------------------------------"
echo "cleanup-verify-twilio: ${PASS_COUNT}/${TOTAL} resources verified clean"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: ${FAIL_COUNT} leftover(s) detected." >&2
  echo "" >&2
  echo "Hints (cleanup quy trinh order matters!):" >&2
  echo "  - Did you release the Twilio phone number in console BEFORE terraform destroy?" >&2
  echo "    (Twilio Console -> Phone Numbers -> Manage -> Active numbers -> Release)" >&2
  echo "  - Did you delete the TwiML Bin 'hera-bridge-prod' in console?" >&2
  echo "  - Did 'terraform destroy' complete without error in infra/envs/prod?" >&2
  echo "  - Did you 'aws secretsmanager delete-secret --secret-id hera/twilio/auth-token --region ap-northeast-1 --force-delete-without-recovery' to drop the Auth Token secret?" >&2
  echo "  - App Runner deletes can take 60-90s; if 'still exists' on first run, retry after 2 min." >&2
  exit 1
fi

echo "OK (cleanup-twilio): all phase 6 resources removed"
exit 0
