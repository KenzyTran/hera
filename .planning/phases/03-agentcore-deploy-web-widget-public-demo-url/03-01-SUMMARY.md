---
phase: 03-agentcore-deploy-web-widget-public-demo-url
plan: 01
subsystem: infra
tags: [terraform, aws, iam, ecr, s3, cloudfront, agentcore, oac, hsts]

# Dependency graph
requires:
  - phase: 02-pipecat-voice-agent-local
    provides: kb_consumer_policy module exposing hera-kb-retrieve-prod policy_arn (D-22 ready-to-attach)
  - phase: 01-knowledge-base-foundation
    provides: knowledge_base module (KB BKXE19AH89, region ap-northeast-1, account 851725411875)
provides:
  - agentcore_iam module (exec role hera-agentcore-exec-prod + inline bidi/logs policy + log group + KB managed-policy attachment)
  - widget_hosting module (private S3 hera-widget-prod + CloudFront E10K3B1L8PQ9EC with OAC + HSTS + nosniff)
  - ecr module (private hera-agent repo, IMMUTABLE tags, scan-on-push, untagged-keep-5 lifecycle)
  - 8 new prod-root outputs consumed by Plans 03-03 and 03-04
  - live AWS resources in 851725411875/ap-northeast-1 (12 created, 0 destroyed)
affects:
  - 03-03 (push-image consumes ecr_repo_url)
  - 03-04 (CDK stack consumes agentcore_exec_role_arn + agentcore_log_group_arn + widget_cloudfront_url + widget_s3_bucket_name + widget_cloudfront_distribution_id)
  - phase-04 (CloudWatch dashboards/alarms attach to agentcore_log_group_arn; cleanup-verify probes the same resource set)

# Tech tracking
tech-stack:
  added: [aws_cloudfront_distribution, aws_cloudfront_origin_access_control, aws_cloudfront_response_headers_policy, aws_ecr_repository, aws_ecr_lifecycle_policy, aws_iam_role_policy_attachment, aws_cloudwatch_log_group]
  patterns:
    - "Four-file module shape mirrored across new agentcore_iam, widget_hosting, ecr modules (versions/variables/main/outputs)"
    - "Phase-N IAM ships, Phase-N+1 attaches (RESEARCH P7) — D-22 closes here via aws_iam_role_policy_attachment.kb_retrieve"
    - "Confused-deputy mitigation on AgentCore role trust: aws:SourceAccount + AWS:SourceArn ArnLike on bedrock-agentcore:runtime/*"
    - "CloudFront OAC (not legacy OAI) with empty origin_access_identity required by provider"
    - "Documented zero-wildcard exception: cloudwatch:PutMetricData Resource=* gated by cloudwatch:namespace StringEquals condition"
    - "Empty conventional commit captures live deploy events (no source diff but verifiable AWS-side outcome)"

key-files:
  created:
    - infra/modules/agentcore_iam/{versions,variables,main,outputs}.tf
    - infra/modules/widget_hosting/{versions,variables,main,outputs}.tf
    - infra/modules/ecr/{versions,variables,main,outputs}.tf
  modified:
    - infra/envs/prod/main.tf (appended data aws_caller_identity + 3 module blocks)
    - infra/envs/prod/outputs.tf (5 -> 13 outputs)
    - .gitignore (added plan.out per Plan 02-03 deferred item)

key-decisions:
  - "AgentCore trust principal = bedrock-agentcore.amazonaws.com (NOT bedrock.amazonaws.com — Phase 1 Pitfall I principal differs at the AgentCore layer; live apply accepted the principal first attempt, no MalformedPolicyDocument fallback needed)"
  - "Sonic foundation-model ARN defaulted to amazon.nova-sonic-v1:0 (placeholder per [needs-verification]; live apply succeeded — Bedrock validates the ARN syntax not the model existence at IAM-policy create time; runtime InvokeModelWithBidirectionalStream is the actual gate, deferred to Plan 03-04 smoke)"
  - "CloudFront MinimumProtocolVersion silently downgrades from TLSv1.2_2021 to TLSv1 when CloudFrontDefaultCertificate=true — AWS-side override (default *.cloudfront.net cert supports clients down to TLSv1 to maximize reach). HTTPS still enforced via viewer_protocol_policy=redirect-to-https. Custom-domain ACM cert (deferred per D-26) would unlock TLSv1.2_2021 minimum"
  - "ECR force_delete=false by default — Phase 4 cleanup-verify must explicitly aws ecr delete-repository --force; protects pushed images from accidental terraform destroy"
  - "ECR :latest mutable tag IMPOSSIBLE on IMMUTABLE repo; Plan 03-03 push-script must NOT pass -t :latest (documented in module main.tf header)"
  - "force_destroy=true on widget S3 bucket preferred over versioning — rollback path is git checkout + bin/deploy-widget.sh per RUNBOOK"

