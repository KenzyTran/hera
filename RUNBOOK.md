# Hera Knowledge Base Runbook

Operational runbook for the Hera Bedrock Knowledge Base on S3 Vectors. Covers first deploy, manual catalog sync, verification, recovery from a half-failed apply, cleanup, and forward-looking next steps. English only — workshop content lives under `content/{vi,en}/`; this runbook is for operators.

## Pre-flight

Before the first deploy, the operator must have AWS CLI v2 installed and authenticated against the target account, Terraform 1.9 or newer on PATH, and `jq` available for the verify script. The default region for production is `ap-northeast-1`; the dev region is `us-east-1`. The most commonly missed step is enabling Amazon Titan Text Embeddings V2 model access in the Bedrock console for the chosen region — without that the data-source ingestion will fail with an `AccessDeniedException` from Bedrock at sync time, not at apply time (Pitfall A).

This runbook assumes you have the four blocking dependencies installed and AWS credentials configured for the target account. Run these checks before the first deploy:

```bash
# 1. AWS CLI v2 and credentials
aws --version                # expect aws-cli/2.x
aws sts get-caller-identity  # confirms credentials and prints the account ID you will deploy into

# 2. Terraform >= 1.9
terraform -version           # expect 1.9 or newer

# 3. jq (used by bin/verify-kb.sh)
jq --version                 # any 1.6+ release
```

You also need to enable Amazon Titan Text Embeddings V2 model access in the deploy region. AWS gates Bedrock models per-account-per-region; this is separate from IAM. The default deploy region is `ap-northeast-1`.

```bash
# Confirm Titan v2 is available in ap-northeast-1 (after enabling in the console)
aws bedrock list-foundation-models --region ap-northeast-1 \
  --query 'modelSummaries[?modelId==`amazon.titan-embed-text-v2:0`].modelLifecycle.status' \
  --output text
# Expect: ACTIVE
# Empty output means model access is not enabled.
```

To enable: AWS Console -> Bedrock -> Model access -> Modify -> check "Amazon Titan Text Embeddings V2" -> Save changes -> wait ~1 minute. Repeat once per region you deploy into.

If `terraform apply` succeeds but `aws bedrock-agent start-ingestion-job` fails with `AccessDeniedException` mentioning the model ARN, re-check this step. IAM may be correct but model access still gated.

## First deploy

The first deploy creates the source S3 bucket, the S3 Vectors bucket and index, the Bedrock Knowledge Base, the data source, and the KB service IAM role. Resource names are fixed (`hera-kb-prod`, `hera-kb-source-prod`, `hera-kb-vectors-prod`) — there is no random suffix, by design (D-12). This is run from `infra/envs/prod/` against the locked-in region.

Provision the Bedrock KB, source S3 bucket, S3 Vectors bucket and index, KB data source, and KB service IAM role:

```bash
cd infra/envs/prod
terraform init
terraform apply
# Review the plan (about 9 resources). Type 'yes' to apply.
cd ../../..
```

Expected outcome:
- `terraform apply` completes in ~30-60 seconds.
- Outputs: `kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`.
- The S3 source bucket and S3 Vectors bucket are now empty; you upload catalog content next.

Region override (use `us-east-1` for dev per DEP-06):

```bash
cd infra/envs/prod
terraform apply -var=region=us-east-1
```

Note: changing the region after a successful apply requires `terraform destroy` first (provider-level state is per-region). For day-to-day workshop use, stay on the default `ap-northeast-1`.

## First sync

`terraform apply` creates the KB but does NOT auto-trigger ingestion (D-05, D-07). The operator manually copies the catalog files into the source bucket and starts an ingestion job. The job typically completes in under a minute for the four-document catalog; results may take 2 to 3 additional minutes to be visible to retrieve calls due to KB propagation lag (Pitfall C).

The catalog content is uploaded to S3 manually, then a Bedrock ingestion job is triggered explicitly. There is no `null_resource` automation in Terraform - the AWS CLI is the teaching surface (D-05, D-07).

