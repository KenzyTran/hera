output "service_url" {
  description = "App Runner service public hostname (https://...). Root output rewrites to wss://...<host>/twilio for Twilio TwiML Bin paste."
  value       = aws_apprunner_service.bridge.service_url
}

output "service_arn" {
  description = "App Runner service ARN. cleanup-verify-twilio.sh asserts this is gone after destroy."
  value       = aws_apprunner_service.bridge.arn
}

output "ecr_repository_url" {
  description = "Bridge ECR repository URL. bin/push-bridge-image.sh consumes for docker buildx push."
  value       = aws_ecr_repository.bridge.repository_url
}

output "ecr_repository_arn" {
  description = "Bridge ECR repository ARN. cleanup-verify-twilio.sh references for the gone-check; access role inline policy scopes ECR pulls to this ARN."
  value       = aws_ecr_repository.bridge.arn
}

output "instance_role_arn" {
  description = "Bridge App Runner instance role ARN. Granted secretsmanager:GetSecretValue + bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream + own log writes."
  value       = aws_iam_role.bridge_instance.arn
}

output "log_group_name" {
  description = "CloudWatch log group /aws/apprunner/hera-twilio-bridge-prod. cleanup-verify-twilio.sh asserts gone via describe-log-groups --log-group-name-prefix."
  value       = aws_cloudwatch_log_group.bridge.name
}
