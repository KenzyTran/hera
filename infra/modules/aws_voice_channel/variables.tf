variable "account_id" {
  description = "AWS account ID (851725411875 for prod). Used in confused-deputy conditions on Lambda trust policy + Lex resource-based policy."
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix. Default \"hera\" (matches D-12 fixed names hera-voice-prod / hera-product-lookup-prod / hera-voice-lookup-prod / hera-voice-flow-prod)."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment suffix. Default \"prod\"."
  type        = string
  default     = "prod"
}

variable "kb_retrieve_policy_arn" {
  description = "ARN of the existing hera-kb-retrieve-prod managed policy (Phase 2 module.kb_consumer_policy.policy_arn). D-70 — Lambda role attaches this; no new KB IAM created."
  type        = string
}

variable "kb_id" {
  description = "Bedrock Knowledge Base ID for cross-region Retrieve. Default BKXE19AH89 (Phase 1 live KB in ap-northeast-1)."
  type        = string
  default     = "BKXE19AH89"
}

variable "kb_region" {
  description = "AWS region where the Bedrock KB lives. Default ap-northeast-1 (Phase 1 D-14)."
  type        = string
  default     = "ap-northeast-1"
}
