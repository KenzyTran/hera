# IAM for the Hera Twilio Bridge App Runner service (Phase 6 — D-66 REVISED).
#
# Two roles per App Runner shape:
#   1. instance role  - assumed by tasks.apprunner.amazonaws.com; the
#      bridge container's runtime AWS identity. Grants:
#        - bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream on the
#          EXACT live runtime ARN (D-66, D-13 zero wildcards).
#        - secretsmanager:GetSecretValue on the EXACT Twilio auth-token
#          secret ARN (D-67).
#        - logs:CreateLogStream + PutLogEvents on its own log group only.
#   2. access role    - assumed by build.apprunner.amazonaws.com; lets
#      App Runner pull the bridge image from ECR. Grants:
#        - ecr:GetAuthorizationToken on Resource=* (AWS IAM mandate; same
#          documented exception used in agentcore_iam).
#        - ecr:BatchCheckLayerAvailability + BatchGetImage +
#          GetDownloadUrlForLayer on the EXACT bridge ECR repo ARN.
#
# Both trust policies enforce aws:SourceAccount=<account_id> confused-deputy
# condition (Pattern S1).

locals {
  service_name       = "${var.name_prefix}-twilio-bridge-${var.env}"
  asc_name           = "${var.name_prefix}-twilio-bridge-asc-${var.env}"
  log_group_name     = "/aws/apprunner/${local.service_name}"
  instance_role_name = "${var.name_prefix}-twilio-bridge-instance-${var.env}"
  access_role_name   = "${var.name_prefix}-twilio-bridge-access-${var.env}"
}

# --- instance role trust ---
data "aws_iam_policy_document" "bridge_instance_trust" {
  statement {
    sid     = "AppRunnerInstanceAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["tasks.apprunner.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "bridge_instance" {
  name               = local.instance_role_name
  assume_role_policy = data.aws_iam_policy_document.bridge_instance_trust.json
}

# --- instance role inline policy: zero wildcards (D-13/D-66) ---
data "aws_iam_policy_document" "bridge_instance_inline" {
  statement {
    sid    = "InvokeAgentRuntimeWebSocketStream"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream",
    ]
    resources = [
      var.agentcore_runtime_arn,
      "${var.agentcore_runtime_arn}/*",
    ]
  }

  statement {
    sid    = "ReadTwilioAuthToken"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      var.twilio_auth_token_secret_arn,
    ]
  }

  statement {
    sid    = "BridgeOwnLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.bridge.arn,
      "${aws_cloudwatch_log_group.bridge.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "bridge_instance_inline" {
  name   = "${local.instance_role_name}-inline"
  role   = aws_iam_role.bridge_instance.id
  policy = data.aws_iam_policy_document.bridge_instance_inline.json
}

# --- access role trust ---
data "aws_iam_policy_document" "bridge_access_trust" {
  statement {
    sid     = "AppRunnerEcrAccessAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["build.apprunner.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "bridge_access" {
  name               = local.access_role_name
  assume_role_policy = data.aws_iam_policy_document.bridge_access_trust.json
}

# --- access role inline policy: ECR pull on the EXACT bridge repo ARN ---
# ecr:GetAuthorizationToken requires Resource = "*" by AWS IAM model
# (no resource-level scoping for the registry-wide auth token endpoint).
# Same documented exception accepted in infra/modules/agentcore_iam/main.tf.
data "aws_iam_policy_document" "bridge_access_inline" {
  statement {
    sid       = "ECRGetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPullBridge"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      aws_ecr_repository.bridge.arn,
    ]
  }
}

resource "aws_iam_role_policy" "bridge_access_inline" {
  name   = "${local.access_role_name}-inline"
  role   = aws_iam_role.bridge_access.id
  policy = data.aws_iam_policy_document.bridge_access_inline.json
}

# --- own log group (Pattern S3) ---
resource "aws_cloudwatch_log_group" "bridge" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
}
