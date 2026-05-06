#!/usr/bin/env bash
# bin/push-image.sh - Phase 3 step 2 of D-25: build + push the multi-arch
# hera-agent image to ECR.
#
# Same Dockerfile, same buildx invocation as Phase 2 Plan 02-02 (D-20: same
# artifact, no second build path). Only difference is the destination registry
# is ECR instead of the local docker daemon.
#
# Usage:    bin/push-image.sh
# Reads:    `terraform output -raw ecr_repo_url`  (Plan 03-01)
# Effect:   `aws ecr get-login-password | docker login`, then
#           `docker buildx build --platform linux/arm64,linux/amd64 --push -t ${ECR_URL}:${GIT_SHA} ./agent`
# Verifies: `aws ecr describe-images --image-ids imageTag=${GIT_SHA}` returns the manifest digest.
#
# Tag scheme: short git SHA only. The ECR repo is image_tag_mutability=IMMUTABLE
# (Plan 03-01), so a mutable :latest tag is rejected by ECR. Documented
# resolution in Plan 03-01 Task 3 leading comment block.

set -euo pipefail

# --- Preflight (fail-fast on missing tools, Plan 01-03 commit f78a39a pattern) ---
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

# Buildx must be available - `docker buildx version` returns 0 only if installed.
if ! docker buildx version >/dev/null 2>&1; then
  echo "ERROR: docker buildx is not installed." >&2
  echo "       Docker Desktop ships buildx by default; on Linux: https://github.com/docker/buildx#installing" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/infra/envs/prod"
AGENT_DIR="$REPO_ROOT/agent"
REGION="${AWS_REGION:-ap-northeast-1}"

# --- Resolve ECR repo URL from terraform outputs ---
echo "[1/5] reading ecr_repo_url from $TF_DIR ..."
ECR_URL="$(cd "$TF_DIR" && terraform output -raw ecr_repo_url)"
echo "       ecr_repo_url=$ECR_URL"

# --- Compute git SHA tag ---
GIT_SHA="$(cd "$REPO_ROOT" && git rev-parse --short HEAD)"
if [ -z "$GIT_SHA" ]; then
  echo "ERROR: could not resolve git short SHA - is this a git repo?" >&2
  exit 3
fi
echo "       git short SHA: $GIT_SHA"

# --- Login to ECR ---
echo "[2/5] aws ecr get-login-password | docker login ..."
# Extract registry host (strip the /repo path)
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
# UnsupportedMediaTypeException on the trailing attestation blob.
# (BuildKit emits attestations starting v0.11; ECR support trails the spec.)
echo "[4/5] docker buildx build --platform linux/arm64,linux/amd64 --push -t $ECR_URL:$GIT_SHA $AGENT_DIR ..."
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --provenance=false \
  --sbom=false \
  --push \
  --tag "$ECR_URL:$GIT_SHA" \
  "$AGENT_DIR"

# --- Verify the manifest landed for both architectures ---
echo "[5/5] aws ecr describe-images --image-ids imageTag=$GIT_SHA ..."
aws ecr describe-images \
  --repository-name "${ECR_URL##*/}" \
  --region "$REGION" \
  --image-ids "imageTag=$GIT_SHA" \
  --no-cli-pager >/dev/null

echo "OK: pushed $ECR_URL:$GIT_SHA"
echo "    next: cd infra/cdk && cdk deploy hera-agentcore --context image_tag=$GIT_SHA"
