---
title: "3.3 Deploy AgentCore"
date: 2025-01-01
weight: 3
---

## Goal of this section

Build a multi-arch container (linux/arm64,linux/amd64) + push it to your ECR → `cdk deploy` the AgentCore Runtime (CDK Python — D-24 hybrid IaC) → second-pass `terraform apply` to wire the `widget_presigner` Lambda to the runtime ARN → `bin/smoke-deploy.sh` end-to-end gate. After this section, the agent runs on Bedrock AgentCore Runtime in `ap-northeast-1` instead of your laptop.

## Hybrid IaC: Terraform + CDK Python (D-24)

Hera uses both IaC tools side-by-side with a clear split:

- **Terraform `~> 6.27` owns everything EXCEPT the AgentCore Runtime resource:** Knowledge Base + S3 Vectors, IAM (including the AgentCore exec role), ECR, S3 widget bucket, CloudFront distribution, CloudWatch log group, observability dashboard + alarms, and the `widget_presigner` Lambda. The AWS provider has full native support for those areas.
- **CDK Python (`infra/cdk/`) owns ONE resource — the AgentCore Runtime:** `AWS::BedrockAgentCore::Runtime`. Early 2026, the Terraform AWS provider has no native resource for AgentCore Runtime → CDK Python bridges the gap (D-24 Phase 3).
- **4-step lifecycle (D-25 amended in Plan 03-04):** TF apply → push image → cdk deploy → second-pass TF apply. The trailing step exists because the `widget_presigner` Lambda needs the Runtime ARN in an env var + IAM policy resource scope, but the Runtime is created by CDK AFTER the TF first apply — the chicken-and-egg is solved with a two-pass apply.
- **Same-artifact contract (AGT-08):** Phase 2 builds the local Dockerfile multi-arch (`linux/arm64,linux/amd64`); Phase 3 pushes the SAME image to AgentCore Runtime which is ARM64-only — no rebuild. The lockfile (`agent/uv.lock`) is reused verbatim for the production deploy.

## Step 0: AgentCore default concurrency (cap=10)

The default AgentCore quota is 10 concurrent runtimes per account. **Your workshop runs fine on the cap=10 default — do nothing here.** At workshop-session scale you will not hit the cap. Skip this step and continue to Step 1.

{{% notice info %}}
**Instructor reference (D-30 does NOT apply to learners):** the instructor's demo URL runs with D-30 concurrency cap=2 to cap cost. If you (the instructor) want to replicate that setup:

1. Open `https://console.aws.amazon.com/servicequotas/home/services/bedrock-agentcore/quotas` in `ap-northeast-1`.
2. Find "Concurrent runtime sessions" (or similar).
3. Click "Request quota increase" → enter 2 → Submit. AWS approves within 1-2 days.

![Service Quotas — request AgentCore concurrency 2 (D-30, instructor reference)](/images/3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png)

*Source: RUNBOOK.md + Phase 3 D-30 — Phase 3 Plan 03-04*
{{% /notice %}}

## Step 1: Apply Terraform (KB + IAM + ECR + widget hosting)

The Wave-1 apply creates every resource except the AgentCore Runtime. On a fresh deploy, `agentcore_runtime_arn` uses the empty-string default (placeholder ARN in the presigner IAM policy) — it is swapped at Step 3.5.

```bash
cd infra/envs/prod
terraform init
terraform plan -out plan.out
terraform apply plan.out
cd ../../..
```

*Source: RUNBOOK.md (Phase 3 Step 1) — Phase 3 Plan 03-01*

Phase 3 outputs added: `ecr_repo_url`, `agentcore_exec_role_arn`, `agentcore_log_group_arn`, `agentcore_log_group_name`, `widget_cloudfront_url`, `widget_s3_bucket_name`, `widget_cloudfront_distribution_id`. Section 3.4 uses the widget outputs to deploy the frontend.

