# Lookup Lambda: Lex V2 fulfillment hook for FallbackIntent.
# Mirrors infra/modules/widget_presigner/ packaging shape (archive_file +
# python3.13 + handler-only zip). D-70: role attaches existing managed
# policy hera-kb-retrieve-prod (no new KB IAM). D-13: zero wildcards;
# logs scoped to own log group ARN.

locals {
  function_name = "${var.name_prefix}-voice-lookup-${var.env}"
  role_name     = "${var.name_prefix}-voice-lookup-lambda-${var.env}"
  log_group     = "/aws/lambda/${var.name_prefix}-voice-lookup-${var.env}"
}

# --- Lambda execution role + trust (Pitfall 3-equivalent: confused-deputy) ---
data "aws_iam_policy_document" "lambda_trust" {
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

resource "aws_iam_role" "lookup" {
  provider = aws.us_east_1

  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

# --- CloudWatch log group: scoped log-write target. 30-day retention matches v1. ---
resource "aws_cloudwatch_log_group" "lookup" {
  provider = aws.us_east_1

  name              = local.log_group
  retention_in_days = 30
}

# --- Inline policy: own log group writes ONLY (zero wildcards on Resource). ---
data "aws_iam_policy_document" "lookup_inline" {
  statement {
    sid    = "OwnLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.lookup.arn,
      "${aws_cloudwatch_log_group.lookup.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "lookup_inline" {
  provider = aws.us_east_1

  name   = "${local.role_name}-inline"
  role   = aws_iam_role.lookup.id
  policy = data.aws_iam_policy_document.lookup_inline.json
}

# --- D-70: attach the existing Phase-2 managed KB consumer policy.
# Account-scoped IAM means us-east-1 Lambda -> ap-northeast-1 KB works
# natively. NO new bedrock:Retrieve policy in this module.
resource "aws_iam_role_policy_attachment" "lookup_kb" {
  provider = aws.us_east_1

  role       = aws_iam_role.lookup.name
  policy_arn = var.kb_retrieve_policy_arn
}

# --- Package the handler (zip; Lambda runtime provides boto3) ---
data "archive_file" "lookup" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/handler.zip"
}

# --- Lambda function (Python 3.13 — RESEARCH A5 latest stable) ---
resource "aws_lambda_function" "lookup" {
  provider = aws.us_east_1

  function_name    = local.function_name
  role             = aws_iam_role.lookup.arn
  runtime          = "python3.13"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lookup.output_path
  source_code_hash = data.archive_file.lookup.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      KB_ID       = var.kb_id
      KB_REGION   = var.kb_region
      NUM_RESULTS = "3"
    }
  }

  depends_on = [
    aws_iam_role_policy.lookup_inline,
    aws_iam_role_policy_attachment.lookup_kb,
    aws_cloudwatch_log_group.lookup,
  ]
}

# --- Permits Lex V2 to invoke the Lambda. SourceArn scoped to bot aliases of
# the specific Lex bot (constructed pattern `bot-alias/{BotId}/*` per
# docs.aws.amazon.com/lexv2/latest/dg/lambda-attach.html). Cannot reference
# awscc_lex_bot_alias.prod.arn directly because the alias has
# depends_on = [aws_lambda_permission.lex_invoke] (Pitfall 2 mitigation) and
# that would create a Terraform cycle. The bot only ever has the single
# `prod` alias, so the practical security posture is identical to
# alias-scoped (T-06.1-02-01).
resource "aws_lambda_permission" "lex_invoke" {
  provider = aws.us_east_1

  statement_id  = "AllowLexV2Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lookup.function_name
  principal     = "lexv2.amazonaws.com"
  source_arn    = "arn:aws:lex:us-east-1:${var.account_id}:bot-alias/${aws_lexv2models_bot.product_lookup.id}/*"
}
