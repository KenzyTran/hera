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
  description = "Foundation-model ARN for Nova Sonic bidi stream. NOTE [needs-verification]: confirm via `aws bedrock list-foundation-models --by-output-modality SPEECH --region ap-northeast-1` at apply time that this is the correct model id for Nova 2 Sonic. The default is the placeholder shape; override at the root if the verified id differs. Sonic v1 is EOL per PROJECT.md so the workshop uses 'Nova 2 Sonic' which Bedrock surfaces under model id `amazon.nova-sonic-v1:0` until renamed (research note)."
  type        = string
  default     = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.nova-sonic-v1:0"
}
