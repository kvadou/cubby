# EKS with one small Graviton managed node group. Pods get AWS access through EKS Pod Identity
# (no OIDC provider, no node-role sharing). Control plane logs and a customer KMS key are off to keep
# an on-demand demo cheap; EKS encrypts Kubernetes API data with AWS-owned keys by default.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "cubby"
  kubernetes_version = "1.37"

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.public_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # kubectl and Terraform run from Doug's laptop; access still requires IAM through an access entry.
  endpoint_public_access = true

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  enable_irsa                 = false
  create_kms_key              = false
  encryption_config           = null
  enabled_log_types           = []
  create_cloudwatch_log_group = false

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = ["t4g.small"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size      = 20
    }
  }
}

# The load balancer reaches the api through its NodePort on each node.
resource "aws_vpc_security_group_ingress_rule" "nodes_from_alb" {
  security_group_id            = module.eks.node_security_group_id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = local.api_node_port
  to_port                      = local.api_node_port
  ip_protocol                  = "tcp"
  description                  = "ALB to api NodePort"
}
