# Terraform owns what comes from infrastructure (namespace, config, secrets, Flux itself); Flux owns
# the workloads in deploy/production, synced from the public GitHub repo with no write credentials.

data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = "cubby-tfstate-731956852586"
    key    = "base/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  namespace = "cubby"
  site      = data.terraform_remote_state.base.outputs.site_domain
}

resource "random_password" "secret_key_base" {
  length  = 64
  special = false
}

# Shared by the demo directors; read it with `terraform -chdir=infra/terraform/cluster output -raw demo_password`.
resource "random_password" "demo" {
  length  = 20
  special = false
}

resource "kubernetes_namespace_v1" "cubby" {
  metadata {
    name = local.namespace
  }
  depends_on = [module.eks]
}

resource "kubernetes_config_map_v1" "cubby" {
  metadata {
    name      = "cubby-config"
    namespace = kubernetes_namespace_v1.cubby.metadata[0].name
  }
  data = {
    AWS_REGION                 = "us-east-1"
    APP_ORIGINS                = "https://${local.site}"
    CUBBY_TRUST_VIEWER_ADDRESS = "1"
    CUBBY_DEMO                 = "1"
    EVENTS_TOPIC_ARN           = aws_sns_topic.events.arn
    EVENTS_QUEUE_NAME          = aws_sqs_queue.events.name
    EVENTS_BUCKET              = data.terraform_remote_state.base.outputs.analytics_bucket
    RAILS_MAX_THREADS          = "3"
  }
}

resource "kubernetes_secret_v1" "cubby" {
  metadata {
    name      = "cubby-secrets"
    namespace = kubernetes_namespace_v1.cubby.metadata[0].name
  }
  data = {
    DATABASE_URL    = "postgres://cubby:${random_password.db.result}@${aws_db_instance.cubby.address}:5432/cubby?sslmode=require"
    REDIS_URL       = "rediss://:${random_password.cache.result}@${aws_elasticache_replication_group.cubby.primary_endpoint_address}:6379/0"
    SECRET_KEY_BASE = random_password.secret_key_base.result
    DEMO_PASSWORD   = random_password.demo.result
  }
}

resource "helm_release" "flux" {
  name             = "flux"
  namespace        = "flux-system"
  create_namespace = true
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = "2.19.1"
  values = [yamlencode({
    helmController            = { create = false }
    imageAutomationController = { create = false }
    imageReflectionController = { create = false }
    notificationController    = { create = false }
  })]
  depends_on = [module.eks]
}

resource "helm_release" "flux_sync" {
  name       = "cubby"
  namespace  = "flux-system"
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2-sync"
  version    = "1.15.1"
  values = [yamlencode({
    gitRepository = {
      spec = {
        url      = "https://github.com/kvadou/cubby"
        ref      = { branch = "main" }
        interval = "1m"
      }
    }
    kustomization = {
      spec = {
        path     = "./deploy/production"
        interval = "5m"
        prune    = true
        wait     = true
        timeout  = "10m"
      }
    }
  })]
  depends_on = [
    helm_release.flux,
    kubernetes_config_map_v1.cubby,
    kubernetes_secret_v1.cubby,
    aws_eks_pod_identity_association.pod,
  ]
}

output "site_url" { value = "https://${local.site}" }

output "demo_password" {
  value     = random_password.demo.result
  sensitive = true
}