patterns-established:
  - "Live-apply commit pattern: --allow-empty conventional commit with live outputs + acceptance-gate results in commit body — captures deploy event in git history when no source diff occurred"
  - "Acceptance gate runner: 5 parallel aws CLI calls (list-attached-role-policies, describe-repositories, get-distribution, get-public-access-block, get-role-policy) verifying live state matches plan must_haves"
  - "Python regex sweep for IAM wildcards across infra/**/*.tf — single match expected (the documented cloudwatch:PutMetricData exception)"

requirements-completed: [DEP-03, DEP-04, DEP-05, DEP-06, WID-01, DEM-01]

# Metrics
duration: ~50min
completed: 2026-05-06
---

# Phase 3 Plan 01: AgentCore IAM + ECR + Widget Hosting Terraform Footprint Summary

**Three new Terraform modules wired into prod root and applied live: AgentCore exec role hera-agentcore-exec-prod with KB managed-policy attached (D-22 closed), private hera-agent ECR repo with IMMUTABLE tags, and S3+CloudFront widget hosting at https://dg0w939ktclw6.cloudfront.net with OAC + HSTS — 12 resources created in account 851725411875/ap-northeast-1, zero destroyed.**

## Performance

- **Duration:** ~50 min (Tasks 1-4 by prior executor + checkpoint approval gap + Task 5 apply + diagnostics)
- **Started:** 2026-05-06 (Tasks 1-4 commit window)
- **Completed:** 2026-05-06T03:47Z (post-apply diagnostics)
- **Tasks:** 5 (4 auto + 1 checkpoint:human-verify)
- **Files modified:** 15 (12 created across 3 new modules, 2 prod-root extensions, 1 .gitignore update)
- **AWS resources created:** 12 (1 IAM role, 1 inline role-policy, 1 role-attachment, 1 CW log group, 1 ECR repo, 1 ECR lifecycle policy, 1 S3 bucket, 1 PAB, 1 OAC, 1 CloudFront distribution, 1 CF response-headers policy, 1 S3 bucket policy)
- **CloudFront distribution wall-clock:** 2m50s (faster than the 8-15 min D-26 estimate)

## Accomplishments

