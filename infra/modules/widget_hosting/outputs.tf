output "s3_bucket_name" {
  description = "S3 bucket holding widget HTML/JS. Plan 03-04 deploy-widget.sh aws s3 sync target."
  value       = aws_s3_bucket.widget.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN."
  value       = aws_s3_bucket.widget.arn
}

output "cloudfront_domain" {
  description = "CloudFront default domain (e.g. d{12chars}.cloudfront.net)."
  value       = aws_cloudfront_distribution.widget.domain_name
}

output "cloudfront_url" {
  description = "Public widget URL on default *.cloudfront.net (DEM-01 success criterion)."
  value       = "https://${aws_cloudfront_distribution.widget.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID. Plan 03-04 deploy-widget.sh aws cloudfront create-invalidation --distribution-id target."
  value       = aws_cloudfront_distribution.widget.id
}
