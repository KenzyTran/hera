variable "name_prefix" {
  description = "Prefix for all named resources (e.g. \"hera\" -> hera-kb-prod, hera-kb-source-prod, hera-kb-vectors-prod). Fixed names per D-12; no random suffix."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment name suffix (e.g. \"prod\" -> hera-kb-prod). Phase 1 only ships prod; dev environment is added in Phase 2 if needed."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region for ARN constructions (embedding_model_arn, S3 Vectors index ARN, IAM scope). Inherits from provider config; passed in for ARN string interpolation only. Default ap-northeast-1 per CLAUDE.md and DEP-06."
  type        = string
  default     = "ap-northeast-1"
}

variable "embedding_dimension" {
  description = "Vector dimension. MUST match the embedding model. 1024 is Titan v2 default. WARNING: S3 Vectors index dimension is IMMUTABLE post-create; changing this requires destroy+recreate of aws_s3vectors_index AND aws_bedrockagent_knowledge_base (Pitfall B / project Pitfall #8)."
  type        = number
  default     = 1024
}

variable "chunk_max_tokens" {
  description = "FIXED_SIZE chunking max tokens per chunk (D-04)."
  type        = number
  default     = 300
}

variable "chunk_overlap_pct" {
  description = "FIXED_SIZE chunking overlap percentage between adjacent chunks (D-04)."
  type        = number
  default     = 20
}
