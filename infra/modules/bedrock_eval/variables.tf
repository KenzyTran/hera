variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment suffix."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region (must match the KB being evaluated)."
  type        = string
  default     = "ap-northeast-1"
}

variable "kb_arn" {
  description = "Bedrock Knowledge Base ARN under evaluation."
  type        = string
}

variable "dataset_path" {
  description = "Path (relative to repo root) of the golden dataset JSONL."
  type        = string
  default     = "evals/golden-dataset.jsonl"
}
