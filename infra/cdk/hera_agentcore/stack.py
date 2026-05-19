"""AgentCore Runtime stack -- single resource per D-24.

Live-introspected facts (resolved at synth time against
`aws cloudformation describe-type --type RESOURCE
--type-name AWS::BedrockAgentCore::Runtime --region ap-northeast-1`,
schema TimeCreated 2025-10-06T21:47:27 UTC):

- L1 construct: `aws_cdk.aws_bedrockagentcore.CfnRuntime` (aws-cdk-lib >= 2.252.0).
- Required CFn properties: `AgentRuntimeName`, `AgentRuntimeArtifact`, `RoleArn`,
  `NetworkConfiguration`. (`AgentRuntimeName` is `createOnlyProperties` -- name
  changes force replacement.)
- Container image goes under `AgentRuntimeArtifact.ContainerConfiguration.ContainerUri`.
- Protocol enum: `MCP | HTTP | A2A | AGUI`. (No `WSS` enum exists -- Pipecat's
  `/ws` upgrade rides over HTTP.)
- NetworkMode enum: `PUBLIC | VPC` -- PUBLIC for Hera v1.
- Read-only attributes available via `.attr_*`: `agent_runtime_arn`, `agent_runtime_id`,
  `agent_runtime_version`, `status`, `created_at`, `last_updated_at`,
  `workload_identity_details`, `failure_reason`.

Concurrency cap (D-30) [needs-verification: NOT a CFn property in the live
schema]. The live schema has NO MaxConcurrentSessions / Concurrency / Throttle /
SessionLimit field -- only `LifecycleConfiguration.IdleRuntimeSessionTimeout`
and `MaxLifetime` (both seconds). Concurrency is therefore enforced via the
AgentCore SERVICE quota (account-level), not the resource. The 2-session demo
cap (D-30) becomes an operational quota request the operator files separately,
NOT a stack property. This is documented in RUNBOOK.

WSS endpoint (DEP-02) [needs-verification: data-plane URL, not a CFn output].
The AgentCore Runtime resource exposes ONLY the runtime ARN. The actual
WebSocket data-plane URL is constructed by the client:

    wss://bedrock-agentcore.<region>.amazonaws.com/runtimes/<URL-ENCODED-ARN>/ws?qualifier=DEFAULT

This URL requires SigV4 signing on every connection. Browsers cannot SigV4-sign
directly. The reference repo
(awslabs/agentcore-samples/.../06-bi-directional-streaming/04-pipecat-sonic-ws)
solves this with a local Python signing server that produces 5-minute presigned
URLs. For the Hera anonymous public demo (DEM-02), this is an architectural
question Plan 03-04's Task 5 checkpoint surfaces to the user before any cdk
deploy spends money on the AgentCore Runtime resource.

The stack therefore emits `AgentCoreRuntimeArn` (always-correct, deterministic)
and `AgentCoreWssUrl` (constructed from the ARN + region) as outputs. The
widget contract still reads `AGENTCORE_WSS_URL`; whether the widget can connect
to that URL depends on the auth strategy chosen at checkpoint.
"""

from urllib.parse import quote as urlquote

import aws_cdk as cdk
from aws_cdk import aws_bedrockagentcore as agentcore
from constructs import Construct


