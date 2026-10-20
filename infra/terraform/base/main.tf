# Persistent, near-free pieces that outlive `make down`: the image registry, the web app on S3 behind
# CloudFront, the analytics export bucket, the GitHub Actions deploy role, alerts, and the budget.
# Decisions: docs/prior-art/2026-10-19-phase6-deploy.md.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.60" }
  }
  backend "s3" {
    bucket       = "cubby-tfstate-731956852586"
    key          = "base/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["731956852586"] # Doug's personal Cubby account, never the STC account
  default_tags {
    tags = { Project = "cubby", ManagedBy = "terraform", Stack = "base" }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  github_repo = "kvadou/cubby"

  # AWS managed CloudFront policies (ids from `aws cloudfront list-*-policies --type managed`).
  caching_optimized         = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  caching_disabled          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  all_viewer_and_cf_headers = "33f36d7e-f396-46d9-90e0-52428a34d9dc"
}

variable "api_origin" {
  description = "The cluster's private load balancer as a CloudFront VPC origin; null while the cluster is down. Written by `make up` / `make down`."
  type = object({
    domain_name   = string
    vpc_origin_id = string
  })
  default = null
}

variable "alert_email" {
  description = "Optional address subscribed to budget and alarm notifications (confirm the email AWS sends)."
  type        = string
  default     = ""
}

# --- Image registry -------------------------------------------------------------------------------

resource "aws_ecr_repository" "api" {
  name                 = "cubby-api"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 20 newest images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

# --- Buckets --------------------------------------------------------------------------------------

resource "aws_s3_bucket" "web" {
  bucket = "cubby-web-${local.account_id}"
}

resource "aws_s3_bucket" "analytics" {
  bucket = "cubby-analytics-production-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "private" {
  for_each                = { web = aws_s3_bucket.web.id, analytics = aws_s3_bucket.analytics.id }
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "owner" {
  for_each = { web = aws_s3_bucket.web.id, analytics = aws_s3_bucket.analytics.id }
  bucket   = each.value
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  for_each = { web = aws_s3_bucket.web.id, analytics = aws_s3_bucket.analytics.id }
  bucket   = each.value
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Only this distribution can read the web bucket.
resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontReads"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn } }
    }]
  })
}

# --- CloudFront -----------------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "cubby-web"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Client-side routes get index.html; /api/* answers 503 when the cluster is down (that path only
# reaches this function when no /api/* behavior exists).
resource "aws_cloudfront_function" "spa" {
  name    = "cubby-spa"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/spa.js")
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "cubby"
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  http_version        = "http2and3"

  origin {
    origin_id                = "web"
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  dynamic "origin" {
    for_each = var.api_origin == null ? [] : [var.api_origin]
    content {
      origin_id   = "api"
      domain_name = origin.value.domain_name
      vpc_origin_config {
        vpc_origin_id            = origin.value.vpc_origin_id
        origin_read_timeout      = 60 # Ask Cubby can take up to 45 s
        origin_keepalive_timeout = 5
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = "web"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = local.caching_optimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
    compress                   = true
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa.arn
    }
  }

  # The API: never cached, every viewer header forwarded (cookies, Origin, Sec-Fetch-Site,
  # Authorization) plus CloudFront-Viewer-Address for per-viewer rate limits.
  dynamic "ordered_cache_behavior" {
    for_each = var.api_origin == null ? [] : [var.api_origin]
    content {
      path_pattern               = "/api/*"
      target_origin_id           = "api"
      viewer_protocol_policy     = "https-only"
      allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods             = ["GET", "HEAD"]
      cache_policy_id            = local.caching_disabled
      origin_request_policy_id   = local.all_viewer_and_cf_headers
      response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
      compress                   = true
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Security headers on every response, the API included. The app loads only its own bundle plus Inter
# from Google Fonts; React style attributes need 'unsafe-inline' for styles only.
resource "aws_cloudfront_response_headers_policy" "security" {
  name = "cubby-security"
  security_headers_config {
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src https://fonts.gstatic.com",
        "img-src 'self' data:",
        "connect-src 'self'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "object-src 'none'",
      ])
      override = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

# --- GitHub Actions deploy role (OIDC, main branch only) ------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "deploy" {
  name = "cubby-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  name = "deploy"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      {
        Effect = "Allow"
        Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:DescribeImages"]
        Resource = aws_ecr_repository.api.arn
      },
      { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.web.arn },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.web.arn}/*" },
      { Effect = "Allow", Action = "cloudfront:CreateInvalidation", Resource = aws_cloudfront_distribution.site.arn }
    ]
  })
}

# --- Alerts and budget ----------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "cubby-alerts"
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AwsServicesPublish"
      Effect    = "Allow"
      Principal = { Service = ["budgets.amazonaws.com", "cloudwatch.amazonaws.com"] }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_sns_topic_subscription" "alert_email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_budgets_budget" "monthly" {
  name         = "cubby-monthly"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.alerts]
}

# --- Outputs (read by the cluster stack and CI) ---------------------------------------------------

output "site_domain" { value = aws_cloudfront_distribution.site.domain_name }
output "distribution_id" { value = aws_cloudfront_distribution.site.id }
output "ecr_repository_url" { value = aws_ecr_repository.api.repository_url }
output "web_bucket" { value = aws_s3_bucket.web.id }
output "analytics_bucket" { value = aws_s3_bucket.analytics.id }
output "analytics_bucket_arn" { value = aws_s3_bucket.analytics.arn }
output "alerts_topic_arn" { value = aws_sns_topic.alerts.arn }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
