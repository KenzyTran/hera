---
title: "Clean up"
date: 2025-01-01
weight: 4
chapter: true
pre: "<b>4. </b>"
---

# Clean up

{{% notice warning %}}
**Don't skip this chapter.** AgentCore Runtime + Bedrock Knowledge Base + S3
Vectors + CloudFront keep billing (~$0.05/hour and up) until you tear them
down. Run the 3 steps below RIGHT after your session ends, then verify Cost
Explorer 24 hours later (D-38) to confirm $0 ongoing cost.
{{% /notice %}}

## Goal of this chapter

Tear down every AWS resource the workshop created (Phases 1-4) back to $0 ongoing cost. Verify with `bin/cleanup-verify.sh` (19 read-only checks) immediately after destroy, and confirm $0 in Cost Explorer 24 hours later (because Cost Explorer has ingestion lag).

## Cleanup contract: required ordering (D-24)

**CDK first, Terraform second.** The AgentCore Runtime resource (managed by CDK) holds the IAM exec role + log group + container image references that Terraform creates. If you run `terraform destroy` first, it fails because the IAM role is still `InUse` by the Runtime — you'd have to re-run after `cdk destroy` anyway, so do it in the right order the first time.

Verify-only script (D-39): `bin/cleanup-verify.sh` only READS — it never destroys anything. Operator destroys; the script verifies. This is a deliberate design choice — the script has no permission to accidentally tear down a production resource.

Region pin: run `cdk destroy` and `terraform destroy` in the region you deployed (default `ap-northeast-1`). If you deployed to a different region, set `HERA_REGION` before running `bin/cleanup-verify.sh`.

## Step 1: cdk destroy hera-agentcore

```bash
(cd infra/cdk && uv run cdk destroy hera-agentcore --force)
```
*Source: RUNBOOK.md (Phase 4 Cleanup Step 1) — Phase 4 Plan 04-03*

CDK destroys the AgentCore Runtime first. When done: the IAM exec role is unattached + the log group is flushed (24h retention) + container image references are freed. Takes about 30-60 seconds. After this step, Terraform can destroy the IAM role without hitting `Role still in use` errors.

## Step 2: terraform destroy

```bash
(cd infra/envs/prod && terraform destroy -auto-approve)
```
*Source: RUNBOOK.md (Phase 4 Cleanup Step 2) — Phase 4 Plan 04-03*

`terraform destroy` tears down the rest: Knowledge Base + S3 source bucket + S3 Vectors + IAM (5 roles + policies) + ECR repo + widget S3+CloudFront + observability dashboard + 3 alarms + presigner Lambda + Function URL.

{{% notice warning %}}
**CloudFront takes 15-30 minutes for the disable-then-delete cycle. DO NOT
interrupt:** if you Ctrl+C during this cycle, the distribution will get stuck
at `Enabled=false, Deployed=true` and you'll need to re-run `terraform destroy`
to finish. Just let it run. CloudFront in AWS has a periodic propagation
schedule — accept it and go grab a coffee.

*Source: RUNBOOK.md (Phase 4 Cleanup Step 2 warning) — Phase 4 Plan 04-03*
{{% /notice %}}

## Step 3: bin/cleanup-verify.sh

```bash
bash bin/cleanup-verify.sh
```
*Source: bin/cleanup-verify.sh — Phase 4 Plan 04-03*

What the script does:

- 19 read-only AWS API calls across regions/services: Knowledge Base, S3 source bucket, S3 Vectors index, AgentCore Runtime, ECR, widget S3 + CloudFront, IAM (5 roles + 1 policy), log groups, 3 alarms, 1 dashboard, presigner Lambda Function URL.
- Each check increments `PASS_COUNT` or `FAIL_COUNT`.
- Exits 0 if everything is gone; exits 1 with a hint block if anything remains.
- Helper-driven: `_check_gone` (alternation regex `ResourceNotFound|NoSuchEntity|NotFound|...`) + `_check_count_zero` (length(@) query).
- Windows-bash quirk: `MSYS_NO_PATHCONV=1` prefix on log-group calls (PITFALL G.8 — Git Bash mangles paths starting with `/`).

Expected output (success):

```
----------------------------------------
cleanup-verify: 19/19 resource checks passed
OK: all phase 1/2/3/4 resources gone
```

{{% notice info %}}
**Hero screenshot deferred:** the all-green PASS terminal capture for
`bin/cleanup-verify.sh` will land in a follow-up commit after the
post-workshop-close verification sweep (04-HUMAN-UAT item #3 — first
organic cleanup-verify run against actually-torn-down state). Until
then this section ships text-only; the script exit-0 + the success
block above are the canonical evidence.
{{% /notice %}}

## If cleanup-verify FAILs

Common causes (from RUNBOOK Phase 4):

- Step 1 / Step 2 reversed (D-24 — CDK must destroy before Terraform).
- `terraform destroy` interrupted during the CloudFront 15-30 minute cycle — just re-run it.
- ECR repo still has images (default `force_delete=false`) — fallback by deleting images manually:

  ```bash
  aws ecr batch-delete-image --repository-name hera-agent \
    --image-ids imageTag=<tag1> imageTag=<tag2> \
    --region ap-northeast-1
  ```
  *Source: RUNBOOK.md (Phase 4 ECR fallback) — Phase 4 Plan 04-03*

- Or set `var.force_delete = true` in `infra/envs/prod` and re-run `terraform destroy`.

After clearing the root cause, re-run `bash bin/cleanup-verify.sh` until 19/19 PASS.

## Verify $0 ongoing cost (24h after destroy — D-38)

Cost Explorer has up to 24 hours of ingestion lag. Run this paste-line TOMORROW after destroy, not now. The instant number at end-of-session won't reflect reality yet — this is an AWS service constraint, not a bug.

Each Cost Explorer API call costs $0.01. Running it once is fine; if an instructor runs it 90 times across a learner cohort, that's $0.90 — which is why this paste-line lives in this chapter as a personal follow-up (operator-driven), not auto-run from a script.

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
*Source: RUNBOOK.md (Phase 4 Verify $0 ongoing cost) — Phase 4 Plan 04-03*

Expected output: `"0"` or `"0.0000000000"` (string). Anything non-zero indicates a leftover billable resource — re-run `bin/cleanup-verify.sh` and investigate (CloudFront stuck-disable, hanging KB ingestion job, or undeleted ECR images are the three most common causes).

Important note: Cost Explorer is region-pinned to `us-east-1` regardless of where you deployed; the `--region us-east-1` flag above is for clarity (the CLI auto-routes if you omit it).

## Next

Your AWS account is back to $0 ongoing cost. Phần 5 wraps up with a cost recap + an expansion roadmap (Twilio voice, multi-language, multi-agent routing) — v2 directions you can build on top of the foundation you just shipped.
