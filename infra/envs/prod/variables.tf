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

variable "agentcore_runtime_arn" {
  description = "AgentCore Runtime ARN emitted by `cdk deploy hera-agentcore` (dist/cdk-outputs.json -> hera-agentcore.AgentCoreRuntimeArn). Pass empty string for the FIRST terraform apply (the IAM policy gets a placeholder ARN); pass the real ARN for the SECOND-PASS apply that wires the widget_presigner Lambda. RUNBOOK Phase 3 documents the 4-step lifecycle: terraform apply (Wave 1) -> push-image -> cdk deploy -> terraform apply -var=agentcore_runtime_arn=<arn> -> build-widget -> smoke."
  type        = string
  default     = ""
}