## Step 2: Build + push the container to your ECR

`bin/push-image.sh` packages the Phase 2 buildx invocation into a single paste-block. Same Dockerfile, same image artifact — only the destination registry differs (ECR instead of the local docker daemon).

```bash
bin/push-image.sh
```

*Source: bin/push-image.sh — Phase 3 Plan 03-03*

What the script does:

- Resolves `ecr_repo_url` from `terraform output -raw ecr_repo_url`.
- Computes `git rev-parse --short HEAD` → image tag (the ECR repo is `imageTagMutability=IMMUTABLE` per Plan 03-01 — no `:latest`).
- `aws ecr get-login-password | docker login` against your ECR registry.
- Creates an idempotent buildx builder `hera-builder` if missing.
- `docker buildx build --platform linux/arm64,linux/amd64 --provenance=false --sbom=false --push -t ${ECR_URL}:${GIT_SHA} ./agent`.
- `aws ecr describe-images --image-ids imageTag=${GIT_SHA}` confirms the manifest list landed for both architectures.

Critical note: `--provenance=false` + `--sbom=false` are MANDATORY. BuildKit v0.11+ emits OCI in-toto attestation manifests by default — ECR's manifest validator REJECTS them with `UnsupportedMediaTypeException` on the trailing attestation blob unless the two flags are off.

## Step 3: cdk deploy AgentCore Runtime

```bash
# Dump terraform outputs so the CDK app can read them (TF -> CDK bridge).
cd infra/envs/prod
terraform output -json > terraform-outputs.json
cd ../../..

# Provision/replace the AgentCore Runtime resource. Captures the runtime ARN
# in dist/cdk-outputs.json under hera-agentcore.AgentCoreRuntimeArn.
cd infra/cdk
GIT_SHA=$(git rev-parse --short HEAD)
uv run cdk deploy hera-agentcore --context image_tag=${GIT_SHA} --outputs-file ../../dist/cdk-outputs.json --require-approval never
cd ../..
```

*Source: RUNBOOK.md (Phase 3 Step 3) — Phase 3 Plan 03-04*

CDK only owns one stack — `hera-agentcore` with the `AWS::BedrockAgentCore::Runtime` resource. The output `AgentCoreRuntimeArn` is written to `dist/cdk-outputs.json`. Note: concurrency cap is NOT in the CFn schema (verified via `aws cloudformation describe-type` in Plan 03-04) — the service quota is the real gate (see Step 0 above).

## Step 3.5: Second-pass terraform apply

```bash
RUNTIME_ARN=$(jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json)
cd infra/envs/prod
terraform apply -var "agentcore_runtime_arn=${RUNTIME_ARN}" -auto-approve
cd ../../..
```

*Source: RUNBOOK.md (Phase 3 Step 3.5) — Phase 3 Plan 03-04*

Chicken-and-egg: the `widget_presigner` Lambda needs the Runtime ARN in an env var + IAM policy resource scope, but the Runtime is created by CDK AFTER the TF first apply. The two-pass solution: TF first apply uses the empty-string placeholder ARN; the second-pass apply (after `cdk deploy` emits the ARN) swaps in the real ARN. The `presign_url` output also only populates after this step.

## Step 4: End-to-end smoke gate (bin/smoke-deploy.sh)

`bin/smoke-deploy.sh` re-runs all of Steps 1-4 in one paste-block + adds HTTPS + presigner + WSS smoke-probe gates. It is idempotent — safe to re-run from any failure point.

```bash
bin/smoke-deploy.sh
```

*Source: bin/smoke-deploy.sh — Phase 3 Plan 03-04*

What the script does:

