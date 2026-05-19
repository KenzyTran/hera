"""CDK app entry point.

Phase 3 IaC split (D-24): this CDK project owns ONE stack (`hera-agentcore`)
containing only the AgentCore Runtime resource. Everything else (KB, IAM, ECR,
log group, S3 + CloudFront widget hosting, KB consumer policy) is Terraform.

The TF -> CDK bridge: `app.py` reads the terraform outputs JSON file from
`../envs/prod/terraform-outputs.json` (operator generates with
`terraform output -json > terraform-outputs.json` before `cdk deploy`). All
cross-tool data flows TF -> CDK; never the reverse.

The image tag (short git SHA) is passed via `--context image_tag=...` so each
deploy targets a deterministic ECR image manifest (D-25).
"""

import json
import os
import pathlib

import aws_cdk as cdk

from hera_agentcore.stack import HeraAgentCoreStack

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TF_OUTPUTS_PATH = REPO_ROOT / "infra" / "envs" / "prod" / "terraform-outputs.json"


def load_tf_outputs() -> dict:
    """Read `terraform output -json` file produced by the operator."""
    if not TF_OUTPUTS_PATH.exists():
        raise RuntimeError(
            f"Missing {TF_OUTPUTS_PATH}. Run: "
            f"cd infra/envs/prod && terraform output -json > terraform-outputs.json"
        )
    with TF_OUTPUTS_PATH.open() as f:
        raw = json.load(f)
    # `terraform output -json` wraps each value in {value, type, sensitive}.
    return {k: v["value"] for k, v in raw.items()}


app = cdk.App()

tf = load_tf_outputs()
image_tag = app.node.try_get_context("image_tag")
if not image_tag:
    raise RuntimeError(
        "Missing --context image_tag=<short-git-sha>. Use bin/push-image.sh first."
    )

HeraAgentCoreStack(
    app,
    "hera-agentcore",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", "851725411875"),
        region=os.environ.get("AWS_REGION", "ap-northeast-1"),
    ),
    ecr_repo_url=tf["ecr_repo_url"],
    image_tag=image_tag,
    exec_role_arn=tf["agentcore_exec_role_arn"],
    kb_id=tf["kb_id"],
    langfuse_public_key=os.environ.get("LANGFUSE_PUBLIC_KEY", ""),
    langfuse_secret_key=os.environ.get("LANGFUSE_SECRET_KEY", ""),
    langfuse_host=os.environ.get("LANGFUSE_HOST", ""),
)

app.synth()
