output "presign_url" {
  description = "Public Lambda Function URL the widget fetches to mint a presigned WSS URL. https://....lambda-url.<region>.on.aws/"
  value       = aws_lambda_function_url.presign.function_url
}

output "function_name" {
  description = "Lambda function name (useful for cross-tool diagnostics: aws lambda get-function ...)."
  value       = aws_lambda_function.presign.function_name
}

output "function_arn" {
  description = "Lambda function ARN."
  value       = aws_lambda_function.presign.arn
}

output "role_arn" {
  description = "Lambda execution role ARN."
  value       = aws_iam_role.presign.arn
}
