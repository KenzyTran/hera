output "connect_instance_arn" {
  description = "Amazon Connect instance ARN. Acceptance for AWS-NAT-01."
  value       = aws_connect_instance.hera.arn
}

output "connect_instance_id" {
  description = "Amazon Connect instance ID. Used by RUNBOOK paste-flow for CCP login URL."
  value       = aws_connect_instance.hera.id
}

output "connect_phone_number" {
  description = "Claimed US DID. RUNBOOK paste-flow displays this for operator to dial."
  value       = aws_connect_phone_number.us_did.phone_number
}

output "lex_bot_alias_arn" {
  description = "Lex V2 bot alias ARN. Wired into Contact Flow JSON template + referenced for Lex resource-based policy."
  value       = awscc_lex_bot_alias.prod.arn
}

output "voice_lookup_lambda_arn" {
  description = "Lookup Lambda ARN. RUNBOOK paste-flow uses for synthetic invoke (AWS-NAT-03 acceptance)."
  value       = aws_lambda_function.lookup.arn
}

output "voice_lookup_lambda_name" {
  description = "Lookup Lambda function name. CloudWatch logs path: /aws/lambda/<this>."
  value       = aws_lambda_function.lookup.function_name
}

output "contact_flow_id" {
  description = "Contact Flow ID. AWS-NAT-04 acceptance via aws connect describe-contact-flow --contact-flow-id <this>."
  value       = aws_connect_contact_flow.hera_voice.contact_flow_id
}
