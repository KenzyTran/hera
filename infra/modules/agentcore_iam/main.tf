# AgentCore execution IAM role + inline bidi/logs/metrics policy + CloudWatch
# log group + KB consumer policy attachment.
#
# D-24: Terraform owns this module; CDK owns only the AgentCore Runtime
# resource that binds to this role.
# D-13: ZERO wildcards in any Action or Resource. The single documented
# exception is cloudwatch:PutMetricData where Resource = "*" is mandated by
# the AWS IAM model and is scoped via the cloudwatch:namespace condition.
# D-22 closes here: hera-kb-retrieve-prod attaches to the exec role below.
#
# Trust principal: bedrock-agentcore.amazonaws.com [needs-verification — Phase
# 1 Pitfall I mitigation]. If MalformedPolicyDocument is raised at apply time,
# fall back to bedrock.amazonaws.com and document the change in 03-01-SUMMARY.

# --- Trust policy (assume role) ---
data "aws_iam_policy_document" "agentcore_trust" {
  statement {
    sid     = "AgentCoreAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:bedrock-agentcore:${var.region}:${var.account_id}:runtime/*"]
    }
  }
}

resource "aws_iam_role" "agentcore_exec" {
  name               = "${var.name_prefix}-agentcore-exec-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.agentcore_trust.json
}

# --- CloudWatch log group for AgentCore stdout/stderr ---
# Name is the AWS-conventional /aws/bedrock-agentcore/<app> path.
# Phase 4 may revisit retention_in_days; 30 is the v1 default.
resource "aws_cloudwatch_log_group" "agentcore" {
  name              = "/aws/bedrock-agentcore/hera-agent"
  retention_in_days = 30
}

# --- Inline policy: Sonic bidi-stream + scoped CloudWatch logs/metrics + ECR pull ---
data "aws_iam_policy_document" "agentcore_inline" {

  statement {
    sid     = "BedrockSonicBidiStream"
    effect  = "Allow"
    actions = ["bedrock:InvokeModelWithBidirectionalStream"]
    # Both Nova Sonic v1 (LEGACY) and Nova 2 Sonic (ACTIVE) allowed.
    # Pipecat 1.1.0 default model is nova-2-sonic-v1:0; legacy nova-sonic-v1:0
    # used as a fallback when v2 loops on tool-result acknowledgment (bug
    # observed live 2026-05-16: Pipecat sends tool result via _send_tool_result
    # but Sonic v2 never acknowledges, retries function call ~1/s indefinitely).
    resources = [
      var.sonic_model_arn,
      replace(var.sonic_model_arn, "nova-2-sonic-v1:0", "nova-sonic-v1:0"),
    ]
  }

  # ECR pull for AgentCore container image. Required by AgentCore Runtime
  # CFn validation (CREATE_FAILED with "Access denied while validating ECR
  # URI" otherwise). GetAuthorizationToken has no resource-level scoping in
  # IAM (the API target is the registry, not a repository) so the AWS
  # least-privilege pattern is Resource=* with the action limited to the
  # token call alone; the actual layer/manifest reads ARE scoped to the
  # specific repo ARN. Same documented-exception pattern as the
  # cloudwatch:PutMetricData statement below.
  statement {
    sid       = "ECRGetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPullHeraAgent"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      "arn:aws:ecr:${var.region}:${var.account_id}:repository/hera-agent",
    ]
  }

  statement {
    sid    = "CloudWatchLogsScopedToAgentCoreGroup"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.agentcore.arn,
      "${aws_cloudwatch_log_group.agentcore.arn}:*",
    ]
  }

  # PutMetricData ONLY allows Resource = "*" per the AWS IAM model (the API
  # has no resource-level identifier). D-13's wildcard rule is satisfied by
  # scoping via the cloudwatch:namespace StringEquals condition: the role
  # can only publish into the hera/agentcore namespace. This is the
  # AWS-published least-privilege pattern for CloudWatch metrics.
  statement {
    sid       = "CloudWatchEMFMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["hera/agentcore"]
    }
  }
}

resource "aws_iam_role_policy" "agentcore_inline" {
  name   = "${var.name_prefix}-agentcore-exec-inline"
  role   = aws_iam_role.agentcore_exec.id
  policy = data.aws_iam_policy_document.agentcore_inline.json
}

# Closes Phase 2 D-22: hera-kb-retrieve-prod attaches to the AgentCore exec
# role here. Phase-N IAM ships, Phase-N+1 attaches (RESEARCH P7).
resource "aws_iam_role_policy_attachment" "kb_retrieve" {
  role       = aws_iam_role.agentcore_exec.name
  policy_arn = var.kb_retrieve_policy_arn
}
