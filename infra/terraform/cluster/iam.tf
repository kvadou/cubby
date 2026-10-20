# One role per workload through EKS Pod Identity, each with only what that process calls:
#   api     Bedrock (Ask Cubby answers inside the request)
#   worker  Bedrock (drafts), publish to the events topic, write the nightly S3 export
#   events  read and delete from the analytics queue

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  bedrock = {
    Effect = "Allow"
    Action = ["bedrock:InvokeModel"]
    Resource = [
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
      "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0",
      "arn:aws:bedrock:us-east-1:${local.account_id}:inference-profile/us.anthropic.claude-*"
    ]
  }

  pod_policies = {
    api = [local.bedrock]
    worker = [
      local.bedrock,
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [aws_sns_topic.events.arn] },
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${data.terraform_remote_state.base.outputs.analytics_bucket_arn}/events/*"] }
    ]
    events = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueUrl"], Resource = [aws_sqs_queue.events.arn] }
    ]
  }
}

resource "aws_iam_role" "pod" {
  for_each = local.pod_policies
  name     = "cubby-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "pod" {
  for_each = local.pod_policies
  name     = "cubby-${each.key}"
  role     = aws_iam_role.pod[each.key].id
  policy   = jsonencode({ Version = "2012-10-17", Statement = each.value })
}

resource "aws_eks_pod_identity_association" "pod" {
  for_each        = local.pod_policies
  cluster_name    = module.eks.cluster_name
  namespace       = local.namespace
  service_account = "cubby-${each.key}"
  role_arn        = aws_iam_role.pod[each.key].arn
}
