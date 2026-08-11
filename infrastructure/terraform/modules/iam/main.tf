data "aws_iam_policy_document" "lambda_assume" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# ── API Lambda Role ────────────────────────────────────────────────────────────
resource "aws_iam_role" "api_lambda" {
  name               = "${var.name_prefix}-api-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "api_lambda" {
  name = "${var.name_prefix}-api-lambda-policy"
  role = aws_iam_role.api_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/${var.name_prefix}-*"
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
          "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name_prefix}-items",
          "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name_prefix}-items/index/*"
        ]
      },
      {
        Sid      = "S3Photos"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:GeneratePresignedUrl"]
        Resource = "arn:aws:s3:::${var.name_prefix}-photos/*"
      },
      {
        Sid      = "SQSSend"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = "arn:aws:sqs:${var.aws_region}:${var.account_id}:${var.name_prefix}-processing.fifo"
      }
    ]
  })
}

# ── Processor Lambda Role ─────────────────────────────────────────────────────
resource "aws_iam_role" "processor_lambda" {
  name               = "${var.name_prefix}-processor-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "processor_lambda" {
  name = "${var.name_prefix}-processor-lambda-policy"
  role = aws_iam_role.processor_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/${var.name_prefix}-*"
      },
      {
        Sid      = "SQSConsume"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = "arn:aws:sqs:${var.aws_region}:${var.account_id}:${var.name_prefix}-processing.fifo"
      },
      {
        Sid      = "S3Read"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.name_prefix}-photos/*"
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name_prefix}-items",
          "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name_prefix}-items/index/*"
        ]
      },
      {
        Sid      = "Bedrock"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:ApplyGuardrail"]
        Resource = "*"
      },
      {
        Sid      = "EventBridge"
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = "arn:aws:events:${var.aws_region}:${var.account_id}:event-bus/${var.name_prefix}-processing"
      }
    ]
  })
}
