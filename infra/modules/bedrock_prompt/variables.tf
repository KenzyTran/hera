variable "name_prefix" {
  description = "Prefix for prompt resource name."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment suffix (prod/dev)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region — used to build the Nova 2 Sonic model ARN."
  type        = string
  default     = "ap-northeast-1"
}

variable "sonic_model_id" {
  description = "Bedrock foundation model id for Nova 2 Sonic."
  type        = string
  default     = "amazon.nova-2-sonic-v1:0"
}

variable "system_prompt_path" {
  description = "Path (relative to repo root) of the source-of-truth system prompt file."
  type        = string
  default     = "agent/hera_agent/prompts.py"
}
