output "role_arn" {
  description = "AgentCore execution role ARN. Plan 03-04 CDK stack binds this to the AgentCore Runtime resource."
  value       = aws_iam_role.agentcore_exec.arn
}

output "role_name" {
  description = "AgentCore execution role name. Useful for cross-tool diagnostics (aws iam list-attached-role-policies)."
  value       = aws_iam_role.agentcore_exec.name
}

output "log_group_arn" {
  description = "CloudWatch log group ARN. Plan 03-04 CDK stack passes this to AgentCore."
  value       = aws_cloudwatch_log_group.agentcore.arn
}

output "log_group_name" {
  description = "CloudWatch log group name (/aws/bedrock-agentcore/hera-agent)."
  value       = aws_cloudwatch_log_group.agentcore.name
}
