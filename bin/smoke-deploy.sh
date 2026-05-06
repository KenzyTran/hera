#!/usr/bin/env bash
# bin/smoke-deploy.sh -- Phase 3 end-to-end live-AWS smoke.
#
# Orchestrates the full 3-step deploy + the smoke probe in one paste-block.
# Each step has its own exit code so the operator can resume mid-stream after
# a failure.
#
# Usage:  bin/smoke-deploy.sh
# Reads:  AWS_REGION (default ap-northeast-1), terraform outputs in infra/envs/prod
# Effect: dumps tf outputs, runs cdk deploy hera-agentcore, exports
#         AGENTCORE_WSS_URL, runs bin/build-widget.sh, curls /ping over the
#         public CloudFront URL, runs bin/_smoke_deploy_probe.py against the
#         AgentCore WSS endpoint.

set -euo pipefail

# --- Preflight ---
for tool in aws docker git terraform jq curl uv; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' is not on PATH." >&2
    case "$tool" in
      uv) echo "Install: https://docs.astral.sh/uv/getting-started/installation/" >&2 ;;
      *)  : ;;
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

# --- Step 1: dump terraform outputs (CDK reads them) ---
echo "[1/6] terraform output -json > terraform-outputs.json ..."
(cd "$TF_DIR" && terraform output -json > terraform-outputs.json)

# --- Step 2: cdk deploy hera-agentcore ---
GIT_SHA="$(cd "$REPO_ROOT" && git rev-parse --short HEAD)"
echo "[2/6] cdk deploy hera-agentcore --context image_tag=$GIT_SHA ..."
(cd "$CDK_DIR" && uv run cdk deploy hera-agentcore \
  --context "image_tag=$GIT_SHA" \
  --outputs-file "$DIST_DIR/cdk-outputs.json" \
  --require-approval never)

# --- Step 3: extract AGENTCORE_WSS_URL from cdk outputs ---
echo "[3/6] reading AgentCoreWssUrl from $DIST_DIR/cdk-outputs.json ..."
AGENTCORE_WSS_URL="$(jq -r '."hera-agentcore".AgentCoreWssUrl' "$DIST_DIR/cdk-outputs.json")"
if [ -z "$AGENTCORE_WSS_URL" ] || [ "$AGENTCORE_WSS_URL" = "null" ]; then
  echo "ERROR: AgentCoreWssUrl is empty/null in cdk-outputs.json." >&2
  echo "       Check infra/cdk/hera_agentcore/stack.py outputs." >&2
  exit 3
fi
export AGENTCORE_WSS_URL
echo "       AGENTCORE_WSS_URL=$AGENTCORE_WSS_URL"

# --- Step 4: deploy widget (sed-replace + s3 sync + CloudFront invalidate) ---
echo "[4/6] bin/build-widget.sh ..."
"$REPO_ROOT/bin/build-widget.sh"

CF_URL="$(cd "$TF_DIR" && terraform output -raw widget_cloudfront_url)"
echo "       widget URL: $CF_URL"

# --- Step 5: HTTPS reachability check on the widget ---
echo "[5/6] curl -fsS $CF_URL/ ..."
curl -fsS "$CF_URL/" -o /dev/null
echo "       OK: 200 from $CF_URL/"

# --- Step 6: live WS smoke probe ---
echo "[6/6] uv run python bin/_smoke_deploy_probe.py (budget 10s) ..."
(cd "$REPO_ROOT/agent" && AGENTCORE_WSS_URL="$AGENTCORE_WSS_URL" uv run python "$REPO_ROOT/bin/_smoke_deploy_probe.py")

echo ""
echo "OK: Phase 3 smoke passed."
echo "    Widget URL : $CF_URL"
echo "    WSS URL    : $AGENTCORE_WSS_URL"
echo "    Image tag  : $GIT_SHA"
