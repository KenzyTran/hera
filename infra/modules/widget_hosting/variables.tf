variable "name_prefix" {
  description = "Resource name prefix. Default \"hera\" (project name)."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment suffix. \"prod\" yields hera-widget-prod (D-12 fixed names)."
  type        = string
  default     = "prod"
}

variable "bucket_name" {
  description = "S3 bucket name for the widget HTML/JS. D-12 fixed name from CONTEXT.md canonical_refs."
  type        = string
  default     = "hera-widget-prod"
}

variable "comment" {
  description = "CloudFront distribution comment for AWS console clarity."
  type        = string
  default     = "hera widget instructor demo"
}
