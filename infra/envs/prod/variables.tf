variable "region" {
  description = "AWS region for prod deployment. Default ap-northeast-1; override to us-east-1 for dev (DEP-06)."
  type        = string
  default     = "ap-northeast-1"
}

variable "env" {
  description = "Environment suffix for resource names. \"prod\" yields hera-kb-prod (D-12 fixed names)."
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "Resource name prefix. Default \"hera\" (project name)."
  type        = string
  default     = "hera"
}

variable "agentcore_runtime_arn" {
  description = "AgentCore Runtime ARN emitted by `cdk deploy hera-agentcore` (dist/cdk-outputs.json -> hera-agentcore.AgentCoreRuntimeArn). Pass empty string for the FIRST terraform apply (the IAM policy gets a placeholder ARN); pass the real ARN for the SECOND-PASS apply that wires the widget_presigner Lambda. RUNBOOK Phase 3 documents the 4-step lifecycle: terraform apply (Wave 1) -> push-image -> cdk deploy -> terraform apply -var=agentcore_runtime_arn=<arn> -> build-widget -> smoke."
  type        = string
  default     = ""
}

variable "twilio_auth_token_secret_arn" {
  description = "Secrets Manager ARN holding the Twilio Auth Token (D-67). Operator pre-creates the secret + pastes the token via console; the bridge instance role grants secretsmanager:GetSecretValue ONLY on this ARN. No token in plaintext IaC. Pass via TF_VAR_twilio_auth_token_secret_arn or terraform.tfvars; terraform.tfvars MUST NOT be committed."
  type        = string
  sensitive   = true
  default     = ""
}

variable "twilio_bridge_image_tag" {
  description = "Bridge container image tag (git short SHA). Empty string for the FIRST `terraform apply` (App Runner uses public.ecr.aws/aws-containers/hello-app-runner:latest as a placeholder); pass the real SHA for the second-pass apply after `bin/push-bridge-image.sh` lands the image. Mirrors agentcore_runtime_arn chicken-and-egg pattern from Phase 3."
  type        = string
  default     = ""
}
