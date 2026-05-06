"""Environment configuration for the Hera Pipecat agent.

KB_ID and AWS_REGION resolve through env vars when present, falling back to
prod defaults baked into the image. This makes the same image work in:
- Local docker-compose (env vars from docker-compose.yml override defaults)
- Amazon Bedrock AgentCore Runtime (no env injection — defaults are used)

KB_SCORE_THRESHOLD and HERA_VOICE remain optional with documented defaults.
"""

import os

# Prod KB id baked in (live KB BKXE19AH89 in ap-northeast-1, Phase 1 D-14).
# Override via HERA_KB_ID env var for dev-against-non-prod-KB workflows.
KB_ID: str = os.environ.get("HERA_KB_ID", "BKXE19AH89")

# Optional: score threshold for KB retrieve filter. Default 0.4 matches bin/verify-kb.sh.
KB_SCORE_THRESHOLD: float = float(os.environ.get("HERA_KB_SCORE_THRESHOLD", "0.4"))

# Region default is ap-northeast-1 prod (D-14, DEP-06).
AWS_REGION: str = os.environ.get("AWS_REGION", "ap-northeast-1")

# Optional: Sonic voice id. Default matthew (masculine US neutral).
HERA_VOICE: str = os.environ.get("HERA_VOICE", "matthew")
