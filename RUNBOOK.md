# Hera Knowledge Base Runbook

Operational runbook for the Hera Bedrock Knowledge Base on S3 Vectors. Covers first deploy, manual catalog sync, verification, recovery from a half-failed apply, cleanup, and forward-looking next steps. English only — workshop content lives under `content/{vi,en}/`; this runbook is for operators.

## Pre-flight

Before the first deploy, the operator must have AWS CLI v2 installed and authenticated against the target account, Terraform 1.9 or newer on PATH, and `jq` available for the verify script. The default region for production is `ap-northeast-1`; the dev region is `us-east-1`. The most commonly missed step is enabling Amazon Titan Text Embeddings V2 model access in the Bedrock console for the chosen region — without that the data-source ingestion will fail with an `AccessDeniedException` from Bedrock at sync time, not at apply time (Pitfall A).

TODO(plan-03): pre-flight commands (`aws sts get-caller-identity`, Terraform install check, `jq` install check) and Bedrock model-access screenshot path.

## First deploy

The first deploy creates the source S3 bucket, the S3 Vectors bucket and index, the Bedrock Knowledge Base, the data source, and the KB service IAM role. Resource names are fixed (`hera-kb-prod`, `hera-kb-source-prod`, `hera-kb-vectors-prod`) — there is no random suffix, by design (D-12). This is run from `infra/envs/prod/` against the locked-in region.

TODO(plan-03): exact `terraform init` and `terraform apply` commands and the expected output line count.

## First sync

`terraform apply` creates the KB but does NOT auto-trigger ingestion (D-05, D-07). The operator manually copies the catalog files into the source bucket and starts an ingestion job. The job typically completes in under a minute for the four-document catalog; results may take 2 to 3 additional minutes to be visible to retrieve calls due to KB propagation lag (Pitfall C).

TODO(plan-03): `aws s3 cp catalog/*.md s3://...` plus `aws bedrock-agent start-ingestion-job` plus the `get-ingestion-job` poll loop with exact flag values.

## Verify

The `bin/verify-kb.sh` script issues a known-good retrieve query (`iPhone 13 Pro Max stock`) and asserts that at least one result is returned with a score above the documented threshold. It polls every 15 seconds for up to 5 minutes to absorb the post-sync propagation lag.

TODO(plan-03): `bin/verify-kb.sh` invocation, expected pass output, and how to interpret a timeout (most often: model access not enabled, or sync is still propagating — wait 2 minutes and re-run before declaring failure).

## Re-index after editing a product file

When a stock count or price changes in any `catalog/*.md`, the operator edits the file in place, uploads it back to S3, and starts another ingestion job. Bedrock Knowledge Base detects changed objects and incrementally re-embeds only the diff (D-06) — there is no need to delete and re-upload the full catalog.

TODO(plan-03): `aws s3 cp` plus `aws bedrock-agent start-ingestion-job` for the re-index workflow, and how to confirm only the changed object was re-embedded.

## Recovery from a half-failed apply

Because resource names are fixed (no random suffix), a half-failed apply that leaves orphan resources cannot be recovered with `terraform apply` alone — the second apply collides with the existing names. The recovery path is `terraform destroy` (which cleans up whatever was created) followed by `terraform apply` again (D-12, Pitfall #17). The cost of a full rebuild at workshop scale is well under one cent plus a few minutes.

TODO(plan-03): destroy-then-reapply walkthrough including the case where `destroy` itself partially fails and the operator must clean up specific resources by hand.

## Cleanup

When the workshop session is over, `terraform destroy` removes all resources created by this stack. Running `bin/verify-kb.sh --invert` afterwards confirms that the KB no longer responds to retrieve calls — this is the inverse-assertion path forward-referenced from Phase 4 (D-16).

TODO(plan-03): full `terraform destroy` walkthrough plus `bin/verify-kb.sh --invert` invocation and the expected access-denied or KB-not-found message.

## Next steps (deferred)

- Remote Terraform backend (S3 versioned + DynamoDB lock) — out of v1 scope per D-11. For v1 the workshop default is local state. When the project grows past one operator, bootstrap a separate state-backend stack first, then migrate this stack with `terraform init -migrate-state`.
- Consumer `bedrock:Retrieve` role for Pipecat — Phase 2 (D-10). Phase 1 only outputs `kb_arn` so Phase 2 can scope its consumer role policy.
- Bedrock Guardrails (PII redaction) — out of v1 per PROJECT.md.
