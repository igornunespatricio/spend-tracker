# ── SQS FIFO Queue ────────────────────────────────────────────────────────────
resource "aws_sqs_queue" "processing_dlq" {
  name                        = "${var.name_prefix}-processing-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600  # 14 days
  tags                        = { Name = "${var.name_prefix}-processing-dlq" }
}

resource "aws_sqs_queue" "processing" {
  name                        = "${var.name_prefix}-processing.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 300
  message_retention_seconds   = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${var.name_prefix}-processing" }
}

# Allow S3 to send messages to queue (photo upload notification path)
resource "aws_sqs_queue_policy" "processing" {
  queue_url = aws_sqs_queue.processing.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaSend"
        Effect = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.processing.arn
      }
    ]
  })
}

# ── Processor Lambda ──────────────────────────────────────────────────────────
data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.root}/../../backend/lambdas/processor"
  output_path = "${path.module}/processor.zip"
}

resource "aws_lambda_function" "processor" {
  function_name    = "${var.name_prefix}-processor"
  role             = var.processor_role_arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = 300
  memory_size      = 512

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      TABLE_NAME           = var.table_name
      PHOTOS_BUCKET        = var.photos_bucket_name
      REGION               = var.aws_region
      ALLOWED_MODELS       = var.allowed_models
      GUARDRAIL_ID         = var.guardrail_id
      GUARDRAIL_VERSION    = var.guardrail_version
    }
  }

  tags = { Name = "${var.name_prefix}-processor" }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.processing.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 1
  enabled          = true
}

# EventBridge bus for lifecycle hooks
resource "aws_cloudwatch_event_bus" "processing" {
  name = "${var.name_prefix}-processing"
  tags = { Name = "${var.name_prefix}-processing" }
}
