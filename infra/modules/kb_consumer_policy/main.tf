# D-22: managed policy ONLY. Phase 2 ships, Phase 3 attaches to the AgentCore
# execution role. NOT attached to any role here — no aws_iam_role,
# no aws_iam_role_policy_attachment in this module.
#
# D-13 (carried from Phase 1): ZERO wildcards in Action or Resource. Single
# Action ("bedrock:Retrieve"), single Resource (the KB ARN passed in by the
# caller). The Resource is var.kb_arn — by contract this MUST be a fully
# qualified KB ARN (no "*"), enforced by the caller's input.

resource "aws_iam_policy" "kb_retrieve" {
  name        = var.name
  description = "Grants bedrock:Retrieve on the hera-kb. Phase 2 ships, Phase 3 attaches to the AgentCore execution role."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "RetrieveFromHeraKB"
      Effect   = "Allow"
      Action   = "bedrock:Retrieve"
      Resource = var.kb_arn
    }]
  })
}
