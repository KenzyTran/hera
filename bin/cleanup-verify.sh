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

# --- 7. CW log group /aws/bedrock-agentcore/hera-agent ---
_check_count_zero "CW log group /aws/bedrock-agentcore/hera-agent" \
  env MSYS_NO_PATHCONV=1 aws logs describe-log-groups \
    --log-group-name-prefix /aws/bedrock-agentcore/hera-agent \
    --region "${REGION}" \
    --query 'logGroups | length(@)' --output text

# --- 8. CW log group /aws/lambda/hera-widget-presign-prod ---
_check_count_zero "CW log group /aws/lambda/hera-widget-presign-prod" \
  env MSYS_NO_PATHCONV=1 aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/hera-widget-presign-prod \
    --region "${REGION}" \
    --query 'logGroups | length(@)' --output text

# --- 9. IAM role hera-agentcore-exec-prod ---
_check_gone "IAM role hera-agentcore-exec-prod" \
  aws iam get-role --role-name hera-agentcore-exec-prod

# --- 10. IAM role hera-widget-presign-prod-exec ---
_check_gone "IAM role hera-widget-presign-prod-exec" \
  aws iam get-role --role-name hera-widget-presign-prod-exec

# --- 11. IAM role hera-kb-service-role (A5 resolved 2026-05-06: actual name
# from `terraform state show module.knowledge_base.aws_iam_role.kb_service_role`
# is hera-kb-service-role, NOT hera-kb-service-prod). ---
_check_gone "IAM role hera-kb-service-role" \
  aws iam get-role --role-name hera-kb-service-role

# --- 12. IAM policy hera-kb-retrieve-prod ---
_check_count_zero "IAM policy hera-kb-retrieve-prod" \
  aws iam list-policies --scope Local \
    --query "Policies[?PolicyName=='hera-kb-retrieve-prod'] | length(@)" --output text

# --- 13. ECR repo hera-agent ---
_check_gone "ECR repo hera-agent" \
  aws ecr describe-repositories --repository-names hera-agent --region "${REGION}"

# --- 14. CloudFront distribution E10K3B1L8PQ9EC ---
_check_gone "CloudFront distribution E10K3B1L8PQ9EC" \
  aws cloudfront get-distribution --id E10K3B1L8PQ9EC

# --- 15. S3 widget bucket hera-widget-prod ---
_check_gone "S3 widget bucket hera-widget-prod" \
  aws s3api head-bucket --bucket hera-widget-prod --region "${REGION}"

# --- 16. Lambda hera-widget-presign-prod ---
_check_gone "Lambda hera-widget-presign-prod" \
  aws lambda get-function --function-name hera-widget-presign-prod --region "${REGION}"

# --- 17. Billing alarm hera-billing-prod (us-east-1) ---
_check_count_zero "Billing alarm hera-billing-prod (us-east-1)" \
  aws cloudwatch describe-alarms \
    --alarm-names hera-billing-prod \
    --region "${BILLING_REGION}" \
    --query 'MetricAlarms | length(@)' --output text

# --- 18. Op alarm hera-error-rate-prod (ap-northeast-1) ---
_check_count_zero "Op alarm hera-error-rate-prod" \
  aws cloudwatch describe-alarms \
    --alarm-names hera-error-rate-prod \
    --region "${REGION}" \
    --query 'MetricAlarms | length(@)' --output text

# --- 18b. Op alarm hera-latency-p95-prod (ap-northeast-1) ---
_check_count_zero "Op alarm hera-latency-p95-prod" \
  aws cloudwatch describe-alarms \
    --alarm-names hera-latency-p95-prod \
    --region "${REGION}" \
    --query 'MetricAlarms | length(@)' --output text

# --- 19. Dashboard hera-prod ---
_check_gone "Dashboard hera-prod" \
  aws cloudwatch get-dashboard --dashboard-name hera-prod --region "${REGION}"

# --- final summary + cleanup-contract hints on FAIL ---
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "----------------------------------------"
echo "cleanup-verify: ${PASS_COUNT}/${TOTAL} resources verified clean"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: ${FAIL_COUNT} resource(s) still exist." >&2
  echo "" >&2
  echo "Hints:" >&2
  echo "  - Did you run 'cdk destroy hera-agentcore' BEFORE 'terraform destroy'?" >&2
  echo "    (D-24 cleanup-contract: CDK owns AgentCore Runtime which holds the IAM" >&2
  echo "    exec role TF tries to delete.)" >&2
  echo "  - ECR repo 'hera-agent' still exists with image tags?" >&2
  echo "    Run 'aws ecr batch-delete-image --repository-name hera-agent --image-ids" >&2
  echo "    imageTag=<tag>' for each remaining tag, or set var.force_delete=true and" >&2
  echo "    re-run terraform destroy." >&2
  echo "  - CloudFront distribution still exists?" >&2
  echo "    terraform destroy may have been interrupted during the 15-30 min" >&2
  echo "    disable-then-delete cycle. Re-run terraform destroy." >&2
  exit 1
fi

echo "OK (cleanup): all hera resources removed"
exit 0
