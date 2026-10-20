# The analytics pipeline on real SNS and SQS, as in the cluster stack (infra/terraform/cluster/events.tf)
# but with demo names so both stacks can exist at once. Only the instance role may publish, and only the
# topic may send to the queue.

locals {
  topic_name = "cubby-demo-domain-events"
  queue_name = "cubby-demo-analytics"
}

resource "aws_sns_topic" "events" {
  name = local.topic_name
}

resource "aws_sqs_queue" "events_dlq" {
  name                      = "${local.queue_name}-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "events" {
  name                       = local.queue_name
  visibility_timeout_seconds = 60
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "events_dlq" {
  queue_url = aws_sqs_queue.events_dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.events.arn]
  })
}

resource "aws_sns_topic_subscription" "events" {
  topic_arn            = aws_sns_topic.events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.events.arn
  raw_message_delivery = true
}

resource "aws_sns_topic_policy" "events" {
  arn = aws_sns_topic.events.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "HostPublishes"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.host.arn }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.events.arn
      },
      {
        Sid       = "OnlyHostPublishes"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.events.arn
        Condition = { ArnNotEquals = { "aws:PrincipalArn" = aws_iam_role.host.arn } }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "events" {
  queue_url = aws_sqs_queue.events.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "TopicDelivers"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.events.arn
        Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.events.arn } }
      },
      {
        Sid       = "OnlyTopicDelivers"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.events.arn
        Condition = { ArnNotEquals = { "aws:SourceArn" = aws_sns_topic.events.arn } }
      }
    ]
  })
}
