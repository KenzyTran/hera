variable "name_prefix" {
  description = "Resource name prefix. Default \"hera\" (project name)."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment suffix for resource names. \"prod\" yields hera-agentcore-exec-prod (D-12 fixed names)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region for the AgentCore Runtime resource ARN in the trust-policy ArnLike condition. No default — caller passes var.region from the prod root."
  type        = string
}

variable "account_id" {
  description = "AWS account ID for the trust-policy aws:SourceAccount condition. No default — caller passes data.aws_caller_identity.current.account_id from the prod root (avoids re-reading caller-identity inside the module)."
  type        = string
}

variable "kb_retrieve_policy_arn" {
  description = "ARN of the managed policy granting bedrock:Retrieve on the hera KB. Caller MUST pass module.kb_consumer_policy.policy_arn. Closes Phase 2 D-22 deferral when attached to the exec role."
  type        = string
}

variable "sonic_model_arn" {
  description = "Foundation-model ARN for Nova 2 Sonic bidi stream. Verified live 2026-05-16: amazon.nova-2-sonic-v1:0 is ACTIVE; amazon.nova-sonic-v1:0 is LEGACY. Pipecat 1.1.0 AWSNovaSonicLLMService defaults to nova-2-sonic-v1:0 so this IAM grant MUST match or the bidi stream invoke fails with AccessDenied (silent: AgentCore container logs are empty)."
  type        = string
  default     = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.nova-2-sonic-v1:0"
}
