# The analytics pipeline (docs/prior-art/2026-10-19-phase5-events.md) on real SNS and SQS. Only the
# worker role may publish to the topic, and only the topic may send to the queue, so nobody else can
# inject events into a center's analytics.

locals {
  topic_name = "cubby-domain-events-production"
  queue_name = "cubby-analytics-production"
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
        Sid       = "WorkerPublishes"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.pod["worker"].arn }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.events.arn
      },
      {
        Sid       = "OnlyWorkerPublishes"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.events.arn
        Condition = { ArnNotEquals = { "aws:PrincipalArn" = aws_iam_role.pod["worker"].arn } }
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