```bash
# 1. Resolve outputs from terraform state
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
SRC_BUCKET=$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)
REGION=ap-northeast-1

# 2. Upload all catalog markdown to the catalog/ prefix
aws s3 cp catalog/ "s3://${SRC_BUCKET}/catalog/" --recursive --exclude "*" --include "*.md"

# 3. Trigger the ingestion job (build-time API: aws bedrock-agent, NOT bedrock-agent-runtime - see Pitfall J below)
JOB_ID=$(aws bedrock-agent start-ingestion-job \
  --region "${REGION}" \
  --knowledge-base-id "${KB_ID}" \
  --data-source-id "${DS_ID}" \
  --description "first sync" \
  --query 'ingestionJob.ingestionJobId' \
  --output text)
echo "started ingestion job: ${JOB_ID}"

# 4. Poll until COMPLETE (or FAILED / STOPPED)
while true; do
  STATUS=$(aws bedrock-agent get-ingestion-job \
    --region "${REGION}" \
    --knowledge-base-id "${KB_ID}" \
    --data-source-id "${DS_ID}" \
    --ingestion-job-id "${JOB_ID}" \
    --query 'ingestionJob.status' \
    --output text)
  echo "status: ${STATUS}"
  case "${STATUS}" in
    COMPLETE|FAILED|STOPPED) break ;;
  esac
  sleep 5
done
```

After `STATUS=COMPLETE`, vectors are written but may take 2-3 more minutes to be queryable. This is documented AWS behavior, not a bug. Run `bin/verify-kb.sh` next - it polls for up to 5 minutes to cover this propagation lag.

**Pitfall J - two CLI surfaces:** `aws bedrock-agent` is the build-time control plane (KBs, agents, ingestion jobs). `aws bedrock-agent-runtime` is the runtime data plane (Retrieve, RetrieveAndGenerate). They are NOT interchangeable. Sync uses `bedrock-agent`; verify uses `bedrock-agent-runtime`.

## Verify

The `bin/verify-kb.sh` script issues a known-good retrieve query (`iPhone 13 Pro Max stock`) and asserts that at least one result is returned with a score above the documented threshold. It polls every 15 seconds for up to 5 minutes to absorb the post-sync propagation lag.

Confirm the KB returns the right document for the verification query:

```bash
bin/verify-kb.sh
```

Expected output (final line on success):

```
OK: 3 results returned, top score 0.78 >= threshold 0.4
```

The script polls every 15s for up to 5 minutes (covers post-sync propagation). It exits 0 on success.

If it fails with `AccessDeniedException`: model access for Titan v2 is not enabled in the deploy region. Re-read the Pre-flight section.

If it times out with `no qualifying results after 300s`: wait another 2 minutes and re-run. Occasional propagation can exceed 5 minutes for fresh KBs. If it still times out, check the ingestion job actually completed (`aws bedrock-agent list-ingestion-jobs --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" --region "${REGION}"`).

If it returns empty results despite a completed sync: confirm the `inclusion_prefixes = ["catalog/"]` setting in the data source matches where you uploaded the markdown. The `aws s3 cp` command above writes to `s3://<bucket>/catalog/`; the data source only reads under that prefix.

Override the query for ad-hoc checks:

```bash
bin/verify-kb.sh --query '{"text":"What MacBook configurations are in stock?"}'
bin/verify-kb.sh --query '{"text":"What is your return policy?"}'
```

## Re-index after editing a product file

When a stock count or price changes in any `catalog/*.md`, the operator edits the file in place, uploads it back to S3, and starts another ingestion job. Bedrock Knowledge Base detects changed objects and incrementally re-embeds only the diff (D-06) — there is no need to delete and re-upload the full catalog.

Bedrock KB ingestion is incremental. After editing a `catalog/*.md` file, re-upload and re-trigger the same ingestion job command - Bedrock processes only the documents that were added, modified, or deleted since the last sync.

```bash
# Edit the file
$EDITOR catalog/iphone-13-pro-max.md

# Re-upload (overwrites the S3 object)
SRC_BUCKET=$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)
aws s3 cp catalog/iphone-13-pro-max.md "s3://${SRC_BUCKET}/catalog/iphone-13-pro-max.md"

# Re-run the ingestion job (same command as First sync)
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
aws bedrock-agent start-ingestion-job \
  --region ap-northeast-1 \
  --knowledge-base-id "${KB_ID}" \
  --data-source-id "${DS_ID}" \
  --description "re-index after editing iphone-13-pro-max.md"

# Wait for status COMPLETE, then run verify (covers propagation)
bin/verify-kb.sh
```

