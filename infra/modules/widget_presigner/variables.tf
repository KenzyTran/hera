variable "name_prefix" {
  description = "Resource name prefix. Default \"hera\" (project name)."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment suffix for resource names. \"prod\" yields hera-widget-presign-prod (D-12 fixed names)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region the AgentCore Runtime lives in. Used to construct the data-plane WSS host (bedrock-agentcore.<region>.amazonaws.com)."
  type        = string
}

variable "account_id" {
  description = "AWS account ID for trust-policy aws:SourceAccount confused-deputy condition."
  type        = string
}

variable "agentcore_runtime_arn" {
  description = "AgentCore Runtime ARN (CDK output). The Lambda needs this to (a) scope its IAM policy to bedrock-agentcore:InvokeAgentRuntime on the exact ARN and (b) URL-encode it into the WSS path. Pass an empty string for the initial terraform apply BEFORE cdk deploy exists; pass the real ARN for the second-pass apply that wires the presigner."
  type        = string
}

variable "cors_allow_origin" {
  description = "Single origin allowed by the Function URL CORS config. v1 = the CloudFront URL hosting the widget. Must NOT be '*' per Plan 03-04 critical_constraints."
  type        = string
}

variable "presign_ttl_seconds" {
  description = "TTL of the presigned URL in seconds. Plan 03-04 critical_constraints: <= 300 (5 minutes)."
  type        = number
  default     = 300

  validation {
    condition     = var.presign_ttl_seconds > 0 && var.presign_ttl_seconds <= 300
    error_message = "presign_ttl_seconds must be > 0 and <= 300 (5 minutes)."
  }
}

variable "reserved_concurrent_executions" {
  description = "Lambda reserved concurrency cap. v1 = 5 for blast-radius bounding (anonymous public Function URL has no auth)."
  type        = number
  default     = 5
}
