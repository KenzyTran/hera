output "bucket_name" {
  description = "S3 bucket holding the golden dataset + eval result outputs."
  value       = aws_s3_bucket.evals.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN."
  value       = aws_s3_bucket.evals.arn
}

output "dataset_s3_uri" {
  description = "S3 URI of the uploaded golden dataset."
  value       = "s3://${aws_s3_bucket.evals.bucket}/${aws_s3_object.golden_dataset.key}"
}

output "results_s3_uri_prefix" {
  description = "S3 URI prefix that eval jobs should write results under."
  value       = "s3://${aws_s3_bucket.evals.bucket}/results/"
}

output "eval_role_arn" {
  description = "IAM role ARN that bin/run-kb-eval.sh should pass via --role-arn."
  value       = aws_iam_role.eval.arn
}
