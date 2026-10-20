# The always-on demo (docs/plans/2026-10-20-demo-host-plan.md): one small Graviton instance running the
# whole app with Docker Compose, about $18 a month, instead of the $5-a-day EKS cluster.
#
# One subnet in use1-az1 (CloudFront VPC origins don't support use1-az3). The instance has a public IP
# only for outbound traffic (ECR, GitHub, AWS APIs); its security group admits nothing but CloudFront's
# VPC origin, so the internet can't reach it directly. No NAT gateway, no SSH: use SSM Session Manager.

resource "aws_vpc" "demo" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "cubby-demo" }
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "cubby-demo" }
}

resource "aws_subnet" "demo" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.50.0.0/24"
  availability_zone_id    = "use1-az1"
  map_public_ip_on_launch = true
  tags                    = { Name = "cubby-demo" }
}

resource "aws_route_table" "demo" {
  vpc_id = aws_vpc.demo.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }
  tags = { Name = "cubby-demo" }
}

resource "aws_route_table_association" "demo" {
  subnet_id      = aws_subnet.demo.id
  route_table_id = aws_route_table.demo.id
}
