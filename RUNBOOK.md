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

## Phase 4: Observability dashboard walkthrough

CloudWatch dashboard + 3 alarms ship via `infra/modules/observability/`. Zero
Bedrock spend; zero new IAM (D-13). Pre-flight: tick "Receive CloudWatch
Billing Alerts" in account Billing Preferences ONCE before apply (RESEARCH
A1). Without the toggle, the billing alarm sits INSUFFICIENT_DATA forever
even though the resource is deployed.

### Pre-flight (one-time, per AWS account)

1. Open https://console.aws.amazon.com/billing/home#/preferences
2. Edit Alert preferences -> tick "Receive CloudWatch Billing Alerts" -> Save.
3. Wait ~15 minutes for billing data to start flowing.

This is informational only — terraform apply succeeds without it; the alarm
sits INSUFFICIENT_DATA until the toggle flips. It is not a gate on apply.

### Apply

The observability module references `var.agentcore_runtime_arn`, so apply must
pass the live runtime ARN to keep the presigner Lambda wired correctly:

```bash
RUNTIME_ARN=$(jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json)
(cd infra/envs/prod && terraform init -upgrade)
(cd infra/envs/prod && terraform apply -var="agentcore_runtime_arn=$RUNTIME_ARN")
```

If `dist/cdk-outputs.json` is missing or stale, fall back to:

```bash
RUNTIME_ARN="arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD"
```

Expected plan: 4 to add (1 dashboard + 3 alarms). Any in-place changes
unrelated to the observability module are benign drift (CloudFront TLS
auto-bump, S3 policy provider re-encoding) — accept and continue.

### Dashboard walkthrough

Open the dashboard URL:

```bash
(cd infra/envs/prod && terraform output -raw observability_dashboard_url)
```

Five panels (left-to-right, top-to-bottom):
1. **Active sessions (singleValue):** AgentCore `ActiveStreamingConnections` 1-min sum. Updates live during a voice session.
2. **Latency p50 / p95 (timeSeries):** AgentCore `Latency` end-to-end-request milliseconds.
3. **Error rate (timeSeries):** computed as `100 * TotalErrors / Invocations`. Returns 0 when no invocations in the window.
4. **Bedrock invocations + tokens (timeSeries):** `AWS/Bedrock` `Invocations` + `InputTokenCount` + `OutputTokenCount` for `amazon.nova-sonic-v1:0`. Proxy for cost.
5. **Estimated charges (us-east-1 cross-region):** `AWS/Billing` `EstimatedCharges` `Currency=USD`. Updated every 6 hours.

A widget panel showing "No data available" is expected on a freshly-deployed
dashboard — fire some traffic via https://dg0w939ktclw6.cloudfront.net/ and
revisit. Bedrock cost panel takes up to 24h to start populating.

### OBS-05 trade-off — billing-alarm manual-stop fallback (D-35)

