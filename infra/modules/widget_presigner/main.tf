// Widget presigner: anonymous public Function URL Lambda that mints
// short-lived SigV4-presigned WSS URLs for the AgentCore Runtime. The
// browser cannot SigV4-sign directly; this is the auth bridge the widget
// fetches before opening the WebSocket.
//
// Architecture per Plan 03-04 user-approved Rule-4 deviation:
// - Function URL AuthType=NONE (anonymous public) so the widget can fetch
//   without credentials.
// - Reserved concurrency = 5 caps blast-radius from a leaked URL or abuse.
// - CORS allow-origin restricted to the single CloudFront URL (NOT *).
// - IAM role grants ONLY bedrock-agentcore:InvokeAgentRuntime on the
//   specific runtime ARN; zero wildcards (D-13).
// - Trust policy uses aws:SourceAccount confused-deputy condition.
// - Presigned URL TTL <= 5 minutes (variable validation enforces).
//
// Chicken-and-egg: agentcore_runtime_arn comes from the CDK stack which
// deploys AFTER this Terraform module. The first apply may pass an empty
// string; the second-pass apply (after `cdk deploy`) wires the real ARN.
// The Lambda env var update on the second apply is in-place (no replace).

locals {
  function_name = "${var.name_prefix}-widget-presign-${var.env}"
  // The IAM policy must allow InvokeAgentRuntime even on a placeholder
  // ARN so terraform can apply before cdk deploy. Empty-string substitution
  // keeps the Resource list well-formed.
  invoke_resource = (var.agentcore_runtime_arn == ""
    ? "arn:aws:bedrock-agentcore:${var.region}:${var.account_id}:runtime/PLACEHOLDER"
    : var.agentcore_runtime_arn
  )
}

// --- Lambda execution role + trust ---
data "aws_iam_policy_document" "presign_trust" {
  statement {
    sid     = "LambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "presign" {
  name               = "${local.function_name}-exec"
  assume_role_policy = data.aws_iam_policy_document.presign_trust.json
}

// --- Inline policy: invoke the AgentCore runtime + write logs to its own log group ---
data "aws_iam_policy_document" "presign_inline" {
  statement {
    sid     = "InvokeAgentRuntime"
    effect  = "Allow"
    actions = ["bedrock-agentcore:InvokeAgentRuntime"]
    resources = [
      local.invoke_resource,
      "${local.invoke_resource}/*",
    ]
  }

  statement {
    sid    = "LambdaOwnLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.presign.arn,
      "${aws_cloudwatch_log_group.presign.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "presign_inline" {
  name   = "${local.function_name}-inline"
  role   = aws_iam_role.presign.id
  policy = data.aws_iam_policy_document.presign_inline.json
}

// --- Log group (explicit; lets us scope logs:* without /aws/lambda/* wildcard) ---
resource "aws_cloudwatch_log_group" "presign" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30
}

// --- Package the handler ---
data "archive_file" "presign" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/handler.zip"
}

// --- Lambda function ---
resource "aws_lambda_function" "presign" {
  function_name    = local.function_name
  role             = aws_iam_role.presign.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.presign.output_path
  source_code_hash = data.archive_file.presign.output_base64sha256
  timeout          = 5
  memory_size      = 256

  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      AGENTCORE_RUNTIME_ARN = var.agentcore_runtime_arn
      CORS_ALLOW_ORIGIN     = var.cors_allow_origin
      PRESIGN_TTL_SECONDS   = tostring(var.presign_ttl_seconds)
    }
  }

  depends_on = [
    aws_iam_role_policy.presign_inline,
    aws_cloudwatch_log_group.presign,
  ]
}

// --- Function URL: anonymous public (auth=NONE), CORS locked to CloudFront origin ---
resource "aws_lambda_function_url" "presign" {
  function_name      = aws_lambda_function.presign.function_name
  authorization_type = "NONE"

  cors {
    allow_origins     = [var.cors_allow_origin]
    allow_methods     = ["GET", "OPTIONS"]
    allow_headers     = ["content-type"]
    max_age           = 300
    allow_credentials = false
  }
}
