output "kb_id" {
  description = "Bedrock Knowledge Base ID. Consumed by aws bedrock-agent start-ingestion-job (Plan 03) and by the Phase 2 Pipecat tool."
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "kb_arn" {
  description = "Bedrock Knowledge Base ARN. Used by Phase 2 to scope bedrock:Retrieve in the consumer role (D-10 deferred)."
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "source_bucket_name" {
  description = "S3 source bucket name. Use with: aws s3 cp catalog/*.md s3://<this>/catalog/"
  value       = aws_s3_bucket.source.bucket
}

output "data_source_id" {
  description = "Bedrock data source ID. Required for aws bedrock-agent start-ingestion-job."
  value       = aws_bedrockagent_data_source.catalog.data_source_id
}
