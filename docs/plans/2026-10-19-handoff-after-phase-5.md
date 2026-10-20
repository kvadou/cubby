# Handoff after phase 5 (2026-10-19)

**Repo:** github.com/kvadou/cubby. Decisions: `docs/prior-art/2026-10-19-phase5-events.md` (O1 to O6 closed).

## Done
- `outbox_events` and `domain_events` tables; `OutboxEvent.record!` / `record_all!` with a no-personal-data validation.
- Events from `ProposedAction#transition!` (approved, dismissed, resolved), `#snooze!`, `CenterScan#insert` (proposed), and `Drafting::Drafter#write` (draft.completed).
- `Events::Publisher` (SKIP LOCKED, batches of 10), `PublishOutboxJob` (post-commit kick plus a one-minute cron), `Events::Consumer` (`bin/rails events:consume`, a compose `events` service), `Events::Exporter` with `ExportDomainEventsJob` (2:30 AM Central, UTC-day partitions), `Events::Setup` (`bin/rails events:setup`, local only).
- `GET /api/v1/centers/:id/analytics?days=7|30|90` (`Analytics::Report`) and the web Analytics tab: tiles, a by-type table, a daily chart with an accessible table, and a pipeline footer. Browser-checked at 1280 and 375 px.
- Moto 5.2.4 in compose (port 5055) and in API CI, which now runs the end-to-end pipeline spec.
- 159 API specs, 11 web tests.

## Gotchas
- Topic and queue names default to an environment suffix (`cubby-analytics-development`, `-test`), so specs never race the dev consumer for messages.
- The consumer survives a missing queue (it can start before setup); compose restarts `events` and `sidekiq` if they exit.
- Export partitions are UTC days.

## Phase 6 notes
- Create the topic, queue, DLQ, subscription (raw delivery), and bucket in Terraform; set `EVENTS_TOPIC_ARN`, `EVENTS_QUEUE_NAME`, `EVENTS_BUCKET`.
- IAM per pod: api and sidekiq `sns:Publish` on the topic; events `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueUrl`; exporter `s3:PutObject` on the bucket prefix.
- Queue policy: accept `sqs:SendMessage` only from the topic (`aws:SourceArn` = topic ARN); topic policy: `sns:Publish` only from the app role. Otherwise anyone with queue access could inject events into any center's analytics.
- Alarm on the DLQ depth and on outbox rows stuck unpublished.
- Re-run `api/spec/integration/event_pipeline_spec.rb` against real AWS.

## Still open from phase 4
Bedrock access on account 731956852586 (Error 002). See `docs/plans/2026-10-19-handoff-after-phase-4.md`.

## Next: phase 6
Terraform (VPC, EKS, RDS, ElastiCache, ECR, S3 + CloudFront, SNS/SQS, IAM with IRSA, CloudWatch), FluxCD, `make up` / `make down`, $50 budget alarm, and the phase 3 deploy checklist.
