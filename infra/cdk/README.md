# infra/cdk/

CDK Python project owning the Hera AgentCore Runtime resource (D-24).
Single stack: `hera-agentcore`.

## Setup

```
cd infra/cdk
uv sync
uv run cdk bootstrap aws://851725411875/ap-northeast-1   # one time per AWS account+region
```

## Deploy

```
# 1. dump terraform outputs the stack reads
cd ../envs/prod
terraform output -json > terraform-outputs.json
cd ../../cdk

# 2. deploy
uv run cdk deploy hera-agentcore \
  --context image_tag=$(cd ../.. && git rev-parse --short HEAD) \
  --outputs-file ../../dist/cdk-outputs.json \
  --require-approval never
```

## Destroy

```
uv run cdk destroy hera-agentcore --force
```

## Why CDK and not Terraform

Per `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-CONTEXT.md`
D-24, Terraform's `~> 6.27` AgentCore Runtime resource coverage is uncertain
(MEDIUM-LOW research confidence). CDK Python is the fallback for ONLY this
single resource; everything else stays Terraform.

## Live-introspected facts (resolves Plan 03-04 [needs-verification] tags)

The plan listed five contracts the executor had to resolve at apply time. All
five resolved cleanly via `aws cloudformation describe-type --type RESOURCE
--type-name AWS::BedrockAgentCore::Runtime --region ap-northeast-1` (schema
TimeCreated 2025-10-06) plus an `aws-cdk-lib==2.252.0` import probe:

| Contract | Resolution |
|----------|-----------|
| L2/L1 construct path | `aws_cdk.aws_bedrockagentcore.CfnRuntime` (typed L1 ships in 2.252.0). |
| ContainerUri property | Nested under `AgentRuntimeArtifact.ContainerConfiguration.ContainerUri`. |
| RoleArn property | Top-level `RoleArn`. |
| Protocol enum | `MCP | HTTP | A2A | AGUI`. **No `WSS` value** -- Pipecat's `/ws` upgrade rides over `HTTP`. |
| WSS endpoint output attribute | **Not a CFn output.** Constructed by client as `wss://bedrock-agentcore.<region>.amazonaws.com/runtimes/<URL-ENCODED-ARN>/ws?qualifier=DEFAULT` (SigV4-signed). |
| Concurrency cap (D-30) | **Not a CFn property.** Account-level service quota; operator files via Service Quotas console. |
