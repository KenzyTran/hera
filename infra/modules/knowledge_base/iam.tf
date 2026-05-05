data "aws_caller_identity" "current" {}

# --- KB service role trust policy ---
# Service principal is bedrock.amazonaws.com — see RESEARCH.md Pitfall I for the trap (the bedrock-agent service principal is NOT a valid trust target for KB roles).
# aws:SourceAccount + aws:SourceArn conditions defend against the cross-account "confused deputy" pattern.
data "aws_iam_policy_document" "kb_trust" {
  statement {
    sid     = "BedrockKBAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "kb_service_role" {
  name               = "${var.name_prefix}-kb-service-role"
  assume_role_policy = data.aws_iam_policy_document.kb_trust.json
}

# --- KB service role inline permissions policy ---
# Three statements; zero wildcards in Action or Resource (D-13). Every action enumerated.
data "aws_iam_policy_document" "kb_inline" {

  # 1. Read source markdown bucket
  statement {
    sid       = "S3SourceListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.source.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "S3SourceGetObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.source.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # 2. Invoke Titan v2 embedding model in this region (foundation-model ARN format omits account segment)
  statement {
    sid     = "BedrockInvokeTitanV2"
    effect  = "Allow"
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0"
    ]
  }

  # 3. Read/write the S3 Vectors index for this KB
  statement {
    sid    = "S3VectorsReadWrite"
    effect = "Allow"
    actions = [
      "s3vectors:PutVectors",
      "s3vectors:GetVectors",
      "s3vectors:DeleteVectors",
      "s3vectors:QueryVectors",
      "s3vectors:GetIndex",
    ]
    resources = [
      "arn:aws:s3vectors:${var.region}:${data.aws_caller_identity.current.account_id}:bucket/${aws_s3vectors_vector_bucket.this.vector_bucket_name}/index/${aws_s3vectors_index.this.index_name}"
    ]
  }
}

resource "aws_iam_role_policy" "kb_inline" {
  name   = "${var.name_prefix}-kb-inline"
  role   = aws_iam_role.kb_service_role.id
  policy = data.aws_iam_policy_document.kb_inline.json
}
