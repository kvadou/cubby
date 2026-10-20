# The demo host: Amazon Linux 2023 on a t4g.small running Postgres (pgvector), Valkey, the Rails API,
# Sidekiq, and the events consumer under Docker Compose. A timer deploys whatever image tag
# deploy/production/kustomization.yaml names on main, the same GitOps source Flux follows on EKS.

locals {
  bedrock_profiles = ["claude-haiku-4-5-20251001-v1:0", "claude-sonnet-4-5-20250929-v1:0"]
  compose_version  = "v5.5.1"
  compose_sha256   = "732e3a84c1a0f67256ce80bc2598a24546b10ca05f9faa97efceb1171ece2ef7" # docker-compose-linux-aarch64
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# --- Identity: one role for the whole host (api, worker, and events share it) ---------------------

resource "aws_iam_role" "host" {
  name = "cubby-demo-host"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "host" {
  name = "cubby-demo-host"
  role = aws_iam_role.host.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = "arn:aws:ecr:us-east-1:${local.account_id}:repository/cubby-api"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:us-east-1:${local.account_id}:parameter${local.param_path}"
      },
      # Session Manager for debugging, without AmazonSSMManagedInstanceCore's account-wide ssm:GetParameter.
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation", "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel", "ec2messages:*"
        ]
        Resource = "*"
      },
      # Only the models api/app/services/ai/bedrock.rb calls. US inference profiles route to these regions.
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = concat(
          [for p in local.bedrock_profiles : "arn:aws:bedrock:us-east-1:${local.account_id}:inference-profile/us.anthropic.${p}"],
          [for p in local.bedrock_profiles : "arn:aws:bedrock:*::foundation-model/anthropic.${p}"],
          ["arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"]
        )
        Condition = { StringEquals = { "aws:RequestedRegion" = ["us-east-1", "us-east-2", "us-west-2"] } }
      },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.events.arn },
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueUrl"], Resource = aws_sqs_queue.events.arn },
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${data.terraform_remote_state.base.outputs.analytics_bucket_arn}/events/*" }
    ]
  })
}

resource "aws_iam_instance_profile" "host" {
  name = "cubby-demo-host"
  role = aws_iam_role.host.name
}

# --- Network access: CloudFront in, anything out --------------------------------------------------

resource "aws_security_group" "host" {
  name        = "cubby-demo-host"
  description = "Cubby demo host: only CloudFront's VPC origin in"
  vpc_id      = aws_vpc.demo.id
}

resource "aws_vpc_security_group_egress_rule" "host_out" {
  security_group_id = aws_security_group.host.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "ECR, GitHub, AWS APIs"
}

# CloudFront creates this group when the VPC origin is created. Admitting it, rather than CloudFront's
# whole prefix list, means only this account's distributions reach the instance, not anyone else's
# distribution pointed at its public address.
data "aws_security_group" "cloudfront_vpc_origin" {
  vpc_id = aws_vpc.demo.id
  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }
  depends_on = [aws_cloudfront_vpc_origin.api]
}

resource "aws_vpc_security_group_ingress_rule" "host_from_cloudfront" {
  security_group_id            = aws_security_group.host.id
  referenced_security_group_id = data.aws_security_group.cloudfront_vpc_origin.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "CloudFront VPC origin"
}

# --- The instance ---------------------------------------------------------------------------------

resource "aws_instance" "host" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.small"
  subnet_id              = aws_subnet.demo.id
  vpc_security_group_ids = [aws_security_group.host.id]
  iam_instance_profile   = aws_iam_instance_profile.host.name

  # Containers reach the instance role through IMDSv2, which needs a hop limit of 2 from a bridge network.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  user_data = templatefile("${path.module}/host/cloud-init.sh.tftpl", {
    compose       = file("${path.module}/host/compose.yaml")
    deploy        = file("${path.module}/host/deploy.sh")
    compose_url   = "https://github.com/docker/compose/releases/download/${local.compose_version}/docker-compose-linux-aarch64"
    compose_sha   = local.compose_sha256
    param_path    = local.param_path
    registry      = "${local.account_id}.dkr.ecr.us-east-1.amazonaws.com"
    app_origins   = "https://${local.site}"
    topic_arn     = aws_sns_topic.events.arn
    queue_name    = aws_sqs_queue.events.name
    events_bucket = data.terraform_remote_state.base.outputs.analytics_bucket
  })
  # A changed boot script means a fresh host; the demo re-seeds itself on first boot.
  user_data_replace_on_change = true

  lifecycle {
    # A newer AMI shouldn't replace a working demo; replace it on purpose with -replace.
    ignore_changes = [ami]
  }

  tags = { Name = "cubby-demo" }
}

resource "aws_cloudfront_vpc_origin" "api" {
  vpc_origin_endpoint_config {
    name                   = "cubby-demo-api"
    arn                    = aws_instance.host.arn
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

# --- Self-healing and alerts ----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "system_check" {
  alarm_name          = "cubby-demo-system-check"
  alarm_description   = "The demo host's underlying hardware failed a check; EC2 recovers it onto new hardware."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = aws_instance.host.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = ["arn:aws:automate:us-east-1:ec2:recover", data.terraform_remote_state.base.outputs.alerts_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "instance_check" {
  alarm_name          = "cubby-demo-instance-check"
  alarm_description   = "The demo host stopped responding (often out of memory); EC2 reboots it."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  dimensions          = { InstanceId = aws_instance.host.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = ["arn:aws:automate:us-east-1:ec2:reboot", data.terraform_remote_state.base.outputs.alerts_topic_arn]
}

output "api_origin" {
  description = "Read by `make demo` into the base stack's api_origin variable."
  value = {
    domain_name   = aws_instance.host.private_dns
    vpc_origin_id = aws_cloudfront_vpc_origin.api.id
  }
}

output "instance_id" {
  description = "For aws ssm start-session --target <id>."
  value       = aws_instance.host.id
}
