module Events
  # Creates the local topic, queue, dead-letter queue, subscription, and bucket in Moto. Idempotent.
  # Real AWS resources come from Terraform in phase 6, never from this.
  module Setup
    module_function

    def call
      raise "Events::Setup only targets a local endpoint (EVENTS_AWS_ENDPOINT)" unless Events.endpoint

      topic = Events.sns.create_topic(name: TOPIC_NAME).topic_arn
      dlq_url = Events.sqs.create_queue(queue_name: DLQ_NAME).queue_url
      dlq_arn = Events.sqs.get_queue_attributes(queue_url: dlq_url, attribute_names: [ "QueueArn" ]).attributes["QueueArn"]
      url = Events.sqs.create_queue(queue_name: QUEUE_NAME, attributes: {
        "RedrivePolicy" => { deadLetterTargetArn: dlq_arn, maxReceiveCount: 5 }.to_json,
        "VisibilityTimeout" => "60"
      }).queue_url
      arn = Events.sqs.get_queue_attributes(queue_url: url, attribute_names: [ "QueueArn" ]).attributes["QueueArn"]
      unless Events.sns.list_subscriptions_by_topic(topic_arn: topic).subscriptions.any? { |s| s.endpoint == arn }
        Events.sns.subscribe(topic_arn: topic, protocol: "sqs", endpoint: arn, attributes: { "RawMessageDelivery" => "true" })
      end
      Events.s3.create_bucket(bucket: BUCKET) unless Events.s3.list_buckets.buckets.any? { |b| b.name == BUCKET }
      { topic: topic, queue: url, dlq: dlq_url, bucket: BUCKET }
    end
  end
end