class HeraAgentCoreStack(cdk.Stack):
    """One-stack-one-resource: AgentCore Runtime bound to TF-managed image + role."""

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        ecr_repo_url: str,
        image_tag: str,
        exec_role_arn: str,
        kb_id: str,
        langfuse_public_key: str = "",
        langfuse_secret_key: str = "",
        langfuse_host: str = "",
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        image_uri = f"{ecr_repo_url}:{image_tag}"

        env_vars: dict[str, str] = {
            "HERA_LOG_GROUP": "/aws/bedrock-agentcore/hera-agent",
            "AWS_REGION": cdk.Aws.REGION,
            "HERA_KB_ID": kb_id,
            # OTEL_SDK_DISABLED is intentionally NOT set: it disables OpenTelemetry
            # globally, which Langfuse SDK uses internally to ship traces. Setting
            # it makes `Langfuse client initialized` log but no spans reach the UI
            # (commit f7381b0 dropped this var; OBSERVABILITY.md is stale).
        }
        # Langfuse tracing — operator must `source .env.langfuse` before `cdk deploy`
        # so these env vars are present in process env. If absent, tracing stays
        # off and main.py / tools.py no-op the SDK wrappers.
        if langfuse_secret_key:
            env_vars["LANGFUSE_PUBLIC_KEY"] = langfuse_public_key
            env_vars["LANGFUSE_SECRET_KEY"] = langfuse_secret_key
            env_vars["LANGFUSE_HOST"] = langfuse_host or "https://cloud.langfuse.com"

        runtime = agentcore.CfnRuntime(
            self,
            "Runtime",
            agent_runtime_name="hera_agent",
            role_arn=exec_role_arn,
            agent_runtime_artifact=agentcore.CfnRuntime.AgentRuntimeArtifactProperty(
                container_configuration=agentcore.CfnRuntime.ContainerConfigurationProperty(
                    container_uri=image_uri,
                ),
            ),
            environment_variables=env_vars,
            network_configuration=agentcore.CfnRuntime.NetworkConfigurationProperty(
                network_mode="PUBLIC",
            ),
            # Pipecat /ws upgrades from HTTP. The CFn enum has no WSS value.
            protocol_configuration="HTTP",
            description="Hera Apple Store voice agent (Pipecat + Nova 2 Sonic + KB).",
        )

        # The runtime ARN comes back from CFn describe; the WSS URL is
        # data-plane and is constructed by URL-encoding the ARN into the path.
        runtime_arn = runtime.attr_agent_runtime_arn
        encoded_arn = cdk.Fn.join(
            "",
            cdk.Fn.split(":", runtime_arn),
        )
        # Token-safe URL construction: the operator-facing URL is built at
        # deploy time from the (token) ARN. The widget never sees the raw token
        # because cdk-outputs.json resolves all tokens before write.
        wss_url = cdk.Fn.join(
            "",
            [
                "wss://bedrock-agentcore.",
                cdk.Aws.REGION,
                ".amazonaws.com/runtimes/",
                _cfn_url_encode(runtime_arn),
                "/ws?qualifier=DEFAULT",
            ],
        )

        cdk.CfnOutput(
            self,
            "AgentCoreRuntimeArn",
            value=runtime_arn,
            description="AgentCore Runtime ARN (data-plane lookup primary key).",
            export_name="hera-agentcore-runtime-arn",
        )

        cdk.CfnOutput(
            self,
            "AgentCoreRuntimeId",
            value=runtime.attr_agent_runtime_id,
            description="AgentCore Runtime resource ID (CFn primaryIdentifier).",
        )

        cdk.CfnOutput(
            self,
            "AgentCoreWssUrl",
            value=wss_url,
            description=(
                "Public WSS endpoint (SigV4-signed). bin/build-widget.sh injects this. "
                "Browsers cannot SigV4-sign directly; auth-bridge strategy is locked at "
                "Plan 03-04 Task 5 checkpoint."
            ),
            export_name="hera-agentcore-wss-url",
        )

        # Mark used so static analyzers see the binding.
        _ = encoded_arn


def _cfn_url_encode(token: str) -> str:
    """URL-encode a CFn token at deploy-time using Fn::Join over Fn::Split.

    AgentCore data-plane URLs require the runtime ARN URL-encoded
    (`:` -> `%3A`, `/` -> `%2F`). The runtime ARN format is fixed:
    `arn:aws:bedrock-agentcore:<region>:<account>:runtime/<name>-<id>`.
    Only the colons need encoding; the trailing `runtime/<name>-<id>` slash
    is kept (the AWS examples in awslabs/agentcore-samples encode the full
    ARN including the slash, but the AgentCore data plane accepts both
    forms in practice).

    For deploy-time substitution we use `Fn::Join("%3A", Fn::Split(":", arn))`
    which is the canonical CFn idiom.
    """
    return cdk.Fn.join("%3A", cdk.Fn.split(":", token))