1. `terraform output -json > terraform-outputs.json` (CDK reads it).
2. `cdk deploy hera-agentcore` (idempotent — a second run is a no-op when the image tag is unchanged).
3. Extracts `AgentCoreRuntimeArn` from `dist/cdk-outputs.json`.
4. Second-pass `terraform apply -var=agentcore_runtime_arn=<arn>`.
5. Reads the `presign_url` output, exports it as `PRESIGN_URL`.
6. `bin/build-widget.sh` (sed-inject + s3 sync + invalidate — covered in Section 3.4).
7. `curl -fsS https://<cloudfront-domain>/` HTTPS reachability gate (DEM-01 verify).
8. `curl -fsS ${PRESIGN_URL}` presigner gate (expects `{"url": "wss://..."}`).
9. `uv run python bin/_smoke_deploy_probe.py` — opens WSS, sends 1s of synthetic 16 kHz Int16 silence, asserts >=1 inbound binary frame within 10s.

Success ends with:

```
OK: Phase 3 smoke passed.
    Widget URL  : https://<your-distribution>.cloudfront.net
    Presign URL : https://<your-fn-url>.lambda-url.ap-northeast-1.on.aws/
    Runtime ARN : arn:aws:bedrock-agentcore:ap-northeast-1:<your-account>:runtime/...
    Image tag   : <git-sha>
```

## POST /invocations: AgentCore HTTP protocol contract (Phase 4 Plan 04-01)

```python
@app.post("/invocations")
async def invocations() -> JSONResponse:
    """AgentCore HTTP data-plane stub. Voice loop runs on /ws (D-31)."""
    return JSONResponse(
        {
            "agent": "hera-pipecat-sonic",
            "status": "running",
            "model": "amazon.nova-sonic-v1:0",
        }
    )
```

*Source: agent/hera_agent/main.py — Phase 4 Plan 04-01*

AgentCore HTTP protocol calls the container at `POST /invocations` per Bedrock convention (selected by `ProtocolConfiguration: HTTP` in the Phase 3 CDK stack). The actual voice loop runs on `/ws` (Pipecat WebSocket transport) — `/invocations` is a static-envelope stub that returns 200 to satisfy the AgentCore data-plane invocation API.

Plan 04-01 deployed Runtime version=3 status=READY referencing image `hera-agent:7e72b66`, closing Phase 3 SC#2 (data-plane invoke returns `statusCode=200`).

## Reference values (resolve from your own deploy)

- Account: `<your-account-id>` — resolve via `aws sts get-caller-identity --query Account --output text`.
- Region: `ap-northeast-1` (workshop default; you can use a different region but must re-enable Bedrock model access in that region).
- Runtime: `<your-runtime-id>` — resolve via `jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json` after `cdk deploy hera-agentcore` completes in Step 4.
- Live URL: `https://<your-distribution>.cloudfront.net/` — resolve via `terraform -chdir=infra/envs/prod output -raw widget_cloudfront_url` after Section 3.4 deploys the widget.
- Active cost: AgentCore Runtime + Sonic streaming around the D-54 ballpark of `~$2-5 USD per 2-hour session`. Exact per-service breakdown will be updated post-launch once the instructor pulls 24h Cost Explorer data from a real workshop session.

## Cleanup order

```bash
# Tear down CDK first, then Terraform.
cd infra/cdk && uv run cdk destroy hera-agentcore --force && cd ../..
cd infra/envs/prod && terraform destroy && cd ../..
```

*Source: RUNBOOK.md (Phase 3 Cleanup order) — Phase 3 Plan 03-04*

Full cleanup details (with `bin/cleanup-verify.sh` and the 24h Cost Explorer paste-line) live in Section 4. CDK first because the AgentCore Runtime holds the IAM exec role that Terraform manages — reverse order → `terraform destroy` fails because the policy is still attached and the role is still in-use.

## What's next

The AgentCore Runtime is live in `ap-northeast-1`, but there is no UI for users yet. Section 3.4 deploys the HTML/JS widget to S3+CloudFront (set up at Step 1), sed-injects `__PRESIGN_URL__`, and you open the HTTPS URL in a browser to test the voice loop end-to-end.
