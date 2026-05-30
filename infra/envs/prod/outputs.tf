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

output "ecr_repo_url" {
  description = "ECR repository URL. Plan 03-03 build-push.sh consumes for docker buildx push."
  value       = module.ecr.repository_url
}

output "agentcore_exec_role_arn" {
  description = "AgentCore execution role ARN. Plan 03-04 CDK stack reads this and binds it to the AgentCore Runtime resource."
  value       = module.agentcore_iam.role_arn
}

output "agentcore_exec_role_name" {
  description = "Role name. Useful for cross-tool diagnostics (aws iam list-attached-role-policies)."
  value       = module.agentcore_iam.role_name
}

output "agentcore_log_group_arn" {
  description = "CloudWatch log group ARN. Plan 03-04 CDK stack passes this to AgentCore."
  value       = module.agentcore_iam.log_group_arn
}

output "agentcore_log_group_name" {
  description = "CloudWatch log group name (/aws/bedrock-agentcore/hera-agent)."
  value       = module.agentcore_iam.log_group_name
}

output "widget_cloudfront_url" {
  description = "Public widget URL on default *.cloudfront.net (DEM-01)."
  value       = module.widget_hosting.cloudfront_url
}

output "widget_s3_bucket_name" {
  description = "S3 bucket holding widget HTML/JS. Plan 03-04 deploy-widget.sh aws s3 sync target."
  value       = module.widget_hosting.s3_bucket_name
}

output "widget_cloudfront_distribution_id" {
  description = "CloudFront distribution ID. Plan 03-04 deploy-widget.sh aws cloudfront create-invalidation --distribution-id target."
  value       = module.widget_hosting.cloudfront_distribution_id
}

output "presign_url" {
  description = "Public Lambda Function URL the widget fetches to mint a SigV4-presigned WSS URL for the AgentCore Runtime (Plan 03-04 Rule-4 deviation). Browser fetches this anonymously over HTTPS; response is {\"url\": \"wss://...\"} valid for 5 min. bin/build-widget.sh sed-injects this into __PRESIGN_URL__."
  value       = module.widget_presigner.presign_url
}

output "observability_dashboard_url" {
  description = "AWS console URL for the Phase 4 CloudWatch dashboard. RUNBOOK Phase 4 dashboard walkthrough section embeds this."
  value       = module.observability.dashboard_url
}

output "observability_billing_alarm_arn" {
  description = "us-east-1 billing alarm ARN ($5/day cap, D-29). Phase 5 workshop content references for screenshot."
  value       = module.observability.billing_alarm_arn
}

# --- Bedrock Prompt Management ---

output "prompt_arn" {
  description = "ARN of the Bedrock Prompt Management resource storing the system prompt."
  value       = module.bedrock_prompt.prompt_arn
}

output "prompt_id" {
  description = "Bedrock prompt id (for console deep-link)."
  value       = module.bedrock_prompt.prompt_id
}

output "prompt_text_hash" {
  description = "SHA256 of the prompt text. Bumps on each prompt edit; correlates with the immutable version published by the local-exec snapshot."
  value       = module.bedrock_prompt.prompt_text_hash
}

# --- Bedrock KB Evaluation infra (consumed by bin/run-kb-eval.sh) ---

output "eval_dataset_s3_uri" {
  description = "S3 URI of the uploaded golden dataset JSONL."
  value       = module.bedrock_eval.dataset_s3_uri
}

output "eval_results_s3_uri_prefix" {
  description = "S3 URI prefix that evaluation jobs write results under."
  value       = module.bedrock_eval.results_s3_uri_prefix
}

output "eval_role_arn" {
  description = "IAM role ARN that Bedrock evaluation jobs assume."
  value       = module.bedrock_eval.eval_role_arn
}

output "eval_bucket_name" {
  description = "S3 bucket holding the dataset + eval results."
  value       = module.bedrock_eval.bucket_name
}
