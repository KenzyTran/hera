variable "kb_arn" {
  description = "Bedrock KB ARN to scope bedrock:Retrieve to. Caller MUST pass module.knowledge_base.kb_arn explicitly. No default — passing a wildcard or hardcoded ARN here would violate D-13 (zero wildcards) or D-22 (Phase-1 sourced ARN)."
  type        = string
  # no default — caller must pass module.knowledge_base.kb_arn
}

variable "name" {
  description = "Managed policy name. Default 'hera-kb-retrieve-prod' per D-22. Override only for dev environments where the prod name would collide."
  type        = string
  default     = "hera-kb-retrieve-prod"
}
