variable "name" {
  description = "ECR repository name. Default \"hera-agent\" matches the container image name (CONTEXT.md canonical_refs)."
  type        = string
  default     = "hera-agent"
}

variable "keep_last_n_untagged" {
  description = "Lifecycle policy: keep this many of the most recent untagged images. D-25 retention default."
  type        = number
  default     = 5
}
