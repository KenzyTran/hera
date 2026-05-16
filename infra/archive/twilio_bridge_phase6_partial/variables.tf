variable "name_prefix" {
  description = "Resource name prefix. Default \"hera\" (project name)."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment suffix for resource names. \"prod\" yields hera-twilio-bridge-prod (D-12 fixed names)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region the AgentCore Runtime lives in. Used to construct the data-plane WSS host (bedrock-agentcore.<region>.amazonaws.com) inside the bridge container."
  type        = string
}

variable "account_id" {
  description = "AWS account ID for trust-policy aws:SourceAccount confused-deputy condition (Phase 1 + 3 carry-forward pattern)."
  type        = string
}

variable "agentcore_runtime_arn" {
  description = "Live AgentCore Runtime ARN. Bridge instance role scopes bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream to this EXACT ARN (D-13 zero wildcards, D-66)."
  type        = string
}

variable "twilio_auth_token_secret_arn" {
  description = "Secrets Manager ARN holding the Twilio Auth Token (D-67). Bridge instance role grants secretsmanager:GetSecretValue ONLY on this ARN. App Runner runtime_environment_secrets injects the token as TWILIO_AUTH_TOKEN. No token in plaintext IaC."
  type        = string
  sensitive   = true
}

variable "image_tag" {
  description = "Bridge container image tag (git short SHA). Empty string -> module substitutes public.ecr.aws/aws-containers/hello-app-runner:latest as a placeholder so the FIRST terraform apply succeeds before bin/push-bridge-image.sh lands a real image. Mirrors widget_presigner's agentcore_runtime_arn chicken-and-egg pattern (Pattern S10)."
  type        = string
  default     = ""
}

variable "cpu" {
  description = "App Runner instance vCPU. Bridge is a thin frame translator; 0.25 vCPU is sufficient."
  type        = string
  default     = "0.25 vCPU"
}

variable "memory" {
  description = "App Runner instance memory."
  type        = string
  default     = "0.5 GB"
}

variable "max_concurrency" {
  description = "Max concurrent requests per App Runner instance before scaling out. Bridge is one WS per phone call; 5 is generous given AgentCore upstream cap=2 (D-30) is the hard ceiling."
  type        = number
  default     = 5
}

variable "max_size" {
  description = "Max App Runner instance count. Capped at 2 to match AgentCore concurrency cap=2 (D-30/D-65) so the bridge cannot fan out beyond what AgentCore accepts."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Min App Runner instance count. App Runner ASC requires MinSize >= 1 (D-56 originally claimed 0 but the AWS provider rejects it). Scale-to-zero in App Runner is achieved by automatic scale-down to 0 *active* instances when idle while MinSize >= 1 provisioned instances remain at reduced cost (~$0.007/GB-hour for provisioned-only)."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the bridge log group."
  type        = number
  default     = 7
}

variable "keep_last_n_untagged" {
  description = "ECR lifecycle policy: keep last N untagged images. Mirrors infra/modules/ecr default."
  type        = number
  default     = 5
}
