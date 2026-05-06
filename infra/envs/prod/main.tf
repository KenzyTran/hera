provider "aws" {
  region = var.region
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
