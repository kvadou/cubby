# The event pipeline: outbox -> SNS topic -> SQS queue -> analytics consumer -> domain_events, plus a
# nightly S3 export (docs/prior-art/2026-10-19-phase5-events.md).
#
# Outside production, events only ever go to an explicit local endpoint (Moto in compose). Without one
# they stay in the outbox, so a developer's real AWS credentials can never publish by accident.
module Events
  ACCOUNT = ENV.fetch("EVENTS_AWS_ACCOUNT", "123456789012") # Moto's default account id
  # Environment-suffixed defaults keep test runs from sharing a local queue with the dev consumer.
  TOPIC_NAME = ENV.fetch("EVENTS_TOPIC_NAME", "cubby-domain-events-#{Rails.env}")
  QUEUE_NAME = ENV.fetch("EVENTS_QUEUE_NAME", "cubby-analytics-#{Rails.env}")
  DLQ_NAME = "#{QUEUE_NAME}-dlq".freeze
  BUCKET = ENV.fetch("EVENTS_BUCKET", "cubby-analytics-#{Rails.env}")

  module_function

  def endpoint = ENV["EVENTS_AWS_ENDPOINT"].presence

  def enabled? = endpoint.present? || Rails.env.production?

  def client_options
    options = { region: ENV.fetch("AWS_REGION", "us-east-1") }
    endpoint ? options.merge(endpoint: endpoint, credentials: Aws::Credentials.new("local", "local")) : options
  end

  def sns = @sns ||= Aws::SNS::Client.new(**client_options)
  def sqs = @sqs ||= Aws::SQS::Client.new(**client_options)
  def s3 = @s3 ||= Aws::S3::Client.new(**client_options, force_path_style: endpoint.present?)

  def topic_arn = ENV.fetch("EVENTS_TOPIC_ARN") { "arn:aws:sns:#{client_options[:region]}:#{ACCOUNT}:#{TOPIC_NAME}" }
  def queue_url = @queue_url ||= sqs.get_queue_url(queue_name: QUEUE_NAME).queue_url

  def forget_queue_url! = @queue_url = nil

  # Specs swap in stubbed clients.
  def reset!(sns: nil, sqs: nil, s3: nil)
    @sns = sns
    @sqs = sqs
    @s3 = s3
    @queue_url = nil
  end
end
