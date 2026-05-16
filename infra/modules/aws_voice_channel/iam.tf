# Lex V2 service role — the IAM role Lex assumes to read its own model + invoke
# the bot. Zero-wildcard inline policy is not strictly required (Lex service
# role lifecycle is AWS-managed), but the trust policy MUST include the
# confused-deputy condition (D-13 carry-forward + Pitfall 3-equivalent).

data "aws_iam_policy_document" "lex_service_trust" {
  statement {
    sid     = "LexV2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lexv2.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "lex_service" {
  provider = aws.us_east_1

  name               = "${var.name_prefix}-lex-service-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.lex_service_trust.json
}
