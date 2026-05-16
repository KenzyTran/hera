provider "aws" {
  region = var.region
}

# Second alias for the cross-region billing alarm in infra/modules/observability.
# AWS/Billing EstimatedCharges is only published in us-east-1; the alarm
# resource has provider = aws.us_east_1 so it lands in the right region.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# awscc provider -- defaults to var.region; us_east_1 alias for Phase 6.1
# Connect / Lex resources. Required because hashicorp/aws lacks
# aws_lexv2models_bot_alias (gh#35780) and aws_connect_bot_association is
# V1 only (gh#30869); awscc fills both gaps per D-68 addendum.
provider "awscc" {
  region = var.region
}

provider "awscc" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Caller identity for confused-deputy conditions in agentcore_iam.
data "aws_caller_identity" "current" {}

module "knowledge_base" {
  source = "../../modules/knowledge_base"

  name_prefix = var.name_prefix
  env         = var.env
  region      = var.region
}

module "kb_consumer_policy" {
  source = "../../modules/kb_consumer_policy"

  kb_arn = module.knowledge_base.kb_arn
}

module "ecr" {
  source = "../../modules/ecr"
  # name and keep_last_n_untagged use module defaults (hera-agent, 5).
}

module "widget_hosting" {
  source = "../../modules/widget_hosting"
  # bucket_name uses default hera-widget-prod (D-12 fixed name).
}

module "agentcore_iam" {
  source = "../../modules/agentcore_iam"

  region                 = var.region
  account_id             = data.aws_caller_identity.current.account_id
  kb_retrieve_policy_arn = module.kb_consumer_policy.policy_arn
  # name_prefix and env use module defaults; sonic_model_arn uses module default
  # (overrideable when the verified Nova 2 Sonic model id is confirmed).
}

# Widget presigner Lambda (Plan 03-04 Rule-4 deviation). The browser cannot
# SigV4-sign a WebSocket directly, so the widget fetches a short-lived
# presigned URL from this Function URL before opening the AgentCore wss://
# connection. agentcore_runtime_arn comes from the CDK stack via
# `terraform apply -var=agentcore_runtime_arn=<arn>` AFTER `cdk deploy`.
module "widget_presigner" {
  source = "../../modules/widget_presigner"

  region                = var.region
  account_id            = data.aws_caller_identity.current.account_id
  agentcore_runtime_arn = var.agentcore_runtime_arn
  cors_allow_origin     = module.widget_hosting.cloudfront_url
}

# Observability: CloudWatch dashboard + 2 operational alarms (ap-northeast-1)
# + 1 billing alarm (us-east-1, AWS/Billing service constraint). Zero new
# IAM (D-13). Wires existing module outputs as live ARNs / IDs.
module "observability" {
  source = "../../modules/observability"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  region                     = var.region
  account_id                 = data.aws_caller_identity.current.account_id
  agentcore_log_group_name   = module.agentcore_iam.log_group_name
  agentcore_runtime_arn      = var.agentcore_runtime_arn
  presigner_function_name    = module.widget_presigner.function_name
  cloudfront_distribution_id = module.widget_hosting.cloudfront_distribution_id
  # billing_threshold_usd / error_rate_threshold_pct / latency_p95_threshold_ms / sonic_model_id all use module defaults
}

# Phase 6.1: Native AWS Voice Channel -- Amazon Connect.
# New module ships Connect instance + 1 US DID + Lex V2 bot (6-resource
# layout per D-68 addendum: aws + awscc providers) + Lookup Lambda + Contact
# Flow. All resources in us-east-1 (Connect free tier region). KB stays in
# ap-northeast-1; Lambda boto3-client region-overrides for cross-region
# Retrieve. D-70: reuses module.kb_consumer_policy.policy_arn (no new KB IAM).
# D-64: v1 surfaces (agent / cdk / kb_* / agentcore_iam / ecr / widget_* /
# observability / frontend / bin/cleanup-verify.sh / bin/push-image.sh) are
# untouched.
module "aws_voice_channel" {
  source = "../../modules/aws_voice_channel"

  providers = {
    aws.us_east_1   = aws.us_east_1
    awscc.us_east_1 = awscc.us_east_1
  }

  account_id             = data.aws_caller_identity.current.account_id
  kb_retrieve_policy_arn = module.kb_consumer_policy.policy_arn
  # name_prefix / env / kb_id / kb_region use module defaults
  # (hera / prod / BKXE19AH89 / ap-northeast-1).
}
