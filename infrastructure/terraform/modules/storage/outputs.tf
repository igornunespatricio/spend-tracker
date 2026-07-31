output "table_name"          { value = aws_dynamodb_table.items.name }
output "table_arn"           { value = aws_dynamodb_table.items.arn }
output "website_bucket_id"   { value = aws_s3_bucket.website.id }
output "website_bucket_arn"  { value = aws_s3_bucket.website.arn }
output "photos_bucket_name"  { value = aws_s3_bucket.photos.bucket }
output "photos_bucket_arn"   { value = aws_s3_bucket.photos.arn }
