---
title: "3.1 Knowledge Base"
date: 2025-01-01
weight: 1
---

## Goal of this section

Deploy a Bedrock Knowledge Base on S3 Vectors with Titan v2 embeddings, ingest the Apple catalog, and verify the Retrieve API returns the right document for the query "iPhone 13 Pro Max stock". After this step the KB is ready for the Pipecat agent in Phần 3.2 to call via the `lookup_product` tool.

## Catalog structure

The Apple catalog consists of 4 markdown files under `catalog/`. Stock and price are inlined in each file so retrieval chunks always co-locate stock with the SKU name (D-03 Phase 1) — Sonic does not have to join multiple chunks to assemble an answer.

```bash
ls catalog/
# apple-watch-s11.md  iphone-13-pro-max.md  macbook-pro-m4.md  store-policy.md
```

*Source: catalog/ — Phase 1 Plan 01-01*

## Step 1: Deploy infra (Terraform)

The `infra/modules/knowledge_base/` module creates the S3 source bucket + S3 Vectors bucket + index + Bedrock KB + data source + KB service IAM role. Resource names are fixed (no random suffix per D-12) — retrying after a partial failure means `terraform destroy && terraform apply`, not `terraform import`.

```bash
cd infra/envs/prod
terraform init
terraform apply
# Review the plan (about 9 resources). Type 'yes' to apply.
cd ../../..
```

*Source: RUNBOOK.md (First deploy) — Phase 1 Plan 01-02*

Completes in ~30-60 seconds. Outputs: `kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`. Both buckets are empty at this point — the next step uploads catalog content.

## Step 2: Ingest catalog (manual sync)

`terraform apply` creates the KB but does NOT auto-trigger ingestion (D-05, D-07). You upload `catalog/*.md` into the S3 source bucket, then call `aws bedrock-agent start-ingestion-job` so the KB embeds + indexes them. The job typically completes in under a minute for 4 documents.

```bash
# 1. Resolve outputs from terraform state
KB_ID=$(terraform -chdir=infra/envs/prod output -raw kb_id)
DS_ID=$(terraform -chdir=infra/envs/prod output -raw data_source_id)
SRC_BUCKET=$(terraform -chdir=infra/envs/prod output -raw source_bucket_name)
REGION=ap-northeast-1

# 2. Upload all catalog markdown to the catalog/ prefix
aws s3 cp catalog/ "s3://${SRC_BUCKET}/catalog/" --recursive --exclude "*" --include "*.md"

# 3. Trigger the ingestion job
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

*Source: RUNBOOK.md (First sync) — Phase 1 Plan 01-03*

Note the two CLI surfaces (Pitfall J from RUNBOOK): `aws bedrock-agent` is the build-time control plane (KBs, agents, ingestion jobs). `aws bedrock-agent-runtime` is the runtime data plane (Retrieve, RetrieveAndGenerate). Sync uses `bedrock-agent`; verify in Step 3 uses `bedrock-agent-runtime`.

## Step 3: Verify Retrieve API

After the ingestion job reports `COMPLETE`, vectors are written but may not be queryable immediately — run `bin/verify-kb.sh` to poll the Retrieve API until the top score exceeds threshold 0.4.

```bash
bin/verify-kb.sh
```

*Source: bin/verify-kb.sh — Phase 1 Plan 01-03*

Final output on success:

```
OK: 3 results returned, top score 0.78 >= threshold 0.4
```

The script polls every 15 seconds up to 20 times (5 minutes total) to absorb post-sync propagation lag. On the live KB `BKXE19AH89`, the measured top score for the default query "iPhone 13 Pro Max stock" was `0.86`.

{{% notice warning %}}
**KB sync delay after ingestion:** after the ingestion job reports `COMPLETE`, vectors are written but it can take another 2-3 minutes before the Bedrock KB Retrieve API returns them. This is documented AWS behavior, not a bug. `bin/verify-kb.sh` polls for up to 5 minutes to absorb this delay. If results stay empty after 5 minutes, check:

- `inclusion_prefixes = ["catalog/"]` in the data source matches the prefix you uploaded to (`s3://<bucket>/catalog/`).
- The ingestion job actually reached `COMPLETE` (not `FAILED`):
  `aws bedrock-agent list-ingestion-jobs --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" --region "${REGION}"`.
- Bedrock model access for `amazon.titan-embed-text-v2:0` is enabled in the deploy region (Phần 2). Empty results after a `COMPLETE` job is usually a model-access miss in a different region.

*Source: bin/verify-kb.sh — Phase 1 Plan 01-03*
{{% /notice %}}

## Step 4: Re-index after editing catalog

When a stock count or price changes, edit the `catalog/*.md` file in place, re-upload, then call the same `start-ingestion-job` command. Bedrock KB detects the changed document and incrementally re-embeds only the diff (D-06) — no need to delete and re-upload the entire catalog.

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

*Source: RUNBOOK.md (Re-index) — Phase 1 Plan 01-03*

Bedrock KB ingestion is incremental — only the modified document is re-embedded; cost is well under one cent at workshop scale.

## Next

The KB is deployed and queryable. Phần 3.2 runs the Pipecat agent locally; the `lookup_product` tool inside the agent calls `aws bedrock-agent-runtime retrieve` against this same KB — you already have `kb_id` from `terraform output -raw kb_id` to export as the `HERA_KB_ID` env var for the agent.
