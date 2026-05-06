#!/usr/bin/env bash
# bin/build-widget.sh - Phase 3 widget deploy (D-25 step 3, D-27 sed-replace).
#
# Usage:  bin/build-widget.sh
# Reads:  terraform output -raw widget_s3_bucket_name, widget_cloudfront_distribution_id
# Reads:  AGENTCORE_WSS_URL env var (Plan 03-04 sets this from cdk outputs after stack deploy);
#         falls back to `terraform output -raw agentcore_wss_url` if that output exists.
# Effect: copies frontend/* into dist/widget/, sed-replaces __AGENTCORE_WSS_URL__,
#         aws s3 sync to the widget bucket, aws cloudfront create-invalidation.
#
# Source tree (frontend/) is NEVER mutated - all edits happen in dist/widget/.

set -euo pipefail

# --- Preflight (Plan 01-03 fail-fast pattern; install hints for the three platforms) ---
for tool in aws sed terraform; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' is not on PATH." >&2
    case "$tool" in
      aws)
        echo "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2 ;;
      sed)
        echo "Linux/macOS ship with sed. On Windows, run from a bash environment (Git Bash / WSL / MSYS2)." >&2 ;;
      terraform)
        echo "Install: https://developer.hashicorp.com/terraform/install" >&2 ;;
    esac
    exit 2
  fi
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/infra/envs/prod"
SRC_DIR="$REPO_ROOT/frontend"
DIST_DIR="$REPO_ROOT/dist/widget"

# --- Resolve inputs from terraform outputs ---
echo "[1/5] reading terraform outputs from $TF_DIR ..."
S3_BUCKET="$(cd "$TF_DIR" && terraform output -raw widget_s3_bucket_name)"
CF_DIST_ID="$(cd "$TF_DIR" && terraform output -raw widget_cloudfront_distribution_id)"

# AGENTCORE_WSS_URL precedence: explicit env var (Plan 03-04 sets this) > terraform output (if present).
if [ -z "${AGENTCORE_WSS_URL:-}" ]; then
  if (cd "$TF_DIR" && terraform output -raw agentcore_wss_url >/dev/null 2>&1); then
    AGENTCORE_WSS_URL="$(cd "$TF_DIR" && terraform output -raw agentcore_wss_url)"
  else
    echo "ERROR: AGENTCORE_WSS_URL is unset and 'terraform output agentcore_wss_url' is not yet populated." >&2
    echo "       Plan 03-04 'cdk deploy hera-agentcore --outputs-file' must run first." >&2
    exit 2
  fi
fi

echo "       widget_s3_bucket_name=$S3_BUCKET"
echo "       widget_cloudfront_distribution_id=$CF_DIST_ID"
echo "       AGENTCORE_WSS_URL=$AGENTCORE_WSS_URL"

# --- Build a deploy copy under dist/widget/ ---
echo "[2/5] preparing deploy copy at $DIST_DIR ..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
cp "$SRC_DIR/index.html"                "$DIST_DIR/index.html"
cp "$SRC_DIR/styles.css"                "$DIST_DIR/styles.css"
cp "$SRC_DIR/app.js"                    "$DIST_DIR/app.js"
cp "$SRC_DIR/audio-capture-worklet.js"  "$DIST_DIR/audio-capture-worklet.js"

# --- sed-replace placeholder in the deploy copy ONLY ---
# Use a delimiter that cannot appear in a WSS URL (`|`); the URL contains : and /.
# Write to a temp file then mv - portable across BSD (macOS) and GNU sed
# (BSD sed requires an explicit suffix for -i, GNU does not).
echo "[3/5] sed-replacing __AGENTCORE_WSS_URL__ in dist/widget/app.js ..."
TMP="$DIST_DIR/app.js.tmp"
sed "s|__AGENTCORE_WSS_URL__|${AGENTCORE_WSS_URL}|g" "$DIST_DIR/app.js" > "$TMP"
mv "$TMP" "$DIST_DIR/app.js"

# Sanity gate: the placeholder must not survive into the deployed artifact.
if grep -q '__AGENTCORE_WSS_URL__' "$DIST_DIR/app.js"; then
  echo "ERROR: __AGENTCORE_WSS_URL__ still present after sed-replace." >&2
  exit 3
fi
# And: the deployed artifact must not ship the localhost dev URL either.
if grep -q 'ws://localhost:8080' "$DIST_DIR/app.js"; then
  echo "ERROR: dist/widget/app.js still contains the localhost dev URL - sed targeted the wrong line." >&2
  exit 3
fi

# --- Upload ---
echo "[4/5] aws s3 sync -> s3://$S3_BUCKET/ ..."
aws s3 sync "$DIST_DIR/" "s3://$S3_BUCKET/" --delete --no-progress

# --- Invalidate CloudFront ---
# Cache: 4 paths total - invalidate /index.html /app.js /styles.css /audio-capture-worklet.js
# rather than /* so we stay below the 1000-free-paths/month threshold.
echo "[5/5] aws cloudfront create-invalidation --distribution-id $CF_DIST_ID ..."
aws cloudfront create-invalidation \
  --distribution-id "$CF_DIST_ID" \
  --paths "/index.html" "/app.js" "/styles.css" "/audio-capture-worklet.js" \
  --no-cli-pager >/dev/null

echo "OK: widget deployed."
