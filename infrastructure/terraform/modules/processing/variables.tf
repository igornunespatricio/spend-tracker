variable "environment"         { type = string }
variable "name_prefix"         { type = string }
variable "aws_region"          { type = string }
variable "photos_bucket_arn"   { type = string }
variable "photos_bucket_name"  { type = string }
variable "table_name"          { type = string }
variable "table_arn"           { type = string }
variable "processor_role_arn"  { type = string }
variable "allowed_models"      { type = string }
variable "guardrail_id"        { type = string; default = "" }
variable "guardrail_version"   { type = string; default = "DRAFT" }
