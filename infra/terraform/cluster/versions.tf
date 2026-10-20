terraform {
  required_version = ">= 1.10"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.60" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }
    helm       = { source = "hashicorp/helm", version = "~> 3.0" }
    random     = { source = "hashicorp/random", version = "~> 3.7" }
  }
  backend "s3" {
    bucket       = "cubby-tfstate-731956852586"
    key          = "cluster/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["731956852586"] # Doug's personal Cubby account, never the STC account
  default_tags {
    tags = { Project = "cubby", ManagedBy = "terraform", Stack = "cluster" }
  }
}

# Both providers authenticate with a short-lived EKS token from the same `cubby` profile.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "us-east-1"]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "us-east-1"]
    }
  }
}
