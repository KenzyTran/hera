output "kb_id" {
  description = "Bedrock Knowledge Base ID."
  value       = module.knowledge_base.kb_id
}

output "kb_arn" {
  description = "Bedrock Knowledge Base ARN. Consumed by Phase 2 to scope the consumer Pipecat role (D-10 deferred)."
  value       = module.knowledge_base.kb_arn
}

output "source_bucket_name" {
  description = "S3 source bucket name. Use with: aws s3 cp catalog/*.md s3://$(this)/catalog/"
  value       = module.knowledge_base.source_bucket_name
}

output "data_source_id" {
  description = "Bedrock data source ID. Required by aws bedrock-agent start-ingestion-job."
  value       = module.knowledge_base.data_source_id
}

output "kb_retrieve_policy_arn" {
  description = "Managed policy ARN for bedrock:Retrieve scoped to the hera KB. Phase 3 attaches this to the AgentCore execution role with aws_iam_role_policy_attachment."
  value       = module.kb_consumer_policy.policy_arn
}
