---
title: "Preparation"
date: 2025-01-01
weight: 2
chapter: true
pre: "<b>2. </b>"
---

### Preparation

# Environment Setup

In this section you configure a clean AWS account so you can deploy Hera in Phần 3 without getting blocked on one-time UI gates (model access, billing alerts) or missing local tools.

## Goals

By the end of this chapter you have: AWS account ready, model access enabled for Nova 2 Sonic + Titan v2, local tools installed (AWS CLI v2, Terraform, uv, Docker with buildx, jq), credentials configured, and a cost expectation for a ~2-hour session.

## AWS Account checklist

- You have your own AWS account — not a shared one. Avoid running as the root user; use an IAM user or IAM Identity Center identity instead.
- IAM permissions allow create/destroy on: Bedrock, AgentCore, ECR, S3, CloudFront, CloudWatch, IAM (for deploy), Lambda. The simplest setup for workshop scope is `AdministratorAccess` on your IAM user (this is a personal demo, not production).
- Target region: `ap-northeast-1` (Tokyo). Workshop default per D-47. If you are elsewhere, other regions with Nova 2 Sonic + AgentCore are `us-east-1`, `us-west-2`, `eu-north-1` — change the `region` variable in `infra/envs/prod/terraform.tfvars` before `terraform apply`.
- Billing Alerts ticked: AWS Console > Billing > Billing Preferences > "Receive Billing Alerts". This is one-time per account; takes ~15 minutes after ticking before the alarm starts receiving data — without it, the billing alarm sits in `INSUFFICIENT_DATA` forever even though resources are deployed.
- You can run `aws sts get-caller-identity` successfully on your local machine (see "Configure AWS credentials" below).

## Enable Bedrock model access (per-region, per-model)

AWS gates Bedrock foundation models per-account-per-region. The workshop uses 3 models in `ap-northeast-1`:

- `amazon.nova-sonic-v1:0` — Nova 2 Sonic, bidirectional speech-to-speech, used by the voice loop.
- `amazon.titan-embed-text-v2:0` — Titan Text Embeddings v2, used by the Knowledge Base for embeddings (1024-dim float32 cosine).
- AgentCore Runtime is not a foundation model, but it does need a region that supports it; `ap-northeast-1` covers all three.

Steps:

- Open `https://console.aws.amazon.com/bedrock/` in region `Asia Pacific (Tokyo) ap-northeast-1` (check the region selector in the top right).
- Click "Model access" → "Modify model access" → tick `Amazon Nova 2 Sonic` + `Amazon Titan Text Embeddings V2` → Submit. Takes ~1 minute to flip to `Granted`.
- Verify via CLI:

```bash
aws bedrock list-foundation-models --region ap-northeast-1 \
  --query 'modelSummaries[?modelId==`amazon.titan-embed-text-v2:0`].modelLifecycle.status' \
  --output text
# Expect: ACTIVE
```

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-03*

Repeat for `amazon.nova-sonic-v1:0`. Empty output means model access is not yet enabled.

![Bedrock Console — Model Access for Nova 2 Sonic + Titan v2 (ap-northeast-1)](/images/2-preparation/console-bedrock-model-access.png)

{{% notice warning %}}
**Bedrock model access is per-region, per-model:** if you skip this, `terraform apply` in Phần 3.1 still passes but `aws bedrock-agent start-ingestion-job` fails with `AccessDeniedException` on the model ARN — the error surfaces at sync time, not apply time. If you deploy in a different region (`us-east-1`, `us-west-2`, `eu-north-1`), you must enable each model again in that region — IAM in the original region does not carry over.

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-03*
{{% /notice %}}

## Install AWS CLI v2

The workshop uses AWS CLI v2 (v1 lacks some `bedrock-agent*` commands we use in Phần 3.1).

```bash
aws --version
# Expect: aws-cli/2.x.x
```

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-01*

If missing, follow: `https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html`.

## Install Terraform >= 1.9

Phase 1 and Phase 2 IaC require `hashicorp/aws ~> 6.27` — Terraform CLI 1.9 or newer satisfies this provider.

```bash
terraform -version
# Expect: Terraform v1.9.x or newer
```

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-01*

Install: `https://developer.hashicorp.com/terraform/install`.

## Install uv (Python package manager)

The workshop uses `uv` exclusively — no `pip`, no direct `python3 ...`. `uv` manages Python 3.12 + the lockfile for the `agent/` project and ensures you install the exact Pipecat 1.1.0 version that was tested.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
# Expect: uv 0.10 or newer
```

*Source: agent/pyproject.toml — Phase 2 Plan 02-01*

## Install Docker Desktop with buildx

Phần 3.3 builds a multi-arch container (`linux/arm64` + `linux/amd64`) via `docker buildx`. AgentCore Runtime is ARM64-only so the arm64 manifest is required for deploy; the same image artifact still runs on a local AMD64 dev machine. `buildx` ships with Docker Desktop 20.10+ and Docker Engine 20.10+.

```bash
docker --version
docker buildx version
# Expect: docker buildx 0.x.x or newer
```

*Source: agent/Dockerfile — Phase 2 Plan 02-02*

## Install jq

`jq` is the JSON parser used by `bin/verify-kb.sh` and several paste-blocks in Phần 3.1.

```bash
jq --version
# Install: winget install jqlang.jq (Windows)
#          brew install jq            (macOS)
#          apt-get install jq         (Debian/Ubuntu)
```

*Source: bin/verify-kb.sh — Phase 1 Plan 01-03*

## Configure AWS credentials

The Pipecat agent (Phần 3.2) reads credentials via the boto3 default chain (env vars → `~/.aws` → IMDSv2). Configure either way:

```bash
# Long-lived IAM user access keys
aws configure

# Or short-lived SSO / IAM Identity Center
aws configure sso

# Verify resolution
aws sts get-caller-identity
# Expect: prints account ID + IAM ARN you will deploy into
```

*Source: RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-01*

If you use SSO, remember to run `aws sso login` before each session — short-lived credentials expire after ~1 hour.

## Cost expectations

- A full workshop session ~2 hours (build + talk to the agent + cleanup) costs **~$2-5 USD** ballpark if you follow Phần 4 Cleanup right after. Phần 5 Summary will be post-launch updated when the instructor has real numbers.
- Two main cost drivers: Bedrock Nova 2 Sonic streaming (charged per active conversation minute) + AgentCore Runtime (charged per active session-second). KB + S3 Vectors + CloudFront at workshop scale stay under one cent.
- **Important:** run Phần 4 Cleanup (cdk destroy → terraform destroy → `bin/cleanup-verify.sh`) right after you finish the session so charges stop. Cost Explorer has up to 24 hour ingestion lag — verify with the next-day paste-line in Phần 4.

{{% notice info %}}
**Cost figures are post-launch updated:** the `~$2-5 USD per 2-hour session` ballpark is a guideline (D-54). Per-service exact figures will be filled in by the instructor in Phần 5 Summary after pulling 24h Cost Explorer data from a real workshop session. AWS pricing changes periodically — bookmark `https://aws.amazon.com/bedrock/pricing/` for live numbers.
{{% /notice %}}

## Ready for Phần 3 Hands-on

You now have: account + model access + tools + credentials + cost expectation. What is next:

- **Phần 3.1** deploys the Bedrock Knowledge Base on S3 Vectors and verifies the Retrieve API.
- **Phần 3.2** runs the Pipecat agent locally so the `lookup_product` tool can call the KB you just deployed.
- **Phần 3.3, 3.4, 3.5** deploy onto AgentCore Runtime + web widget + observability.