The cost of a single-file re-embed at workshop scale is well under one cent.

## Recovery from a half-failed apply

Because resource names are fixed (no random suffix), a half-failed apply that leaves orphan resources cannot be recovered with `terraform apply` alone — the second apply collides with the existing names. The recovery path is `terraform destroy` (which cleans up whatever was created) followed by `terraform apply` again (D-12, Pitfall #17). The cost of a full rebuild at workshop scale is well under one cent plus a few minutes.

Resource names are fixed (per D-12 - no random suffix), so retrying after a partial failure can hit `ResourceAlreadyExistsException`. The recovery path is destroy + re-apply, not `terraform import`.

```bash
cd infra/envs/prod
terraform destroy   # type 'yes' to confirm
terraform apply
cd ../../..
```

Cost of a full rebuild at workshop scale is under one cent in S3 / S3 Vectors / Bedrock embedding charges plus a few minutes of waiting. After a successful re-apply, repeat the First sync section.

If `terraform destroy` itself fails because the source bucket has objects, that should not happen (the module sets `force_destroy = true` on both buckets). If it does, wipe the bucket manually and retry:

```bash
aws s3 rm "s3://$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)/" --recursive
cd infra/envs/prod && terraform destroy && cd ../../..
```

## Cleanup

When the workshop session is over, `terraform destroy` removes all resources created by this stack. Running `bin/verify-kb.sh --invert` afterwards confirms that the KB no longer responds to retrieve calls — this is the inverse-assertion path forward-referenced from Phase 4 (D-16).

Tear down all Phase 1 AWS resources and confirm the KB is no longer reachable:

```bash
cd infra/envs/prod
terraform destroy   # type 'yes' to confirm
cd ../../..

# Confirm the KB no longer responds to retrieve calls (Phase 4 cleanup verification, D-16).
# In invert mode, success means AccessDenied / ResourceNotFound is returned.
bin/verify-kb.sh --invert
```

Expected `--invert` final line:

```
OK (cleanup): KB no longer accessible
```

After this, no Bedrock KB, no S3 source bucket, no S3 Vectors bucket / index, and no IAM role exist for this stack. Cost Explorer should show $0 for the affected services within 24 hours. Phase 4 builds a more comprehensive cleanup-verify script that checks across all phases.

## Local agent setup (Phase 2) — uv path

The Phase 2 Pipecat voice agent runs on a developer laptop and proves the full voice loop end-to-end against the live Phase 1 KB. This section covers the **uv-native run path** (fast iteration, no Docker rebuild loop). The Docker Compose run path and the first-voice-test smoke probe are documented in subsequent sections (`First voice test`, `Cleanup local Docker resources`) added by Plan 02-02.

Pre-flight: confirm uv 0.10+ is installed, and that AWS credentials with `bedrock:InvokeModelWithBidirectionalStream` (for Nova 2 Sonic) and `bedrock:Retrieve` (for the KB) are available in your shell.

```bash
uv --version       # expect 0.10 or newer

# AWS Nova 2 Sonic model access (per-region, separate from IAM)
aws bedrock list-foundation-models --region ap-northeast-1 \
  --query 'modelSummaries[?modelId==`amazon.nova-2-sonic-v1:0`].modelLifecycle.status' \
  --output text
# Expect: ACTIVE
# Empty -> Console -> Bedrock -> Model access -> Modify -> Amazon Nova 2 Sonic -> Save changes (~1 min)
```

Set the required env vars (or copy `agent/.env.example` to `agent/.env` and fill in):

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
# AWS_SESSION_TOKEN only needed if your creds are short-lived (SSO / AssumeRole)
export HERA_KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
export AWS_REGION=ap-northeast-1     # default if unset
export HERA_KB_SCORE_THRESHOLD=0.4   # default if unset
export HERA_VOICE=matthew            # default if unset; tiffany / amy also valid
```

Run the agent natively via uv:

```bash
bin/run-agent-local.sh
# starts uvicorn on http://localhost:8080
# /ping -> {"status":"Healthy", ...}
# /ws   -> Pipecat WebSocket endpoint (browser test page connects here)
```

Stop with Ctrl-C. The agent has no persistent state — D-21 mandates in-memory only — so there is nothing to back up between runs.

Troubleshooting:

- If the agent fails to start with `KeyError: 'AWS_SECRET_ACCESS_KEY'`: the `AWSNovaSonicLLMService` requires explicit static credentials (it does NOT follow the boto3 default chain). The env vars MUST be set in the shell or `agent/.env`. See `agent/.env.example`.
- If the agent answers but says "no relevant product info": confirm the live KB is queryable with `bin/verify-kb.sh`, confirm `HERA_KB_ID` matches `terraform -chdir=infra/envs/prod output -raw kb_id`, and try a lower threshold like `HERA_KB_SCORE_THRESHOLD=0.2`.
- If long conversations (>8 minutes) cut out: Pipecat's `SessionContinuationParams` (default `transition_threshold_seconds=360`) rotates the Sonic bidi stream ~120s before the cap. The transition should be inaudible. If you observe a real audio dropout, root-cause via agent logs (look for the rotation log line); do NOT add try/except in `pipeline.py`.

For the docker-compose run path and the browser-driven voice loop, see the `First voice test` and `Cleanup local Docker resources` sections below (added by Plan 02-02).

## First voice test

Two ways to drive the voice loop end-to-end against the live KB and live Sonic:

**Path A - scripted AGT-04 latency gate (no browser):**

```bash
export HERA_KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
bin/smoke-voice.sh
```

Expected last three lines:
```
LATENCY_MS=<n>           # typically 0-2500 ms
OK: latency 1.XXX s < AGT-04 budget 3.0s
OK: AGT-04 latency gate passed
```

This script brings up the docker-compose stack, opens a WebSocket to `ws://localhost:8080/ws`, sends ~1 second of synthetic silence, and times the first inbound binary audio frame from Sonic. Exits non-zero if the measured latency is >= 3.0 seconds. Re-run any time the agent code changes - this is the AGT-04 regression check.

**Path B - browser-driven manual test (with real microphone):**

Bring up the stack:

```bash
bin/run-agent-docker.sh
# agent     -> http://localhost:8080
# frontend  -> http://localhost:8000
```

Open `http://localhost:8000/` in Chrome or Edge (Firefox has had AudioWorklet quirks in the past - Chromium-based browsers are the smoke-test default). Click "Allow" on the microphone permission prompt, click "Record", and ask:

> Do you have MacBook Pro?

Expected outcome:
- The transcript pane shows your question within ~1s.
- Sonic calls the `lookup_product` tool against the Phase 1 KB.
- A spoken Apple Store-style answer plays through your speakers, naming the in-stock MacBook Pro M4 configurations.
- The end-to-end latency from end-of-utterance to first audio chunk is under 3 seconds (AGT-04 target - the same number Path A measures programmatically).

If the agent answers but says "no relevant product info":
- Confirm the live KB is queryable: `bin/verify-kb.sh` exits 0.
- Confirm `HERA_KB_ID` matches the terraform output: `terraform -chdir=infra/envs/prod output -raw kb_id`.
- Confirm the score threshold is not too high: try `HERA_KB_SCORE_THRESHOLD=0.2`.

If the WebSocket connects but no audio plays:
- Open the browser DevTools console; confirm no AudioContext suspension errors. Click anywhere on the page first to satisfy the browser autoplay policy.
- Confirm the agent container logs show `WS client connected` and a `lookup_product` invocation.

If the agent fails to start with `KeyError: 'AWS_SECRET_ACCESS_KEY'`:
- The `AWSNovaSonicLLMService` requires explicit static credentials (it does NOT follow the boto3 default credential chain). Mounting `~/.aws` is not enough - the env vars must be set in the shell or `.env`. See `agent/.env.example`.

If long conversations (>8 minutes) cut out:
- Pipecat's `SessionContinuationParams` (default `transition_threshold_seconds=360`) rotates the Sonic bidi stream ~120s before the cap. The transition should be inaudible. If you observe a real audio dropout, root-cause via agent logs (look for the rotation log line); do NOT add try/except in `pipeline.py`.

## Cleanup local Docker resources

When the workshop session is over (and after Phase 1 cleanup is complete), tear down the local Docker containers and images. Phase 1 cleanup (`terraform destroy` from `infra/envs/prod/`) handles the AWS-side teardown including the Phase 2 IAM policy `hera-kb-retrieve-prod`; this section only handles the local Docker artifacts.

```bash
# Stop and remove the docker compose containers (keeps images)
docker compose down

# Remove the agent image (recover ~2 GB)
docker image rm hera-agent:dev 2>/dev/null || true

# Optional: prune unreferenced layers (recover more space)
docker image prune -f
```

The Pipecat agent has no persistent state - D-21 mandates in-memory only - so there is nothing to back up before teardown. The Phase 1 KB and S3 buckets are untouched by these commands.

## Phase 3: AgentCore deploy

Four explicit paste-blocks (D-25 amended in Plan 03-04 Task 5b: the Rule-4
widget_presigner Lambda needs the AgentCore Runtime ARN, so the original
3-step lifecycle gains a second-pass Terraform apply between cdk deploy and
build-widget). Each step has one job, surfaces its own exit code, and is
idempotent enough to re-run safely.

Sequence:

1. `terraform apply` (KB + IAM + ECR + widget hosting + log group; Wave 1)
2. `bin/push-image.sh` (multi-arch buildx push to ECR)
3. `cdk deploy hera-agentcore` (creates the AgentCore Runtime; emits ARN)
4. `terraform apply -var=agentcore_runtime_arn=<arn>` (wires the
   widget_presigner Lambda to the now-existing runtime)
5. `bin/build-widget.sh` (sed-inject __PRESIGN_URL__ + s3 sync + invalidate)
6. `bin/smoke-deploy.sh` (end-to-end smoke; or run individual steps)

### Prerequisites

- AWS credentials for account 851725411875 in shell, with IAM/ECR/S3/CloudFront/CloudWatch write rights and `bedrock-agentcore:*` permissions for `cdk deploy`.
- Region: `ap-northeast-1` (set `export AWS_REGION=ap-northeast-1` before any step).
- Local tools: `terraform >= 1.9`, `docker` with `buildx`, `aws` CLI v2, `node` >= 18 + `python3` >= 3.11 (for AWS CDK Python), `jq`.
- Plan 03-01 has been applied (`terraform apply` in `infra/envs/prod/`); `terraform output -raw ecr_repo_url` returns the ECR URI.
- Phase 2 image (`hera-agent:dev-multiarch`) has built locally at least once on this machine so buildx caches are warm.

### Step 1: Apply Terraform (KB + IAM + ECR + widget hosting + log group)

Already covered in earlier RUNBOOK section "Phase 1 / Phase 2 deploy". The Phase 3 modules (`agentcore_iam`, `widget_hosting`, `ecr`) are wired into the same prod root. Re-run terraform when those modules change:

```bash
cd infra/envs/prod
terraform plan -out plan.out
terraform apply plan.out
```

Outputs Phase 3 added: `ecr_repo_url`, `agentcore_exec_role_arn`, `agentcore_log_group_arn`, `agentcore_log_group_name`, `widget_cloudfront_url`, `widget_s3_bucket_name`, `widget_cloudfront_distribution_id`.

### Step 2: Build + push the agent image to ECR

```bash
bin/push-image.sh
```

What this does (Plan 03-03):
1. Resolves `ecr_repo_url` from terraform outputs.
2. Computes the short git SHA - that is the only image tag (ECR repo is IMMUTABLE per Plan 03-01).
3. `aws ecr get-login-password | docker login` against the ECR registry.
4. Ensures a `hera-builder` buildx builder exists (idempotent).
5. `docker buildx build --platform linux/arm64,linux/amd64 --provenance=false --sbom=false --push -t ${ECR_URL}:${GIT_SHA} ./agent`.
6. `aws ecr describe-images --image-ids imageTag=${GIT_SHA}` confirms the manifest landed.

Output ends with the `cdk deploy` line you paste into Step 3. Re-run is safe: pushing the same SHA tag twice no-ops at ECR (manifest digest already present); pushing a new SHA tag adds a new image manifest. To deploy a new image, commit your changes locally first so the SHA differs.

### Step 3: Deploy AgentCore (CDK)

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

Plan 03-04 owns the `infra/cdk/` stack and the `dist/cdk-outputs.json` shape.

### Step 3.5: Wire widget_presigner to the live AgentCore Runtime ARN

```bash
# Read the runtime ARN that cdk deploy just emitted, then second-pass
# terraform apply to update the widget_presigner Lambda env vars + IAM
# policy to point at the real runtime ARN.
RUNTIME_ARN=$(jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json)
cd infra/envs/prod
terraform apply -var "agentcore_runtime_arn=${RUNTIME_ARN}" -auto-approve
cd ../../..
```

This is the Plan 03-04 Rule-4 deviation: the browser cannot SigV4-sign a
WebSocket upgrade directly, so a small Lambda Function URL mints
short-lived (TTL 300s) presigned WSS URLs the widget fetches before
opening the connection. The Lambda needs the runtime ARN, but the runtime
is created by CDK, so this is a second-pass terraform apply. On a fresh
deploy the Wave-1 apply uses the empty-string default for
`agentcore_runtime_arn` (placeholder ARN in the IAM policy); this step
swaps it for the real ARN.

### Step 4: Deploy the widget (S3+CloudFront)

```bash
# Inject __PRESIGN_URL__ into the widget and ship to CloudFront. Reads
# presign_url from terraform outputs (set in Step 3.5).
bin/build-widget.sh
```

The widget loads `index.html` -> reads the injected `PRESIGN_URL` constant
in `app.js` -> on click-record, fetches `${PRESIGN_URL}` -> server returns
`{"url": "wss://..."}` -> browser opens the WSS URL. The Function URL has
CORS allow-origin restricted to the CloudFront domain.

### Step 5: End-to-end smoke

All steps above can be run in one paste-block:

```
bin/smoke-deploy.sh
```

What it does:
1. `terraform output -json > infra/envs/prod/terraform-outputs.json` (CDK reads this).
2. `cdk deploy hera-agentcore --context image_tag=$(git rev-parse --short HEAD) --outputs-file dist/cdk-outputs.json`.
3. Extracts `AgentCoreRuntimeArn` from `dist/cdk-outputs.json`.
4. `terraform apply -var=agentcore_runtime_arn=<arn>` -- second-pass apply
   updates the widget_presigner Lambda to point at the real runtime ARN.
5. Reads `presign_url` from `terraform output`; exports as `PRESIGN_URL`.
6. `bin/build-widget.sh` (sed-injects `__PRESIGN_URL__`, s3 syncs, invalidates CloudFront).
7. `curl -fsS https://<cloudfront-domain>/` -- HTTPS reachability gate (DEM-01 verify).
8. `curl -fsS ${PRESIGN_URL}` -- presigner reachability gate; expects `{"url": "wss://..."}`.
9. `uv run python bin/_smoke_deploy_probe.py` -- fetches the presigned URL, opens WSS, streams 1s of synthetic 16 kHz Int16 silence, asserts >=1 inbound binary frame within 10s.

On success the operator sees:
```
OK: Phase 3 smoke passed.
    Widget URL  : https://d111111abcdef.cloudfront.net
    Presign URL : https://....lambda-url.ap-northeast-1.on.aws/
    Runtime ARN : arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/...
    Image tag   : <git-sha>
```

If any step fails, fix at that layer and re-run -- `bin/smoke-deploy.sh` is idempotent.

### Cleanup order

```bash
# Tear down CDK first (so the AgentCore Runtime resource releases its grip on
# the IAM role + log group + image), then Terraform.
cd infra/cdk && uv run cdk destroy hera-agentcore --force && cd ../..
cd infra/envs/prod && terraform destroy && cd ../..
```

Cleanup verification script (`cleanup-verify.sh`) is Phase 4 work.

## Phase 4: Protocol-bridge deploy

Closes Phase 3 SC#2 by exposing `POST /invocations` on the live container per the
AgentCore HTTP protocol contract. The voice loop continues on `/ws` unchanged;
`/invocations` is a static-envelope stub (D-31, RESEARCH section A — canonical
awslabs Pipecat-on-AgentCore sample shape).

### Step 1: Local rebuild + curl verify gate (D-32 — run BEFORE pushing image)

```bash
cd agent && docker build -t hera-agent:local-test . && cd ..
docker run --rm -d --name hera-test -p 8080:8080 hera-agent:local-test
curl -fsS -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" -d '{"prompt":"healthcheck"}'
# Expect: HTTP 200 + {"agent":"hera-pipecat-sonic","status":"running","model":"amazon.nova-sonic-v1:0"}
curl -fsS http://localhost:8080/ping  # /ping unchanged: {"status":"Healthy",...}
docker stop hera-test
```

### Step 2: Multi-arch ECR push (reuses bin/push-image.sh)

```bash
NEW_TAG=$(git rev-parse --short HEAD)
bash bin/push-image.sh
aws ecr describe-images --repository-name hera-agent \
  --image-ids imageTag=$NEW_TAG --region ap-northeast-1 \
  --query 'imageDetails[0].imageManifest' --output text | head -20
```

### Step 3: cdk deploy in-place (version=2 -> version=3)

```bash
(cd infra/envs/prod && terraform output -json > terraform-outputs.json)
mkdir -p dist
(cd infra/cdk && uv run cdk deploy hera-agentcore \
  --context "image_tag=$NEW_TAG" \
  --outputs-file dist/cdk-outputs.json \
  --require-approval never)
```

CFn does an UPDATE_IN_PROGRESS -> UPDATE_COMPLETE; AgentCore Runtime
`hera_agent-GIsf2P4ImD` ContainerUri swaps to the new tag; version increments
from 2 to 3.

### Step 4: SC#2 closure smoke probe (D-34)

```bash
RUNTIME_ARN=$(jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json)
aws bedrock-agentcore invoke-agent-runtime \
  --region ap-northeast-1 \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --payload '{"prompt":"healthcheck"}' \
  --content-type application/json \
  --accept application/json \
  /tmp/agentcore-response.json
jq '.' /tmp/agentcore-response.json
# Expect {"agent":"hera-pipecat-sonic","status":"running","model":"amazon.nova-sonic-v1:0"}
```

[needs-verification A2]: if running under a non-root operator profile, ensure
the IAM identity has `bedrock-agentcore:InvokeAgentRuntime` on the runtime ARN.

### Optional: browser smoke (NOT a gate per D-34)

Open https://dg0w939ktclw6.cloudfront.net/ in a desktop browser. Click record,
grant mic permission, ask "Do you have MacBook Pro?". Hear a KB-backed Apple
Store answer. Closes SC#2 visibly to the instructor in addition to the
data-plane smoke above.

### Rollback

The previous image tag `5f21e36` (Plan 03-05) stays in ECR (`imageTagMutability=IMMUTABLE`).
To roll back the AgentCore Runtime to version=2:

```bash
(cd infra/cdk && uv run cdk deploy hera-agentcore \
  --context "image_tag=5f21e36" --require-approval never)
```

## Resolved deferrals

The following items were tracked as Phase-N deferrals during earlier milestones and have since been delivered:

- Consumer `bedrock:Retrieve` policy for Pipecat (Phase 1 D-10 -> Phase 2 D-22). Delivered in Plan 02-03 as the managed policy `hera-kb-retrieve-prod` (output `kb_retrieve_policy_arn`). NOT attached to any role in Phase 2 — Phase 3 attaches to the AgentCore execution role with `aws_iam_role_policy_attachment`.

## Next steps (deferred)

- Remote Terraform backend (S3 versioned + DynamoDB lock) — out of v1 scope per D-11. For v1 the workshop default is local state. When the project grows past one operator, bootstrap a separate state-backend stack first, then migrate this stack with `terraform init -migrate-state`.
- Bedrock Guardrails (PII redaction) — out of v1 per PROJECT.md.
