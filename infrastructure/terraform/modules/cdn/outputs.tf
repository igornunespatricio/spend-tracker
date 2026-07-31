output "cloudfront_url"         { value = "https://${aws_cloudfront_distribution.main.domain_name}" }
output "cloudfront_domain_name" { value = aws_cloudfront_distribution.main.domain_name }
output "distribution_id"        { value = aws_cloudfront_distribution.main.id }
