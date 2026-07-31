# ── CloudFront Origin Access Control ─────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.name_prefix}-website-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── CloudFront Distribution ───────────────────────────────────────────────────
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.name_prefix} website"
  price_class         = "PriceClass_100"

  aliases = []

  # S3 website origin
  origin {
    domain_name              = "${var.website_bucket_id}.s3.us-east-1.amazonaws.com"
    origin_id                = "S3-${var.website_bucket_id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  # Default cache behaviour → website
  default_cache_behavior {
    target_origin_id       = "S3-${var.website_bucket_id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # SPA: return index.html for all 404s (React Router)
  custom_error_response {
    error_code            = 403
    response_page_path    = "/index.html"
    response_code         = 200
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_page_path    = "/index.html"
    response_code         = 200
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "${var.name_prefix}-distribution" }
}

# Allow CloudFront to read from S3
data "aws_iam_policy_document" "website_bucket" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${var.website_bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "website" {
  bucket = var.website_bucket_id
  policy = data.aws_iam_policy_document.website_bucket.json
}
