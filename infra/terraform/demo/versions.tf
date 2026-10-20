terraform {
  required_version = ">= 1.10"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.60" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
  backend "s3" {
    bucket       = "cubby-tfstate-731956852586"
    key          = "demo/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["731956852586"] # Doug's personal Cubby account, never the STC account
  default_tags {
    tags = { Project = "cubby", ManagedBy = "terraform", Stack = "demo" }
  }
}

data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = "cubby-tfstate-731956852586"
    key    = "base/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  site       = data.terraform_remote_state.base.outputs.site_domain
}
