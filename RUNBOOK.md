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

## Next steps (deferred)

- Remote Terraform backend (S3 versioned + DynamoDB lock) — out of v1 scope per D-11. For v1 the workshop default is local state. When the project grows past one operator, bootstrap a separate state-backend stack first, then migrate this stack with `terraform init -migrate-state`.
- Consumer `bedrock:Retrieve` role for Pipecat — Phase 2 (D-10). Phase 1 only outputs `kb_arn` so Phase 2 can scope its consumer role policy.
- Bedrock Guardrails (PII redaction) — out of v1 per PROJECT.md.
