# syntax=docker/dockerfile:1.7
# Hera Twilio Bridge - Phase 6 container.
#
# Runs on AWS App Runner with min-instances=0 (D-56) — long-running Python
# FastAPI process that holds the per-call upstream WSS to bedrock-agentcore
# for the duration of a phone call. Multi-arch (linux/arm64,linux/amd64).
#
# Python 3.13 is required (D-59) because audioop-lts is a verbatim drop-in
# for stdlib audioop which was removed in 3.13 per PEP 594. The agent
# container (Phase 2) pins 3.12 because Pipecat aws-nova-sonic still pulls
# from stdlib audio paths; the bridge does NOT run Pipecat (it talks
# directly to AgentCore data-plane), so 3.13 is safe and forward-correct.
#
# Do NOT pin a per-arch platform on the FROM directive — that would break
# local AMD64 smoke. docker buildx orchestrates per-arch layers via the
# TARGETPLATFORM / BUILDPLATFORM args.

FROM ghcr.io/astral-sh/uv:0.10.8-python3.13-trixie-slim AS base

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
COPY src /app/src
COPY pyproject.toml uv.lock /app/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen

# Non-root user (security threat T-06-02-01 mitigation).
RUN useradd --create-home --uid 1000 appuser && chown -R appuser:appuser /app
USER appuser

ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8080

# App Runner health probe contract (GET /ping returning HTTP 200).
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/ping').read()"]

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
