# Widget hosting: private S3 bucket + CloudFront distribution with Origin
# Access Control. CloudFront is the only allowed reader; bucket itself blocks
# public access at all four account-level flags.
#
# D-26: HTTPS-only viewer protocol; default *.cloudfront.net cert (no custom
# domain v1 — ACM deferred); default-root-object index.html; 404 falls
# through to index.html.
# D-13: zero IAM wildcards beyond the unavoidable ${arn}/* object scope on
# the bucket-policy s3:GetObject grant (which IS the resource expression for
# objects in the bucket).
#
# force_destroy = true preferred over versioning for v1; rollback path is
# `git checkout` + re-run bin/deploy-widget.sh. Phase 4 may add versioning
# when the cleanup-verify script proves it tears down cleanly.

resource "aws_s3_bucket" "widget" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "widget" {
  bucket = aws_s3_bucket.widget.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- CloudFront Origin Access Control (NOT legacy OAI) ---
resource "aws_cloudfront_origin_access_control" "widget" {
  name                              = "${var.name_prefix}-widget-oac"
  description                       = "OAC for hera widget S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --- Response headers policy: HSTS + nosniff ---
# preload = false because preload requires explicit submission to the HSTS
# preload list (out of v1 scope).
resource "aws_cloudfront_response_headers_policy" "widget" {
  name = "${var.name_prefix}-widget-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }

    content_type_options {
      override = true
    }
  }
}

# --- CloudFront distribution ---
# cache_policy_id 658327ea-f89d-4fab-a63d-7e88639e58f6 = AWS-managed
# CachingOptimized policy.
resource "aws_cloudfront_distribution" "widget" {
  comment             = var.comment
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    origin_id                = "s3-widget"
    domain_name              = aws_s3_bucket.widget.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.widget.id

    # Required by the provider when OAC is used: pass an empty
    # origin_access_identity. The OAC reference above replaces the
    # legacy OAI flow.
    s3_origin_config {
      origin_access_identity = ""
    }
  }

  default_cache_behavior {
    target_origin_id           = "s3-widget"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.widget.id
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# --- Bucket policy: only the CloudFront distribution may read objects ---
data "aws_iam_policy_document" "widget_oac" {
  statement {
    sid     = "AllowCloudFrontOAC"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.widget.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.widget.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "widget" {
  bucket = aws_s3_bucket.widget.id
  policy = data.aws_iam_policy_document.widget_oac.json
}