The billing alarm has `alarm_actions = []` per D-35 — no SNS topic, no email
subscription, no Lambda auto-stop hook. When the alarm transitions to ALARM
state (visible on the dashboard's billing panel + via `aws cloudwatch
describe-alarms`), respond manually:

```bash
# Stop the AgentCore Runtime to halt new invocations:
aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id hera_agent-GIsf2P4ImD \
  --region ap-northeast-1 \
  --status STOPPED
# (verify the exact verb name; if not supported, scale concurrency to 0
#  via service-quota or destroy the runtime via cdk destroy.)

# Or via CDK destroy (full teardown of just AgentCore):
(cd infra/cdk && uv run cdk destroy hera-agentcore --force)
```

Trade-off accepted: instructor must monitor dashboard. No out-of-band
notification. For a future v2 with real public traffic, add an SNS topic
+ email subscription + (optional) Lambda hook to automate this — explicitly
out of scope per D-35.

### OBS-04 trade-off — no per-IP rate limit on presigner (D-36)

The presigner Lambda Function URL is open (no per-IP rate limit). Effective
rate-limit lives downstream at the AgentCore Runtime concurrency cap=2 (D-30
operational service quota). Abuse via cached URL replay returns 503 from the
runtime once cap is hit.

What we did NOT add:
- AWS WAF rate-based rule on CloudFront — out of demo budget (~$5/month base).
- DynamoDB token-bucket Lambda — added complexity for marginal benefit given
  the 2-session cap.

Trade-off accepted: presigner is open; AgentCore concurrency is the gate.
For a v2 with real public traffic, add WAF or token-bucket — explicitly out
of scope per D-36.

## Phase 4: Cleanup quy trinh

Operator destroys; the script verifies (D-37, D-39). Three-step paste-style
matches D-24 cleanup-contract: CDK first, Terraform second, verify third.

### Step 1: cdk destroy hera-agentcore

```bash
(cd infra/cdk && uv run cdk destroy hera-agentcore --force)
```

CDK owns the AgentCore Runtime which holds the IAM exec role Terraform
manages. If you reverse the order, terraform destroy fails on the role
because policies are still attached and the role is still in use.

### Step 2: terraform destroy

```bash
(cd infra/envs/prod && terraform destroy -auto-approve)
```

WARNING: This step takes 15-30 minutes on the CloudFront line (disable-then-
delete cycle). DO NOT interrupt. If you hit Ctrl+C, the distribution stays
in Enabled=false, Deployed=true and you must re-run terraform destroy.

If `terraform destroy` fails on the ECR repo (`RepositoryNotEmptyException`):
the repo is `imageTagMutability=IMMUTABLE` and `force_delete=false`. Either:
- delete remaining image tags first:

  ```bash
  aws ecr batch-delete-image --repository-name hera-agent \
    --image-ids imageTag=<tag1> imageTag=<tag2> \
    --region ap-northeast-1
  ```

- or set `var.force_delete = true` in `infra/envs/prod` and re-run.

### Step 3: bin/cleanup-verify.sh

```bash
bash bin/cleanup-verify.sh
```

Runs 19 read-only AWS API calls; prints OK / FAIL per resource; exits 0
when all are gone. The script is verify-only; never destroys anything (D-39).

If any FAIL, follow the hints printed by the script. Common causes:
- step 1 / step 2 reversed (D-24)
- terraform destroy interrupted during CloudFront line (15-30 min cycle)
- ECR repo still has images (force_delete=false default)

### Verify $0 ongoing cost (24h after destroy)

Cost Explorer has up to 24h ingestion lag. Run the paste-line tomorrow
morning, NOT now (D-38). Each Cost Explorer API call is $0.01 — running
this once is fine; running it 90 times across a learner cohort costs $0.90.

```bash
# Replace YYYY-MM-DD with the actual destroy date.
DESTROY_DATE=YYYY-MM-DD
NEXT_DAY=$(date -d "${DESTROY_DATE} +1 day" +%Y-%m-%d 2>/dev/null || \
           date -j -v+1d -f "%Y-%m-%d" "${DESTROY_DATE}" +"%Y-%m-%d")

cat > /tmp/no-tax-credits.json <<'JSON'
{
  "Not": {
    "Dimensions": {
      "Key": "RECORD_TYPE",
      "Values": ["Tax", "Credit", "Refund"]
    }
  }
}
JSON

aws ce get-cost-and-usage \
  --time-period "Start=${DESTROY_DATE},End=${NEXT_DAY}" \
  --granularity DAILY \
  --metrics BlendedCost \
  --filter file:///tmp/no-tax-credits.json \
  --region us-east-1 \
  | jq '.ResultsByTime[].Total.BlendedCost.Amount'
```

Expected output: `"0"` or `"0.0000000000"` (string). Anything non-zero
indicates a leftover billable resource — re-run `bin/cleanup-verify.sh`
and inspect.

NOTE: Cost Explorer is region-pinned to us-east-1 regardless of where
your resources lived; the `--region us-east-1` flag is for clarity.

## Resolved deferrals

The following items were tracked as Phase-N deferrals during earlier milestones and have since been delivered:

- Consumer `bedrock:Retrieve` policy for Pipecat (Phase 1 D-10 -> Phase 2 D-22). Delivered in Plan 02-03 as the managed policy `hera-kb-retrieve-prod` (output `kb_retrieve_policy_arn`). NOT attached to any role in Phase 2 — Phase 3 attaches to the AgentCore execution role with `aws_iam_role_policy_attachment`.

## Next steps (deferred)

- Remote Terraform backend (S3 versioned + DynamoDB lock) — out of v1 scope per D-11. For v1 the workshop default is local state. When the project grows past one operator, bootstrap a separate state-backend stack first, then migrate this stack with `terraform init -migrate-state`.
- Bedrock Guardrails (PII redaction) — out of v1 per PROJECT.md.

## Phase 6 — Twilio Voice Channel Setup (operator paste-style)

Phase 6 ADDS phone-channel ingress to the existing v1 system. v1 web widget at https://dg0w939ktclw6.cloudfront.net + AgentCore Runtime hera_agent-GIsf2P4ImD + KB BKXE19AH89 + Phase 4 dashboard / alarms are NOT modified — phone calls and browser sessions share the AgentCore concurrency cap=2 (D-30).

### Pre-flight

- AWS CLI v2 + Terraform >=1.9 + jq + curl + uv + Docker Desktop with buildx (per Phase 1-5 RUNBOOK pre-flight; nothing new).
- A Twilio account (sign up free at https://www.twilio.com/try-twilio).
- A funded Twilio balance (~$5 covers the workshop demo + 30min testing). US local number hold ~$1.15/mo + ~$0.0085/min inbound (current 2026 Twilio US pricing per RESEARCH.md Q7).
- A stopwatch (phone built-in clock app is fine) for the dial-in latency measurement in Step 8.

### Step 1: Create Twilio account + capture credentials

1. Sign up, verify email + phone, complete onboarding.
2. Twilio Console -> Account -> API keys & tokens. Copy:
   - Account SID (starts `AC...`)
   - Auth Token (click "Show")
3. Set env vars locally (NEVER commit):
   ```bash
   export TWILIO_ACCOUNT_SID=<paste account sid>
   export TWILIO_AUTH_TOKEN=<paste auth token>
   ```

### Step 1.5: Create Secrets Manager secret for the Auth Token (D-67)

The bridge container reads the Twilio Auth Token from Secrets Manager via App Runner runtime_environment_secrets — no token in plaintext IaC.

```bash
aws secretsmanager create-secret \
  --name hera/twilio/auth-token \
  --secret-string "$TWILIO_AUTH_TOKEN" \
  --region ap-northeast-1
# Capture the ARN:
export TF_VAR_twilio_auth_token_secret_arn="$(aws secretsmanager describe-secret \
  --secret-id hera/twilio/auth-token \
  --region ap-northeast-1 \
  --query ARN --output text)"
echo "$TF_VAR_twilio_auth_token_secret_arn"
```

### Step 2: Buy a phone number

1. Twilio Console -> Phone Numbers -> Manage -> Buy a number.
2. Filter by capabilities: Voice. Country: US (cheapest at $1.15/mo local).
3. Buy. Note the number (e.g., +18005551234).

### Step 3: First-pass terraform apply (placeholder image)

The App Runner service uses a public placeholder image on the FIRST apply (chicken-and-egg per Pattern S10). The bridge image lands in ECR in Step 4.

```bash
cd infra/envs/prod
terraform apply \
  -var=agentcore_runtime_arn=arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD
```

Expected: 9 resources added (App Runner service + ASC + ECR repo + lifecycle policy + 2 IAM roles + 2 IAM role policies + log group). App Runner takes ~2-4 min to reach `RUNNING` status with the placeholder image.

Capture the ECR URL for the next step:
```bash
cd infra/envs/prod
terraform output -raw twilio_bridge_ecr_repository_url
```

### Step 4: Build + push the real bridge image

```bash
# Working tree must be clean before pinning the SHA (WARNING-5 fix —
# avoids tag/SHA desync if you have uncommitted changes).
git diff --quiet && git diff --cached --quiet \
  || { echo "ERROR: working tree dirty; commit or stash before pushing"; exit 1; }
# Pin BRIDGE_SHA AT THE START of the push so a later commit cannot desync the tag.
export BRIDGE_SHA="$(git rev-parse --short HEAD)"
bash bin/push-bridge-image.sh
echo "$BRIDGE_SHA"
```

### Step 5: Second-pass terraform apply (pin the real image SHA)

```bash
cd infra/envs/prod
terraform apply \
  -var=agentcore_runtime_arn=arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD \
  -var=twilio_bridge_image_tag="$BRIDGE_SHA"
```

Expected: 1 in-place change (App Runner service `image_identifier` updates from placeholder to `851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-twilio-bridge:$BRIDGE_SHA`). App Runner deploys the new image in 2-3 min.

Capture the WSS URL for Twilio:
```bash
cd infra/envs/prod
export TWILIO_BRIDGE_WSS_URL="$(terraform output -raw twilio_bridge_wss_url)"
echo "$TWILIO_BRIDGE_WSS_URL"
# Example: wss://abc123.ap-northeast-1.awsapprunner.com/twilio
```

### Step 6: Create TwiML Bin

1. Twilio Console -> Develop -> TwiML Bins -> Create new TwiML Bin.
2. Friendly name: `hera-bridge-prod`.
3. Paste content (REPLACE `<APP-RUNNER-WSS-URL>` with `$TWILIO_BRIDGE_WSS_URL` from Step 5):

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <Response>
     <Connect>
       <Stream url="<APP-RUNNER-WSS-URL>" />
     </Connect>
   </Response>
   ```

   DO NOT change `<Connect>` to `<Start>` — `<Start><Stream>` is unidirectional (capture-only) and outbound audio from the bridge is silently dropped (RESEARCH.md Pitfall 1).

4. Save. Copy the TwiML Bin SID (starts `EH...`).

### Step 7: Wire the number's voice webhook to the TwiML Bin

1. Twilio Console -> Phone Numbers -> Manage -> Active numbers -> click your number.
2. Voice & Fax -> "A call comes in" -> set to TwiML Bin -> pick `hera-bridge-prod`.
3. Save.

### Step 8: Smoke test (with stopwatch latency protocol — Phase 6 SC#1)

Phase 6 SC#1 mandates the response is audible within 3 seconds of first sentence. The measurement protocol below makes the gate non-subjective (WARNING-2 fix).

1. Make sure no browser session is active on the v1 widget (AgentCore concurrency cap=2 — phone competes with browser; RESEARCH.md Pitfall 7).
2. Have a stopwatch ready (phone Clock app on the dialing phone, or laptop).
3. Dial the Twilio number from your phone.
4. After TwiML connects, speak: "Do you have iPhone 13 Pro Max in stock?" — START the stopwatch the instant your last syllable finishes (end-of-utterance).
5. STOP the stopwatch the instant you hear the FIRST audible word from Hera (first response audio frame).
6. Record the elapsed time and apply the gate:
   - **<= 3.0 s**  -> **PASS** (record exact value in 06-04-SUMMARY.md as p50 latency).
   - **> 3.0 s and <= 5.0 s** -> **WARN** (record value + note "above SC#1 budget but within usable demo range"; check CloudWatch logs for cold-start indicator: first-call after scale-from-zero typically ~1.5 s slower than warmed steady-state).
   - **> 5.0 s** -> **FAIL** (do NOT proceed to REQ flips; root-cause via CloudWatch logs + retry).

7. Fallback measurement (if your phone has a call-recording app): record the call, open the WAV in Audacity, count samples between end-of-utterance waveform-trough and the first response audio frame onset. At 8 kHz sampling, 24,000 samples = 3 s. Visible by waveform inspection; no math required beyond sample-count divided by 8000.

8. End the call.

9. Tail logs:
   ```bash
   aws logs tail /aws/apprunner/hera-twilio-bridge-prod --since 5m --region ap-northeast-1
   ```
   Expected events: `Twilio WS accepted`, `Twilio start: callSid=...`, `AgentCore upstream WSS open for callSid=...`, several `audioop.ratecv` traces (none should ERROR), `Twilio stop received; closing pumps`, `AgentCore upstream closed for callSid=...`.

10. Audio quality check (Phase 6 SC#2 — no chipmunk effect): if Sonic's voice sounds high-pitched / fast, the upstream output sample rate is 24 kHz and the bridge's `SONIC_OUTPUT_RATE_HZ = 16000` constant in `infra/modules/twilio_bridge/src/bridge.py` needs updating to 24000 (D-59 open caveat from CONTEXT.md). Update + push a new image (Step 4) + second-pass apply (Step 5).

11. v1 unchanged check (D-64): open https://dg0w939ktclw6.cloudfront.net in a fresh browser tab; click "record"; speak. The widget should still hold a voice loop. (If the AgentCore concurrency cap=2 is consumed by the phone call, the widget shows "agent timeout" — end the phone call first, then retry.)

### Step 9: Cost watch

- Twilio Console -> Usage -> Voice -> confirm <$0.10 spent for the test call (US local: $0.0085/min × 5 min = $0.0425).
- AWS Billing alarm at $5/day (Phase 4 hera-billing-prod) covers Bedrock + App Runner combined.
- App Runner with `min-instances=0` returns to scale-to-zero after ~5 min idle = $0/mo idle.

### Phase 6 Cleanup quy trinh (release in this exact order!)

Operator destroys before running cleanup-verify-twilio.sh per D-39 carry-forward (script is verify-only).

1. **Release the Twilio number FIRST.** Twilio Console -> Phone Numbers -> Manage -> Active numbers -> click number -> Release this number -> confirm. (Stops the $1.15/mo hold.)
2. **Delete the TwiML Bin.** Twilio Console -> Develop -> TwiML Bins -> click `hera-bridge-prod` -> Delete.
3. **Terraform destroy** (drops App Runner service + ASC + ECR repo + 2 IAM roles + log group):
   ```bash
   cd infra/envs/prod
   terraform destroy \
     -var=agentcore_runtime_arn=arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD \
     -var=twilio_bridge_image_tag="$BRIDGE_SHA"
   ```
   Note: `terraform destroy` here drops only the Phase 6 module's resources because var.agentcore_runtime_arn keeps v1 widget_presigner state pinned. App Runner deletion takes ~60-90s. ECR `force_delete=true` (D-63) drops the repo even with images present.
4. **Delete the Auth Token secret** (operator-owned, not Terraform-managed):
   ```bash
   aws secretsmanager delete-secret \
     --secret-id hera/twilio/auth-token \
     --region ap-northeast-1 \
     --force-delete-without-recovery
   ```
5. **Verify zero leftovers** (read-only; no destroy):
   ```bash
   export TWILIO_ACCOUNT_SID=<paste account sid again>
   export TWILIO_AUTH_TOKEN=<paste auth token again>
   bash bin/cleanup-verify-twilio.sh
   # Expect: cleanup-verify-twilio: 9/9 resources verified clean -> exit 0
   ```

If verify-twilio reports FAIL, see the script's hint block — most common cause is the App Runner deletion still mid-flight (retry after 2 min) or forgetting to release the Twilio number BEFORE terraform destroy.

## Phase 6.1: Native AWS Voice Channel — Amazon Connect

Phase 6.1 ships an AWS-native PSTN voice channel (supersedes the defunct Phase 6 Twilio bridge per D-56). A caller dials a US phone number, Amazon Connect routes to a Lex V2 bot, the bot invokes a Lookup Lambda that calls the Phase-1 Bedrock KB cross-region (us-east-1 -> ap-northeast-1), and Polly Neural Joanna speaks the answer.

**Live resources** (us-east-1 — Connect free tier region):

- Connect instance: `hera-voice-prod` (id `2f9fbb50-4526-423a-8180-b9ec2cff6d96`)
- Phone number (US Toll-free): **DEFERRED — see "Phone number blocker" section**
- Lex bot: `hera-product-lookup-prod` (id `EP8MNSCULA`) alias `prod` (id `Y6L5UXBXFQ`)
- Lookup Lambda: `hera-voice-lookup-prod` (Python 3.13; calls KB `BKXE19AH89` in ap-northeast-1)
- Contact Flow: `hera-voice-flow-prod` (id `bcc2bf50-55f5-4329-8f3f-573844c7aa11`)
- CloudWatch log group: `/aws/lambda/hera-voice-lookup-prod`

### Pre-deploy paste-flow (one-time setup)

> **Shell note (W-7):** All commands below MUST be run in Git Bash (Windows) or bash (macOS/Linux). PowerShell users: open Git Bash via "Git Bash Here" in the project folder.

1. **Confirm AWS credentials reach account 851725411875** (AWS-NAT-01 acceptance preflight)

   ```
   aws sts get-caller-identity --query 'Account' --output text
   # Expect: 851725411875
   ```

2. **Confirm Connect service-linked role state** (Pitfall 4 — both states are OK)

   ```
   aws iam get-role --role-name AWSServiceRoleForAmazonConnect --query 'Role.Arn' --output text 2>&1 | head -1
   ```

3. **Confirm Polly Neural Joanna is GA in us-east-1**

   ```
   aws polly describe-voices --region us-east-1 --engine neural --query "Voices[?Id=='Joanna'].Id" --output text
   # Expect: Joanna
   ```

4. **Confirm `hera-billing-prod` alarm is OK (cost preflight)**

   ```
   aws cloudwatch describe-alarms --alarm-names hera-billing-prod --region us-east-1 --query 'MetricAlarms[0].StateValue' --output text
   # Expect: OK or INSUFFICIENT_DATA. If ALARM, STOP and triage.
   ```

### Phone number blocker (KNOWN ISSUE — operator action required)

Plan 06.1-03 live deploy on 2026-05-16 hit an AWS-side new-account eligibility blocker for Toll-free + DID claims. Both API and Console return: `Status: FAILED, Message: "The allowed limit for claimed phone numbers has been exceeded for your instance"` despite 0 phones actually claimed account-wide. AWS-side false positive caused by new Connect tenant eligibility gate.

**Unblock procedure:**

1. Submit AWS Support ticket -> Service: Amazon Connect -> Category: "Phone number management" -> request: enable phone number claim for instance `hera-voice-prod` (id `2f9fbb50-4526-423a-8180-b9ec2cff6d96`) in us-east-1; account 851725411875. AWS Support typically responds within 1-2 business days.
2. Once unblocked: uncomment `resource "aws_connect_phone_number" "us_did"` in `infra/modules/aws_voice_channel/main.tf`; revert output `connect_phone_number` to `aws_connect_phone_number.us_did.phone_number`; run `terraform apply`.
3. On Pitfall 5 retry race, use Console claim + `terraform import module.aws_voice_channel.aws_connect_phone_number.us_did <phone-arn>`.

### Deploy paste-flow

```
cd infra/envs/prod
terraform init -upgrade
terraform plan -var=agentcore_runtime_arn=<live-agentcore-runtime-arn>
# Expect: ~16 to add (15 if phone deferred), 2 to change (pre-existing CloudFront drift per D-26), 0 destroy
terraform apply -auto-approve -var=agentcore_runtime_arn=<live-agentcore-runtime-arn>
```

**Surprises to expect (and how to recover):**

- **FallbackIntent already exists race (Pitfall 1 variant):** error mentions "Intent with name FallbackIntent already exists." Cause: Lex V2 auto-creates FallbackIntent on locale create. Fix: `terraform import 'module.aws_voice_channel.aws_lexv2models_intent.fallback' 'FALLBCKINT:<BOT_ID>:DRAFT:en_US'` (intent ID literal `FALLBCKINT` for built-in), then re-run apply.

- **Alias-needs-Lambda race (Pitfall 2):** error "Lambda function not found". Fix: re-run `terraform apply`.

- **Phone claim async + ghost phone (Pitfall 5):** see "Phone number blocker" section above.

- **Contact Flow `InvalidContactFlowException` with no message body:** AWS Connect API returns empty error body. Workaround: capture exact error via `aws --cli-error-format json connect create-contact-flow ...`. Known fix: `ConnectParticipantWithLexBot` block requires THREE error transitions — `InputTimeLimitExceeded` + `NoMatchingCondition` + `NoMatchingError`. Missing any -> `Action is missing required error. Error: <name>, Path: Actions[N]`.

### Synthetic Lambda smoke (AWS-NAT-03)

Verifies the KB cross-region path BEFORE dialing the phone number.

```
aws lambda invoke --function-name hera-voice-lookup-prod --region us-east-1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"messageVersion":"1.0","invocationSource":"FulfillmentCodeHook","inputMode":"Speech","responseContentType":"audio/mpeg","sessionId":"synthetic-smoke","inputTranscript":"Do you have iPhone 13 Pro Max in stock?","bot":{"id":"X","name":"hera-product-lookup-prod","localeId":"en_US","version":"1","aliasId":"prod","aliasName":"prod"},"interpretations":[{"intent":{"name":"FallbackIntent","state":"InProgress"},"nluConfidence":1.0}],"sessionState":{"intent":{"name":"FallbackIntent","state":"InProgress"},"sessionAttributes":{}}}' \
  ~/lex_out.json

cat ~/lex_out.json | python -m json.tool
# PASS: sessionAttributes.answer contains "iPhone 13 Pro Max" + one of {in stock, out of stock, available, stock}
# Plan 06.1-03 live result: "Yes, Do you have iPhone 13 Pro Max in stock? is available."
```

### CCP browser-softphone smoke (AWS-NAT-05) — DEFERRED

Verifies full PSTN-to-Polly loop. Currently DEFERRED until phone number unblock.

Once phone is claimed:

1. Open Connect Console -> us-east-1 -> click `hera-voice-prod` -> top-right **Open Connect** launches `https://hera-voice-prod.my.connect.aws/`.
2. Login. If no user exists, create one via `aws connect create-user --instance-id 2f9fbb50-4526-423a-8180-b9ec2cff6d96 ...` (see Plan 06.1-03 SUMMARY for full command).
3. Top-right CCP icon -> set status **Available**.
4. Use a separate phone (mobile) to dial the claimed US number.
5. After Polly greeting ("Welcome to Hera Apple Store. How can I help?") ends, speak: **"Do you have iPhone 13 Pro Max in stock?"**
6. Start stopwatch at end-of-question. Listen for Polly response. Stop stopwatch at first answer audio.

**PASS criteria:** audio response heard, contains "iPhone 13 Pro Max" + stock keyword (in stock / out of stock / available / stock), latency <= 5 seconds. Self-report in `.planning/phases/06.1-native-aws-voice-channel-amazon-connect/06.1-HUMAN-UAT.md`.

**FAIL paths** with Pitfall # in `06.1-RESEARCH.md`:

- >5 s latency -> KB Retrieve cross-region slow; check `/aws/lambda/hera-voice-lookup-prod` CW logs.
- Greeting then silence -> Lex resource policy denied (Pitfall 3); check `awscc_lex_resource_policy.connect_invoke`.
- Answer played twice -> Pitfall 8 double-playback; Lambda handler returns `messages[0].content = " "` to mitigate.
- Wrong product / no stock keyword -> KB Retrieve returned unexpected doc; sanity-check `bin/verify-kb.sh`.

### Cleanup paste-flow

```
cd infra/envs/prod

# If phone was claimed (after support ticket unblock), release FIRST:
aws connect release-phone-number --phone-number-id <id> --region us-east-1

# Then destroy module:
terraform destroy -target=module.aws_voice_channel -auto-approve \
  -var=agentcore_runtime_arn=arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD

# Wait 5-10 min for Connect to finalize (Pitfall 7), then verify:
aws connect list-instances --region us-east-1 --query 'InstanceSummaryList'
# Expect: []
```

24-hour-deferred Cost Explorer check (per D-38):

```
aws ce get-cost-and-usage --time-period Start=<yesterday>,End=<today> --granularity DAILY \
  --metrics UnblendedCost \
  --filter '{"Tags":{"Key":"Service","Values":["AmazonConnect","AmazonLex","Lambda"]}}'
# Expect: $0 after 24h propagation
```
