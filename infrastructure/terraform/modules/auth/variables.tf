variable "environment" { type = string }
variable "name_prefix" { type = string }
variable "aws_region"  { type = string }
variable "callback_url" { type = string; default = "http://localhost:5173" }
