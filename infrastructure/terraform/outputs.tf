output "website_url" {
  description = "CloudFront URL for the frontend application"
  value       = module.cdn.cloudfront_url
}

output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = module.api.api_endpoint
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.auth.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito App Client ID"
  value       = module.auth.client_id
}

output "table_name" {
  description = "DynamoDB table name"
  value       = module.storage.table_name
}

output "photos_bucket_name" {
  description = "S3 bucket name for photo uploads"
  value       = module.storage.photos_bucket_name
}

output "website_bucket_name" {
  description = "S3 bucket name for website assets"
  value       = module.storage.website_bucket_id
}

output "processing_queue_url" {
  description = "SQS queue URL for photo processing jobs"
  value       = module.processing.queue_url
}
