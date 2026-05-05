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
