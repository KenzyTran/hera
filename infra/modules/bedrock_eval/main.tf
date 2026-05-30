# Bedrock KB Evaluation — infra prerequisites for `bin/run-kb-eval.sh`.
#
# Provides:
#   - S3 bucket for dataset uploads + evaluation result outputs
#   - IAM service role that Bedrock assumes to read dataset / KB and write results
#   - Auto-upload of the golden dataset on `terraform apply`
#
# The eval JOB itself is NOT a Terraform resource because it is intentionally
# imperative — operators trigger runs on demand (post-deploy, post-prompt-change)
# via `bin/run-kb-eval.sh`. Treating evaluation as imperative also keeps the
# state file clean of long-lived job ARNs that complete-then-stale.

# --- S3 bucket: holds golden dataset + eval result outputs ---
resource "aws_s3_bucket" "evals" {
  bucket        = "${var.name_prefix}-evals-${var.env}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "evals" {
  bucket = aws_s3_bucket.evals.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload the golden dataset. etag forces re-upload whenever the file changes.
resource "aws_s3_object" "golden_dataset" {
  bucket = aws_s3_bucket.evals.id
  key    = "datasets/golden-dataset.jsonl"
  source = "${path.root}/../../../${var.dataset_path}"
  etag   = filemd5("${path.root}/../../../${var.dataset_path}")

  content_type = "application/jsonl"
}

# --- IAM service role for Bedrock evaluation jobs ---
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "eval_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    # Confused-deputy: only OUR account can prompt Bedrock to assume this role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "eval" {
  name               = "${var.name_prefix}-bedrock-eval-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.eval_trust.json
}

# Permissions the service needs while running an evaluation job:
#  - Read the dataset + write results under the evals S3 bucket
#  - Retrieve from the KB under evaluation (and retrieve-and-generate)
#  - Invoke the generator model used for RAG eval (Nova / Claude on Bedrock)
data "aws_iam_policy_document" "eval_inline" {
  statement {
    sid    = "S3DatasetAndResults"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.evals.arn,
      "${aws_s3_bucket.evals.arn}/*",
    ]
  }

  statement {
    sid       = "BedrockKBRetrieve"
    effect    = "Allow"
    actions   = ["bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
    resources = [var.kb_arn]
  }

  statement {
    sid    = "BedrockInvokeGeneratorModel"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    # Generator + judge models. Scoped to foundation-model ARNs only.
    resources = [
      "arn:aws:bedrock:${var.region}::foundation-model/*",
      "arn:aws:bedrock:us-east-1::foundation-model/*",
      "arn:aws:bedrock:us-west-2::foundation-model/*",
    ]
  }
}

resource "aws_iam_role_policy" "eval_inline" {
  name   = "${var.name_prefix}-bedrock-eval-inline-${var.env}"
  role   = aws_iam_role.eval.id
  policy = data.aws_iam_policy_document.eval_inline.json
}
