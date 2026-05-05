output "policy_arn" {
  description = "Managed policy ARN. Phase 3 attaches to the AgentCore execution role with aws_iam_role_policy_attachment."
  value       = aws_iam_policy.kb_retrieve.arn
}
