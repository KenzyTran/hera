#!/usr/bin/env bash
# bin/smoke-deploy.sh -- Phase 3 end-to-end live-AWS smoke (Plan 03-04 Rule-4 update).
#
# Orchestrates the full 4-step deploy + the smoke probe in one paste-block.
# Each step has its own exit code so the operator can resume mid-stream after
# a failure.
#
# Usage:  bin/smoke-deploy.sh
# Reads:  AWS_REGION (default ap-northeast-1), terraform outputs in infra/envs/prod
# Effect: dumps tf outputs, runs cdk deploy hera-agentcore, captures the runtime
#         ARN, second-pass terraform apply to wire the widget_presigner Lambda,
#         exports PRESIGN_URL, runs bin/build-widget.sh, curls /ping over the
#         public CloudFront URL, curls the presign Function URL, runs
#         bin/_smoke_deploy_probe.py against the AgentCore WSS endpoint via
#         the presign flow.

set -euo pipefail

# --- Preflight ---
for tool in aws docker git terraform jq curl uv cdk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' is not on PATH." >&2
    case "$tool" in
      uv)  echo "Install: https://docs.astral.sh/uv/getting-started/installation/" >&2 ;;
      cdk) echo "Install: npm install -g aws-cdk (>=2.150.0)" >&2 ;;
      *)   : ;;
    esac
    exit 2
  fi
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/infra/envs/prod"
CDK_DIR="$REPO_ROOT/infra/cdk"
DIST_DIR="$REPO_ROOT/dist"
REGION="${AWS_REGION:-ap-northeast-1}"
export AWS_REGION="$REGION"

mkdir -p "$DIST_DIR"

# Source Langfuse keys if .env.langfuse exists. CDK reads LANGFUSE_* from
# process env and bakes them into the runtime's EnvironmentVariables so
# tracing works on first connect. If the file is absent we deploy without
# tracing and the SDK wrappers no-op (this is fine, just no Langfuse traces).
if [ -f "$REPO_ROOT/.env.langfuse" ]; then
  echo "[0/8] sourcing .env.langfuse (tracing on)"
  set -a; . "$REPO_ROOT/.env.langfuse"; set +a
else
  echo "[0/8] .env.langfuse not found -- deploying without Langfuse tracing"
fi

# --- Step 1: dump terraform outputs (CDK reads them) ---
echo "[1/8] terraform output -json > terraform-outputs.json ..."
(cd "$TF_DIR" && terraform output -json > terraform-outputs.json)

# --- Step 2: cdk deploy hera-agentcore ---
# `cdk` is the Node CLI on PATH; do NOT prefix `uv run` (uv does not proxy
# Node binaries -- spawns fail with "program not found").
GIT_SHA="$(cd "$REPO_ROOT" && git rev-parse --short HEAD)"
echo "[2/8] cdk deploy hera-agentcore --context image_tag=$GIT_SHA ..."
(cd "$CDK_DIR" && cdk deploy hera-agentcore \
  --context "image_tag=$GIT_SHA" \
  --outputs-file "$DIST_DIR/cdk-outputs.json" \
  --require-approval never)

# --- Step 3: extract AgentCoreRuntimeArn from cdk outputs ---
echo "[3/8] reading AgentCoreRuntimeArn from $DIST_DIR/cdk-outputs.json ..."
RUNTIME_ARN="$(jq -r '."hera-agentcore".AgentCoreRuntimeArn' "$DIST_DIR/cdk-outputs.json")"
if [ -z "$RUNTIME_ARN" ] || [ "$RUNTIME_ARN" = "null" ]; then
  echo "ERROR: AgentCoreRuntimeArn is empty/null in cdk-outputs.json." >&2
  exit 3
fi
echo "       AgentCoreRuntimeArn=$RUNTIME_ARN"

# --- Step 4: second-pass terraform apply to wire widget_presigner to the runtime ARN ---
echo "[4/8] terraform apply -var=agentcore_runtime_arn=<arn> (widget_presigner update) ..."
(cd "$TF_DIR" && terraform apply -var "agentcore_runtime_arn=${RUNTIME_ARN}" -auto-approve)

# Re-dump outputs after the second apply (presign_url is now populated).
(cd "$TF_DIR" && terraform output -json > terraform-outputs.json)

# --- Step 5: read presign_url from terraform outputs ---
echo "[5/8] reading presign_url from terraform output ..."
PRESIGN_URL="$(cd "$TF_DIR" && terraform output -raw presign_url)"
if [ -z "$PRESIGN_URL" ] || [ "$PRESIGN_URL" = "null" ]; then
  echo "ERROR: presign_url is empty/null after terraform apply." >&2
  exit 3
fi
export PRESIGN_URL
echo "       PRESIGN_URL=$PRESIGN_URL"

# --- Step 6: deploy widget (sed-replace + s3 sync + CloudFront invalidate) ---
echo "[6/8] bin/build-widget.sh ..."
"$REPO_ROOT/bin/build-widget.sh"

CF_URL="$(cd "$TF_DIR" && terraform output -raw widget_cloudfront_url)"
echo "       widget URL: $CF_URL"

# --- Step 7: HTTPS reachability checks (widget + presigner) ---
echo "[7/8] curl -fsS $CF_URL/ ..."
curl -fsS "$CF_URL/" -o /dev/null
echo "       OK: 200 from $CF_URL/"

echo "       curl -fsS $PRESIGN_URL ..."
PRESIGN_BODY="$(curl -fsS "$PRESIGN_URL")"
echo "       OK: 200 from presigner -- body: ${PRESIGN_BODY:0:120}..."

# Sanity: presigner returned a wss:// URL.
if ! echo "$PRESIGN_BODY" | jq -e '.url | startswith("wss://")' >/dev/null; then
  echo "ERROR: presigner did not return {\"url\": \"wss://...\"}." >&2
  echo "       body: $PRESIGN_BODY" >&2
  exit 3
fi

# --- Step 8: live WS smoke probe (drives the same presign flow the browser uses) ---
echo "[8/8] uv run python bin/_smoke_deploy_probe.py (presign + WSS connect, budget 10s) ..."
(cd "$REPO_ROOT/agent" && PRESIGN_URL="$PRESIGN_URL" uv run python "$REPO_ROOT/bin/_smoke_deploy_probe.py")

echo ""
echo "OK: Phase 3 smoke passed."
echo "    Widget URL  : $CF_URL"
echo "    Presign URL : $PRESIGN_URL"
echo "    Runtime ARN : $RUNTIME_ARN"
echo "    Image tag   : $GIT_SHA"
