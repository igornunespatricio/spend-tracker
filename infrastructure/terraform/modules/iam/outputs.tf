output "api_lambda_role_arn"       { value = aws_iam_role.api_lambda.arn }
output "processor_lambda_role_arn" { value = aws_iam_role.processor_lambda.arn }
output "github_actions_role_arn"   { value = aws_iam_role.github_actions.arn }
