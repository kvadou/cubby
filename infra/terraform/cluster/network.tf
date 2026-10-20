# Two availability zones picked by zone id (CloudFront VPC origins don't support use1-az3).
# No NAT gateway: nodes sit in public subnets with public IPs for outbound traffic, and their security
# group admits nothing from the internet. The database, cache, control plane, and load balancer are
# in private subnets with no route out.
data "aws_availability_zones" "chosen" {
  filter {
    name   = "zone-id"
    values = ["use1-az1", "use1-az2"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = "cubby"
  cidr = "10.40.0.0/16"
  azs  = data.aws_availability_zones.chosen.names

  public_subnets  = ["10.40.0.0/20", "10.40.16.0/20"]
  private_subnets = ["10.40.128.0/20", "10.40.144.0/20"]

  enable_nat_gateway      = false
  map_public_ip_on_launch = true
  enable_dns_hostnames    = true
  enable_dns_support      = true
}
