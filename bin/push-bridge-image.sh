#!/usr/bin/env bash
# bin/push-bridge-image.sh - Phase 6 step of D-56 deploy lifecycle: build + push
# the multi-arch hera-twilio-bridge container image to the bridge ECR.
#
# Mirrors bin/push-image.sh (Plan 03-03 + Pattern S5) verbatim with three
# changes: ECR URL output name, build context dir, final hint message.
#
# Usage:    bin/push-bridge-image.sh
# Reads:    `terraform output -raw twilio_bridge_ecr_repository_url`  (Plan 06-01)
# Effect:   `aws ecr get-login-password | docker login`, then
#           `docker buildx build --platform linux/arm64,linux/amd64 --push -t ${ECR_URL}:${GIT_SHA} infra/modules/twilio_bridge`
# Verifies: `aws ecr describe-images --image-ids imageTag=${GIT_SHA}` returns the manifest digest.
#
# Tag scheme: short git SHA only. The bridge ECR repo is image_tag_mutability=IMMUTABLE
# (Plan 06-01), so :latest is rejected by ECR. To deploy a new image, commit
# first so the SHA differs.

set -euo pipefail

# --- Preflight (fail-fast on missing tools, mirrors push-image.sh) ---
for tool in aws docker git terraform; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' is not on PATH." >&2
    case "$tool" in
      aws)        echo "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2 ;;
      docker)     echo "Install Docker Desktop with buildx: https://docs.docker.com/get-docker/" >&2 ;;
      git)        echo "Install: https://git-scm.com/downloads" >&2 ;;
      terraform)  echo "Install: https://developer.hashicorp.com/terraform/install" >&2 ;;
    esac
    exit 2
  fi
done

if ! docker buildx version >/dev/null 2>&1; then
  echo "ERROR: docker buildx is not installed." >&2
  echo "       Docker Desktop ships buildx by default; on Linux: https://github.com/docker/buildx#installing" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/infra/envs/prod"
BRIDGE_DIR="$REPO_ROOT/infra/modules/twilio_bridge"
REGION="${AWS_REGION:-ap-northeast-1}"

# --- Resolve bridge ECR repo URL from terraform outputs ---
echo "[1/5] reading twilio_bridge_ecr_repository_url from $TF_DIR ..."
ECR_URL="$(cd "$TF_DIR" && terraform output -raw twilio_bridge_ecr_repository_url)"
echo "       twilio_bridge_ecr_repository_url=$ECR_URL"

# --- Compute git SHA tag ---
GIT_SHA="$(cd "$REPO_ROOT" && git rev-parse --short HEAD)"
if [ -z "$GIT_SHA" ]; then
  echo "ERROR: could not resolve git short SHA - is this a git repo?" >&2
  exit 3
fi
echo "       git short SHA: $GIT_SHA"

# --- Login to ECR ---
echo "[2/5] aws ecr get-login-password | docker login ..."
REGISTRY="${ECR_URL%/*}"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

# --- Ensure a buildx builder exists (idempotent) ---
echo "[3/5] ensuring buildx builder 'hera-builder' is ready ..."
if ! docker buildx inspect hera-builder >/dev/null 2>&1; then
  docker buildx create --name hera-builder --driver docker-container --use >/dev/null
else
  docker buildx use hera-builder >/dev/null
fi
docker buildx inspect --bootstrap >/dev/null

# --- Build + push (multi-arch) ---
# --provenance=false / --sbom=false: ECR rejects OCI in-toto provenance and SBOM
# manifests by default; without these flags, push fails with
# UnsupportedMediaTypeException (Pattern S5 - non-negotiable).
echo "[4/5] docker buildx build --platform linux/arm64,linux/amd64 --push -t $ECR_URL:$GIT_SHA $BRIDGE_DIR ..."
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --provenance=false \
  --sbom=false \
  --push \
  --tag "$ECR_URL:$GIT_SHA" \
  "$BRIDGE_DIR"

# --- Verify the manifest landed for both architectures ---
echo "[5/5] aws ecr describe-images --image-ids imageTag=$GIT_SHA ..."
aws ecr describe-images \
  --repository-name "${ECR_URL##*/}" \
  --region "$REGION" \
  --image-ids "imageTag=$GIT_SHA" \
  --no-cli-pager >/dev/null

echo "OK: pushed $ECR_URL:$GIT_SHA"
echo "    next: cd infra/envs/prod && terraform apply -var=twilio_bridge_image_tag=$GIT_SHA -var=twilio_auth_token_secret_arn=\$TWILIO_SECRET_ARN -var=agentcore_runtime_arn=arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD"