- AgentCore exec role hera-agentcore-exec-prod live, trust principal bedrock-agentcore.amazonaws.com accepted first try (no Pitfall-I fallback needed), confused-deputy guards in place (aws:SourceAccount + AWS:SourceArn ArnLike on bedrock-agentcore:runtime/*).
- Phase 2 D-22 deferral closed: hera-kb-retrieve-prod managed policy attached to the new exec role; verified via aws iam list-attached-role-policies.
- Inline bidi/logs/metrics policy verified zero-wildcard except the AWS-mandated cloudwatch:PutMetricData Resource=* exception (gated by cloudwatch:namespace = hera/agentcore StringEquals condition — D-13 honored).
- ECR repo hera-agent live with imageTagMutability=IMMUTABLE and scanOnPush=true; lifecycle policy keeps last 5 untagged.
- Widget hosting live: S3 hera-widget-prod with all four PAB flags true; CloudFront E10K3B1L8PQ9EC with OAC as the only allowed reader; HTTPS-only via redirect-to-https; HSTS (max-age 31536000, includeSubDomains) + X-Content-Type-Options: nosniff active and verified via curl -I returning Strict-Transport-Security and X-Content-Type-Options headers in the live 403 response.
- 8 new prod-root outputs unblocking Plans 03-03 (ecr_repo_url) and 03-04 (agentcore_exec_role_arn, agentcore_log_group_arn, widget_*_url/bucket_name/distribution_id).
- plan.out gitignore entry landed (closes Plan 02-03 deferred repo-hygiene item).

## Task Commits

Each task committed atomically:

1. **Task 1: agentcore_iam module** — `4529fa1` (feat) — exec role + inline policy + log group + KB attach
2. **Task 2: widget_hosting module** — `7817942` (feat) — private S3 + CloudFront with OAC
3. **Task 3: ecr module** — `8f7e7f6` (feat) — immutable scan-on-push private repo
4. **Task 4: prod-root wiring** — `f8ba30a` (feat) — 3 module blocks + data aws_caller_identity + 8 new outputs
5. **Task 5: live terraform apply** — `adf966c` (feat, --allow-empty) — 12 resources created with full output capture in commit body

**Plan metadata:** (see final commit at end — SUMMARY + STATE + ROADMAP)

## Files Created/Modified

- `infra/modules/agentcore_iam/versions.tf` — provider pin (aws ~> 6.27, terraform >= 1.9), byte-identical to kb_consumer_policy/versions.tf
- `infra/modules/agentcore_iam/variables.tf` — name_prefix/env/region/account_id/kb_retrieve_policy_arn/sonic_model_arn inputs (no defaults on cross-cutting injectables)
- `infra/modules/agentcore_iam/main.tf` — 6 resources (trust data + role + log group + inline data + inline role_policy + KB role_policy_attachment); zero defensive blocks
- `infra/modules/agentcore_iam/outputs.tf` — role_arn/role_name/log_group_arn/log_group_name
- `infra/modules/widget_hosting/versions.tf` — same provider pin
- `infra/modules/widget_hosting/variables.tf` — bucket_name (default hera-widget-prod, D-12) + comment
- `infra/modules/widget_hosting/main.tf` — 7 resources (S3 + PAB + OAC + response-headers policy + CloudFront distribution + bucket policy data + bucket policy resource)
- `infra/modules/widget_hosting/outputs.tf` — s3_bucket_name/s3_bucket_arn/cloudfront_domain/cloudfront_url/cloudfront_distribution_id
- `infra/modules/ecr/versions.tf` — same provider pin
- `infra/modules/ecr/variables.tf` — name (default hera-agent) + keep_last_n_untagged (default 5)
- `infra/modules/ecr/main.tf` — 2 resources (repo + lifecycle policy)
- `infra/modules/ecr/outputs.tf` — repository_url/repository_arn/repository_name
- `infra/envs/prod/main.tf` — appended data aws_caller_identity.current + module ecr + module widget_hosting + module agentcore_iam blocks
- `infra/envs/prod/outputs.tf` — added 8 new outputs (ecr_repo_url, agentcore_exec_role_arn, agentcore_exec_role_name, agentcore_log_group_arn, agentcore_log_group_name, widget_cloudfront_url, widget_s3_bucket_name, widget_cloudfront_distribution_id) on top of the 5 existing
- `.gitignore` — added plan.out (Plan 02-03 deferred item closed)

## Live AWS Resource IDs

| Output | Value |
|--------|-------|
| `agentcore_exec_role_arn` | `arn:aws:iam::851725411875:role/hera-agentcore-exec-prod` |
| `agentcore_exec_role_name` | `hera-agentcore-exec-prod` |
| `agentcore_log_group_arn` | `arn:aws:logs:ap-northeast-1:851725411875:log-group:/aws/bedrock-agentcore/hera-agent` |
| `agentcore_log_group_name` | `/aws/bedrock-agentcore/hera-agent` |
| `ecr_repo_url` | `851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent` |
| `widget_cloudfront_url` | `https://dg0w939ktclw6.cloudfront.net` |
| `widget_cloudfront_distribution_id` | `E10K3B1L8PQ9EC` |
| `widget_s3_bucket_name` | `hera-widget-prod` |

## Acceptance Gate Results (live AWS)

All 5 verification gates passed against ap-northeast-1:

1. **D-22 closed** — `aws iam list-attached-role-policies --role-name hera-agentcore-exec-prod` returns exactly one policy: `arn:aws:iam::851725411875:policy/hera-kb-retrieve-prod`.
2. **ECR shape** — `aws ecr describe-repositories --repository-names hera-agent` returns `imageTagMutability=IMMUTABLE`, `scanOnPush=true`.
3. **CloudFront** — `aws cloudfront get-distribution --id E10K3B1L8PQ9EC` returns `Status=Deployed`, `CloudFrontDefaultCertificate=true`. (See observation under "Decisions Made" about MinimumProtocolVersion downgrade.)
4. **S3 PAB** — `aws s3api get-public-access-block --bucket hera-widget-prod` returns all 4 flags `true`.
5. **D-13 zero-wildcard** — `aws iam get-role-policy --role-name hera-agentcore-exec-prod --policy-name hera-agentcore-exec-inline` shows 3 statements: BedrockSonicBidiStream (Resource = Sonic ARN), CloudWatchLogsScopedToAgentCoreGroup (Resource = log-group ARN x2 forms), CloudWatchEMFMetrics (Resource=* gated by cloudwatch:namespace=hera/agentcore). Python regex sweep across infra/**/*.tf finds exactly one wildcard hit, matching the documented exception line.
6. **Reachability** — `curl -I https://dg0w939ktclw6.cloudfront.net/` returns `HTTP/1.1 403 Forbidden` with `Server: AmazonS3`, `X-Content-Type-Options: nosniff`, and `Strict-Transport-Security: max-age=31536000; includeSubDomains`. The 403 is the correct empty-bucket-via-OAC behavior; Plan 03-02 + 03-04 will populate the bucket.

## Decisions Made

- **AgentCore trust principal = `bedrock-agentcore.amazonaws.com`** accepted first try — no MalformedPolicyDocument, no fallback to `bedrock.amazonaws.com` (Pitfall I) needed. The AgentCore service principal differs from the foundation-model Bedrock principal Phase 1 used.
- **Sonic foundation-model ARN `amazon.nova-sonic-v1:0`** flagged `[needs-verification]` in PLAN.md; IAM-policy creation only validates ARN syntax, not model existence. The actual model availability is gated at runtime InvokeModelWithBidirectionalStream — deferred to Plan 03-04 smoke. If Plan 03-04 finds the runtime rejects this id, override `sonic_model_arn` at the prod root after `aws bedrock list-foundation-models --by-output-modality SPEECH --region ap-northeast-1`.
- **CloudFront MinimumProtocolVersion silent downgrade** — set to `TLSv1.2_2021` in TF, returned as `TLSv1` by the API. AWS-side behavior: when `CloudFrontDefaultCertificate=true` (default `*.cloudfront.net` cert), AWS forces the minimum to `TLSv1` to maximize client reach. HTTPS-only is still enforced via `viewer_protocol_policy=redirect-to-https`. Custom-domain ACM cert (deferred per D-26) would unlock the requested `TLSv1.2_2021` minimum. Documented behavior, not a regression.
- **CloudFront wall-clock 2m50s** — faster than the 8-15 min D-26 estimate. Worth noting because the Phase 4 cleanup-verify timing budget can lean on the same fast-path assumption.
- **Empty deploy commit pattern** — Task 5 produced no source diff (state file is gitignored, plan.out is gitignored). `git commit --allow-empty` with live outputs + gate results in the body captures the deploy event in git history while preserving the per-task commit-atomicity contract.

## Deviations from Plan

None — plan executed exactly as written. The Pitfall-I fallback path documented in PLAN.md Task 1 was not triggered (bedrock-agentcore.amazonaws.com accepted on first apply). The CloudFront MinimumProtocolVersion downgrade is an AWS-side behavior, not a deviation in our config.

## Issues Encountered

None — all 5 acceptance gates passed first run.

## Threat Flags

None new beyond the plan's `<threat_model>` register. Plan 03-01 created 12 AWS resources, all fall inside the documented STRIDE register T-03-01-01..07. No surface introduced outside that scope.

## User Setup Required

None ongoing — Task 5 consumed the AWS credentials via the same identity Phase 1+2 used. Plans 03-03 and 03-04 will reuse those credentials.

## Next Phase Readiness

**Wave 2 unblocked (03-03 push-image.sh):**
- `ecr_repo_url = 851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent` is live and ready for `docker buildx push -t ${url}:${git_sha}`. Reminder for Plan 03-03 author: NO `:latest` tag — IMMUTABLE mutability rejects retag.

**Wave 3 unblocked (03-04 CDK AgentCore stack):**
- All consumed outputs live: `agentcore_exec_role_arn`, `agentcore_log_group_arn`, `widget_cloudfront_url`, `widget_s3_bucket_name`, `widget_cloudfront_distribution_id`.
- Sonic foundation-model ARN runtime gate is the smoke responsibility — if `bedrock:InvokeModelWithBidirectionalStream` returns `AccessDenied` or `ResourceNotFound` for `amazon.nova-sonic-v1:0`, override the module input at the prod root and `terraform apply` to swap the inline policy.

**Phase 4 hand-off seeds:**
- CloudWatch log group `/aws/bedrock-agentcore/hera-agent` exists for OBS-01..03 dashboards/alarms.
- Cost circuit-breaker (OBS-05) Lambda will need permission to update the AgentCore endpoint (out of Phase 3 scope).

**Open items / parking lot:**
- Custom domain + ACM cert for CloudFront (deferred per D-26; would also unlock TLSv1.2_2021 minimum).
- Versioning on widget S3 bucket (deferred per D-26 — rollback is git + bin/deploy-widget.sh).
- Sonic model ARN [needs-verification] (verified at runtime in Plan 03-04 smoke).

## Self-Check

Files created/modified verified present:
- infra/modules/agentcore_iam/{versions,variables,main,outputs}.tf — all 4 present
- infra/modules/widget_hosting/{versions,variables,main,outputs}.tf — all 4 present
- infra/modules/ecr/{versions,variables,main,outputs}.tf — all 4 present
- infra/envs/prod/{main,outputs}.tf — modified

Commits verified in git log:
- 4529fa1, 7817942, 8f7e7f6, f8ba30a, adf966c — all 5 Task commits present and reachable.

Live AWS resources verified via AWS CLI:
- IAM role hera-agentcore-exec-prod live with kb_retrieve attachment
- ECR hera-agent live with IMMUTABLE + scan-on-push
- S3 hera-widget-prod live with PAB all-true
- CloudFront E10K3B1L8PQ9EC live with default cert + HSTS + nosniff headers (curl -I confirmed)

## Self-Check: PASSED

---
*Phase: 03-agentcore-deploy-web-widget-public-demo-url*
*Completed: 2026-05-06*
