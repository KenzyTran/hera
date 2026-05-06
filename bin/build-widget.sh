#!/usr/bin/env bash
# bin/build-widget.sh - Phase 3 widget deploy (D-25 step 5, Plan 03-04 Rule-4 update).
#
# Usage:  bin/build-widget.sh
# Reads:  terraform output -raw widget_s3_bucket_name, widget_cloudfront_distribution_id
# Reads:  PRESIGN_URL env var (Plan 03-04 Step 3.5 set this to the Lambda
#         Function URL); falls back to `terraform output -raw presign_url`.
# Effect: copies frontend/* into dist/widget/, sed-replaces __PRESIGN_URL__,
#         aws s3 sync to the widget bucket, aws cloudfront create-invalidation.
#
# Source tree (frontend/) is NEVER mutated - all edits happen in dist/widget/.
#
# Wire format change vs Plan 03-02 baseline (Rule-4 deviation): the placeholder
# is now __PRESIGN_URL__ (a Lambda Function URL https://...lambda-url...) NOT
# __AGENTCORE_WSS_URL__ (a wss://...). The widget itself fetches the
# presigner and then opens the returned wss URL. See SUMMARY.md for context.

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

# PRESIGN_URL precedence: explicit env var (Plan 03-04 Step 3.5 sets this) > terraform output (if present).
if [ -z "${PRESIGN_URL:-}" ]; then
  if (cd "$TF_DIR" && terraform output -raw presign_url >/dev/null 2>&1); then
    PRESIGN_URL="$(cd "$TF_DIR" && terraform output -raw presign_url)"
  else
    echo "ERROR: PRESIGN_URL is unset and 'terraform output presign_url' is not yet populated." >&2
    echo "       Plan 03-04 Step 3.5 'terraform apply -var=agentcore_runtime_arn=<arn>' must run first." >&2
    exit 2
  fi
fi

echo "       widget_s3_bucket_name=$S3_BUCKET"
echo "       widget_cloudfront_distribution_id=$CF_DIST_ID"
echo "       PRESIGN_URL=$PRESIGN_URL"

# --- Build a deploy copy under dist/widget/ ---
echo "[2/5] preparing deploy copy at $DIST_DIR ..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
cp "$SRC_DIR/index.html"                "$DIST_DIR/index.html"
cp "$SRC_DIR/styles.css"                "$DIST_DIR/styles.css"
cp "$SRC_DIR/app.js"                    "$DIST_DIR/app.js"
cp "$SRC_DIR/audio-capture-worklet.js"  "$DIST_DIR/audio-capture-worklet.js"

# --- sed-replace placeholder in the deploy copy ONLY ---
# Use a delimiter that cannot appear in the URL (`|`); the URL contains : and /.
# Write to a temp file then mv - portable across BSD (macOS) and GNU sed
# (BSD sed requires an explicit suffix for -i, GNU does not).
echo "[3/5] sed-replacing __PRESIGN_URL__ in dist/widget/app.js ..."
TMP="$DIST_DIR/app.js.tmp"
sed "s|__PRESIGN_URL__|${PRESIGN_URL}|g" "$DIST_DIR/app.js" > "$TMP"
mv "$TMP" "$DIST_DIR/app.js"

# Sanity gate: the placeholder must not survive into the deployed artifact.
if grep -q '__PRESIGN_URL__' "$DIST_DIR/app.js"; then
  echo "ERROR: __PRESIGN_URL__ still present after sed-replace." >&2
  exit 3
fi
# And: the deployed artifact must not ship the localhost dev URL either
# (the typeof guard SHOULD select the presign branch in production).
if grep -q 'ws://localhost:8080' "$DIST_DIR/app.js"; then
  # The local-dev sentinel is fine to ship as long as the typeof check
  # selects the production branch; this grep is informational only.
  echo "       note: WS_LOCAL_DEV_URL still present (expected; typeof guard selects presign branch in prod)."
fi

# --- Upload ---
echo "[4/5] aws s3 sync -> s3://$S3_BUCKET/ ..."
aws s3 sync "$DIST_DIR/" "s3://$S3_BUCKET/" --delete --no-progress

# --- Invalidate CloudFront ---
# CloudFront free tier = 1000 paths/month. /* counts as ONE invalidation path
# so it's well within free tier even for daily deploys. The multi-path form
# was failing on Windows bash with InvalidArgument; /* is simpler and works
# cross-platform.
echo "[5/5] aws cloudfront create-invalidation --distribution-id $CF_DIST_ID ..."
aws cloudfront create-invalidation \
  --distribution-id "$CF_DIST_ID" \
  --paths "/*" \
  --no-cli-pager >/dev/null

echo "OK: widget deployed."
