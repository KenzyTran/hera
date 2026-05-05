"""Environment configuration for the Hera Pipecat agent.

All env vars are read at import time so misconfiguration fails fast at startup,
not on the first WebSocket connection. Required vars raise KeyError; optional
vars use os.environ.get() with documented defaults.
"""

import os

# Required: live Phase 1 KB id. Resolve with:
#   terraform -chdir=infra/envs/prod output -raw kb_id
KB_ID: str = os.environ["HERA_KB_ID"]

# Optional: score threshold for KB retrieve filter. Default 0.4 matches bin/verify-kb.sh.
KB_SCORE_THRESHOLD: float = float(os.environ.get("HERA_KB_SCORE_THRESHOLD", "0.4"))

# Optional: AWS region. Default ap-northeast-1 (Phase 1 prod region; Nova 2 Sonic available).
AWS_REGION: str = os.environ.get("AWS_REGION", "ap-northeast-1")

# Optional: Sonic voice id. Default matthew (masculine US neutral).
HERA_VOICE: str = os.environ.get("HERA_VOICE", "matthew")
