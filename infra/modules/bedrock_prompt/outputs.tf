output "prompt_arn" {
  description = "ARN of the Bedrock Prompt Management resource."
  value       = aws_bedrockagent_prompt.hera_system.arn
}

output "prompt_id" {
  description = "Bedrock prompt id."
  value       = aws_bedrockagent_prompt.hera_system.id
}

output "prompt_name" {
  description = "Display name of the prompt."
  value       = aws_bedrockagent_prompt.hera_system.name
}

output "prompt_text_hash" {
  description = "SHA256 of the prompt text. Bumps whenever a new immutable version is published via the local-exec snapshot."
  value       = sha256(local.system_prompt)
}
