locals {
  environment = terraform.workspace
  name_prefix = "spend-tracker-${local.environment}"
}

module "iam" {
  source      = "./modules/iam"
  environment = local.environment
  name_prefix = local.name_prefix
  aws_region  = var.aws_region
  account_id  = data.aws_caller_identity.current.account_id
}

module "storage" {
  source      = "./modules/storage"
  environment = local.environment
  name_prefix = local.name_prefix
  aws_region  = var.aws_region
}

module "auth" {
  source       = "./modules/auth"
  environment  = local.environment
  name_prefix  = local.name_prefix
  aws_region   = var.aws_region
  callback_url = var.callback_url
}

module "processing" {
  source              = "./modules/processing"
  environment         = local.environment
  name_prefix         = local.name_prefix
  aws_region          = var.aws_region
  photos_bucket_arn   = module.storage.photos_bucket_arn
  photos_bucket_name  = module.storage.photos_bucket_name
  table_name          = module.storage.table_name
  table_arn           = module.storage.table_arn
  processor_role_arn  = module.iam.processor_lambda_role_arn
  allowed_models      = var.allowed_bedrock_models
  guardrail_id        = var.bedrock_guardrail_id
  guardrail_version   = var.bedrock_guardrail_version
}

module "api" {
  source                = "./modules/api"
  environment           = local.environment
  name_prefix           = local.name_prefix
  aws_region            = var.aws_region
  table_name            = module.storage.table_name
  table_arn             = module.storage.table_arn
  photos_bucket_name    = module.storage.photos_bucket_name
  photos_bucket_arn     = module.storage.photos_bucket_arn
  processing_queue_url  = module.processing.queue_url
  processing_queue_arn  = module.processing.queue_arn
  api_lambda_role_arn   = module.iam.api_lambda_role_arn
  cognito_user_pool_arn = module.auth.user_pool_arn
  allowed_models        = var.allowed_bedrock_models
}

module "cdn" {
  source             = "./modules/cdn"
  environment        = local.environment
  name_prefix        = local.name_prefix
  website_bucket_id  = module.storage.website_bucket_id
  website_bucket_arn = module.storage.website_bucket_arn
  api_endpoint       = module.api.api_endpoint
}

data "aws_caller_identity" "current" {}
