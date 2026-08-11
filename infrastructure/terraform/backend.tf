terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Values injected by scripts/03_create_tf_workspaces.sh or CI/CD
    # bucket               = "spend-tracker-tfstate-<accountId>"
    # key                  = "terraform.tfstate"
    # region               = "us-east-1"
    # use_lockfile         = true
    # encrypt              = true
    # workspace_key_prefix = ""   # → state stored at: bucket/<workspace>/terraform.tfstate
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "spend-tracker"
      Environment = local.environment
      ManagedBy   = "terraform"
    }
  }
}
