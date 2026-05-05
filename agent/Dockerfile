# syntax=docker/dockerfile:1.7
# Hera Pipecat agent - Phase 2 container.
#
# Built multi-arch (linux/arm64,linux/amd64) so the SAME image serves local AMD64
# dev (docker compose up) AND Phase 3 AgentCore Runtime ARM64 deployment.
# The Pipecat aws-nova-sonic extra requires Python 3.12 (Pitfall A).
# Do NOT add `FROM --platform=linux/arm64 ...` - that would break local AMD64
# dev (Pitfall C). docker buildx orchestrates the per-arch layers via the
# TARGETPLATFORM / BUILDPLATFORM args.

# Pinned to the uv version verified during Phase 2 AGT-04 (uv 0.10.8).
# Bump deliberately when needed; do not float on :python3.12-trixie-slim.
FROM ghcr.io/astral-sh/uv:0.10.8-python3.12-trixie-slim AS base

ARG TARGETPLATFORM
ARG BUILDPLATFORM

WORKDIR /app

# Layer 1: dependency install. Bind-mounts the lockfile + manifest so this
# layer is cached unless those two files change. --no-install-project keeps
# this layer independent of the source code.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --frozen --no-install-project

# Layer 2: project source. Copy the package and the manifest, then run a
# second uv sync to install the project itself (now that source is present).
COPY hera_agent /app/hera_agent
COPY pyproject.toml uv.lock /app/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen

# Non-root user (security threat T-02-02-01 mitigation).
RUN useradd --create-home --uid 1000 appuser && chown -R appuser:appuser /app
USER appuser

ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8080

# Health probe matches AgentCore Runtime contract (GET /ping returning Healthy).
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/ping').read()"]

CMD ["uvicorn", "hera_agent.main:app", "--host", "0.0.0.0", "--port", "8080"]
