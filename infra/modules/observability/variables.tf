variable "name_prefix" {
  description = "Resource name prefix. Default \"hera\" (project name)."
  type        = string
  default     = "hera"
}

variable "env" {
  description = "Environment suffix for resource names. \"prod\" yields hera-billing-prod (D-12 fixed names)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region for the dashboard + operational alarms. No default - caller passes var.region from the prod root. Billing alarm uses provider aws.us_east_1 regardless (AWS/Billing service constraint)."
  type        = string
}

variable "account_id" {
  description = "AWS account ID. Reserved for future use (e.g. dashboard widget ARN templates)."
  type        = string
}

variable "agentcore_log_group_name" {
  description = "CloudWatch log group name for the AgentCore Runtime (e.g. /aws/bedrock-agentcore/hera-agent). Reserved for log-based metric panels in a future iteration."
  type        = string
}

variable "agentcore_runtime_arn" {
  description = "Live AgentCore Runtime ARN. Used as the Resource dimension on AWS/Bedrock-AgentCore metric queries (Invocations, TotalErrors, Latency, ActiveStreamingConnections)."
  type        = string
}

variable "presigner_function_name" {
  description = "Lambda function name for the widget presigner. Reserved for an optional Lambda-metrics widget panel."
  type        = string
}

variable "cloudfront_distribution_id" {
  description = "CloudFront distribution id (widget hosting). Reserved for an optional 5xx-rate widget panel."
  type        = string
}

variable "billing_threshold_usd" {
  description = "Billing alarm threshold in USD per day (D-29 banner-copy hardcode). Default 5."
  type        = number
  default     = 5
}

variable "error_rate_threshold_pct" {
  description = "Error-rate alarm threshold in percent (OBS-02 verbatim). Default 5."
  type        = number
  default     = 5
}

variable "latency_p95_threshold_ms" {
  description = "Latency-p95 alarm threshold in milliseconds (OBS-02 verbatim). Default 5000."
  type        = number
  default     = 5000
}

variable "sonic_model_id" {
  description = "Bedrock Sonic model id used for the cost-proxy widget panel (token volume by ModelId). Default amazon.nova-sonic-v1:0."
  type        = string
  default     = "amazon.nova-sonic-v1:0"
}
