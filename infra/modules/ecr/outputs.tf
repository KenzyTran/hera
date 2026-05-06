output "repository_url" {
  description = "ECR repository URL. Plan 03-03 build-push.sh: docker buildx build -t $${this}:$${git_sha}."
  value       = aws_ecr_repository.hera_agent.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN."
  value       = aws_ecr_repository.hera_agent.arn
}

output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.hera_agent.name
}
