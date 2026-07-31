output "queue_url"          { value = aws_sqs_queue.processing.url }
output "queue_arn"          { value = aws_sqs_queue.processing.arn }
output "processor_function_arn" { value = aws_lambda_function.processor.arn }
output "event_bus_name"     { value = aws_cloudwatch_event_bus.processing.name }
