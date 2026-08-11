# ── Lambda Functions ──────────────────────────────────────────────────────────
data "archive_file" "spending_api" {
  type        = "zip"
  source_dir  = "${path.root}/../../backend/lambdas/api/spending"
  output_path = "${path.module}/spending_api.zip"
}

resource "aws_lambda_function" "spending_api" {
  function_name    = "${var.name_prefix}-spending-api"
  role             = var.api_lambda_role_arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.spending_api.output_path
  source_code_hash = data.archive_file.spending_api.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      TABLE_NAME           = var.table_name
      PHOTOS_BUCKET        = var.photos_bucket_name
      PROCESSING_QUEUE_URL = var.processing_queue_url
      REGION               = var.aws_region
      ALLOWED_MODELS       = var.allowed_models
    }
  }

  tags = { Name = "${var.name_prefix}-spending-api" }
}

# ── HTTP API Gateway ──────────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["Content-Type", "Authorization"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = { Name = "${var.name_prefix}-api" }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-authorizer"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

resource "aws_apigatewayv2_integration" "spending_api" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.spending_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "spending_routes" {
  for_each = toset([
    "GET /api/spending",
    "POST /api/spending",
    "DELETE /api/spending/{itemId}",
    "GET /api/jobs/{jobId}",
    "POST /api/jobs",
    "POST /api/jobs/{jobId}/submit",
    "PUT /api/jobs/{jobId}/confirm",
    "GET /api/categories",
  ])

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.spending_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format          = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.name_prefix}"
  retention_in_days = var.environment == "prod" ? 90 : 14
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.spending_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Store API endpoint in SSM for frontend builds
resource "aws_ssm_parameter" "api_endpoint" {
  name  = "/spend-tracker/${var.environment}/api/endpoint"
  type  = "String"
  value = aws_apigatewayv2_stage.default.invoke_url
}
