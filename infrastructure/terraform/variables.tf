variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "callback_url" {
  description = "OAuth callback URL for Cognito hosted UI"
  type        = string
  default     = "http://localhost:5173"
}

variable "allowed_bedrock_models" {
  description = "Comma-separated list of Bedrock model IDs available for photo processing"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0,anthropic.claude-3-5-haiku-20241022-v1:0,anthropic.claude-3-5-sonnet-20241022-v2:0,anthropic.claude-3-opus-20240229-v1:0"
}

variable "bedrock_guardrail_id" {
  description = "Bedrock Guardrail ID to apply to all model invocations"
  type        = string
  default     = ""
}

variable "bedrock_guardrail_version" {
  description = "Bedrock Guardrail version"
  type        = string
  default     = "DRAFT"
}
