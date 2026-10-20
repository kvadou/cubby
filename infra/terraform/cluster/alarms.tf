# Alarms go to the base stack's alerts topic (and the optional alert email).

locals {
  alerts = [data.terraform_remote_state.base.outputs.alerts_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "events_dlq" {
  alarm_name          = "cubby-events-dlq"
  alarm_description   = "Analytics messages the consumer couldn't process landed in the dead-letter queue."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.events_dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alerts
}

resource "aws_cloudwatch_metric_alarm" "events_backlog" {
  alarm_name          = "cubby-events-backlog"
  alarm_description   = "Analytics events are waiting more than 10 minutes; is the events consumer running?"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = aws_sqs_queue.events.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 600
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alerts
}

resource "aws_cloudwatch_metric_alarm" "api_unhealthy" {
  alarm_name          = "cubby-api-unhealthy"
  alarm_description   = "No healthy api target behind the load balancer."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = { LoadBalancer = aws_lb.api.arn_suffix, TargetGroup = aws_lb_target_group.api.arn_suffix }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 10
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alerts
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "cubby-api-5xx"
  alarm_description   = "The api returned more than 10 server errors in 5 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.api.arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alerts
}
