# An internal ALB in the private subnets, reachable only through CloudFront's VPC origin. Traffic from
# the edge to the ALB stays on AWS's network, so plain HTTP inside is acceptable without a custom
# domain, and the CloudFront-Viewer-Address header can be trusted (lib/middleware/viewer_address.rb).

locals {
  api_node_port = 30080
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "cubby-alb"
  description = "Cubby internal ALB: CloudFront in, nodes out"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "CloudFront VPC origin"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodes" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = module.eks.node_security_group_id
  from_port                    = local.api_node_port
  to_port                      = local.api_node_port
  ip_protocol                  = "tcp"
  description                  = "api NodePort"
}

resource "aws_lb" "api" {
  name                       = "cubby-api"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.vpc.private_subnets
  drop_invalid_header_fields = true
  idle_timeout               = 75
}

resource "aws_lb_target_group" "api" {
  name                 = "cubby-api"
  port                 = local.api_node_port
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = module.vpc.vpc_id
  deregistration_delay = 15
  health_check {
    path                = "/up"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# Every node in the managed group registers with the target group, including replacements.
resource "aws_autoscaling_attachment" "api" {
  autoscaling_group_name = module.eks.eks_managed_node_groups["default"].node_group_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.api.arn
}

resource "aws_cloudfront_vpc_origin" "api" {
  vpc_origin_endpoint_config {
    name                   = "cubby-api"
    arn                    = aws_lb.api.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
  timeouts {
    create = "30m"
    delete = "30m"
  }
}

output "api_origin" {
  description = "Read by `make up` into the base stack's api_origin variable."
  value = {
    domain_name   = aws_lb.api.dns_name
    vpc_origin_id = aws_cloudfront_vpc_origin.api.id
  }
}
