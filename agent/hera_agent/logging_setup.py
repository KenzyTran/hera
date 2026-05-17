"""CloudWatch log shipping for AgentCore Runtime container.

AgentCore Runtime does NOT auto-route container stdout/stderr to CloudWatch.
We need to push our own log events to the configured log group so operators
can observe what happens inside /ws (Pipecat pipeline, Sonic bidi stream, KB
tool calls). Local docker-compose dev skips this (env var HERA_LOG_GROUP unset).
"""

import logging
import os
import socket
import sys

import boto3
import watchtower
from loguru import logger


def configure_logging() -> None:
    """Wire loguru + uvicorn stdlib logging to CloudWatch when in production."""
    log_group = os.environ.get("HERA_LOG_GROUP")
    if not log_group:
        return

    region = os.environ.get("AWS_REGION", "ap-northeast-1")
    stream = f"runtime/{socket.gethostname()}"
    cw_client = boto3.client("logs", region_name=region)
    handler = watchtower.CloudWatchLogHandler(
        log_group_name=log_group,
        log_stream_name=stream,
        boto3_client=cw_client,
        create_log_group=False,
        send_interval=2,
    )
    handler.setLevel(logging.DEBUG)

    logger.add(handler, level="DEBUG", serialize=False)

    for name in ("uvicorn", "uvicorn.access", "uvicorn.error", "fastapi"):
        std_logger = logging.getLogger(name)
        std_logger.addHandler(handler)
        std_logger.setLevel(logging.DEBUG)

    logger.info(f"CloudWatch logging enabled: group={log_group} stream={stream}")
    sys.stderr.write(f"CloudWatch logging enabled: group={log_group} stream={stream}\n")
