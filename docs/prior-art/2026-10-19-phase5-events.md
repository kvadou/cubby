# Prior art: Cubby phase 5 events and analytics

Retrieved 2026-10-19. Research record for the phase 5 build.

## Decision first

- **Recommendation:**
  - Write an `outbox_events` row in the same transaction as every action change: proposed, approved, dismissed, resolved, snoozed, and draft completed.
  - Relay the rows to an SNS topic in batches of ten, claiming them with `FOR UPDATE SKIP LOCKED` and marking them published only after SNS accepts them.
  - Fan out to an SQS queue with raw delivery and a dead-letter queue, consumed by a long-polling process that dedupes on `event_id` into `domain_events`.
  - Export UTC days to S3 as JSON lines.
  - Build `/analytics` only from received events.
  - Run everything locally on Moto (D1 to D6).
- **Evidence:** the phase 2 record already planned the outbox inside `transition!` (phase 2 D9, E32). Outbox writeups agree on at-least-once publishing with a stable event id, idempotent consumers, and `SKIP LOCKED` for parallel relays (E2). Since 2026.03.0, LocalStack requires an auth token (E3). A live spike showed Moto 5.2.4 delivers SNS `publish_batch` to SQS with the raw body and message attributes intact (E4).
- **Limitation:** Moto proves the API calls and delivery path, not AWS-side behavior such as IAM, encryption, or throughput. Real AWS resources and IAM come from Terraform in phase 6.
- **Next check:** in phase 6, re-run `api/spec/integration/event_pipeline_spec.rb` against the real topic and queue, with IAM limited to `sns:Publish`, `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueUrl`, and `s3:PutObject`.

## Run header

- Outcome: phase 5 event pipeline plus an analytics page, with no dependency on Bedrock access. Mode greenfield. Profile Quick (4 searches, local source, one live spike).
- Known constraints: Rails 8.1, Sidekiq + sidekiq-cron, Postgres 17, phase 3 tenancy, and phase 2 D9 (outbox in `transition!`). Events leave the app, so they carry no personal data.
- Local-first: read the phase 2 record (D9, E32), `ProposedAction#transition!`, `CenterScan#insert`, and `Drafting::Drafter#write`.

## Questions

| ID | Question | Needs | Status | Answer |
| --- | --- | --- | --- | --- |
| Q1 | How do events leave the database without dual-write loss? | Pattern guidance, local seam | answered | D1, D2 |
| Q2 | What runs SNS/SQS/S3 locally without accounts or tokens? | Vendor announcements, live spike | answered | D6 |
| Q3 | How does the consumer stay correct under redelivery? | Pattern guidance | answered | D4 |
| Q4 | What may an event contain? | Local data rules | answered | D3 |
| Q5 | What should directors see? | Local product goals | answered | D5 |

## Evidence register

| ID | Family | Authority | Source / revision / locator | Status | Establishes |
| --- | --- | --- | --- | --- | --- |
| E1 | Local project | source | `docs/prior-art/2026-10-19-phase2-action-queue.md` D9/E32; `api/app/models/proposed_action.rb` `transition!`; `api/app/services/center_scan.rb` `insert` | read | Outbox seam already planned inside the guarded transition; scan inserts are bulk |
| E2 | Pattern writeups | secondary | oneuptime.com/blog/post/2026-07-22-transactional-outbox-duplicate-events; oneuptime.com/blog/post/2026-03-31-mysql-outbox-pattern; designgurus.io outbox answer (search summaries) | read | Marking a row sent before publishing can lose it, so publish at least once with a stable id; relays parallelize with `FOR UPDATE SKIP LOCKED`; consumers dedupe on event id in the same transaction as the effect |
| E3 | Vendor announcement | documentation | blog.localstack.cloud/localstack-for-aws-release-2026-03-0/; blog.localstack.cloud/localstack-single-image-next-steps/ (search summary) | read | Since 2026.03.0 (March 23, 2026) LocalStack requires an auth token; a free non-commercial tier exists with registration |
| E4 | Live feasibility | observed-artifact | `motoserver/moto:5.2.4` in compose, 2026-10-19: create topic and queue, subscribe with `RawMessageDelivery`, `publish_batch`, `receive_message` | read | Batch publish succeeded; the queue received the raw JSON body; the `event_type` message attribute arrived |
| E5 | Official contract | documentation | docs.aws.amazon.com/cli/latest/reference/sns/subscribe.html (search summary) | read | `RawMessageDelivery` removes the SNS JSON envelope for SQS subscribers; `RedrivePolicy` and filter policies are subscription attributes |
| E6 | Library source | source | Rails 8.1.4 `update_all` behavior observed in phase 4 (adds the locking column) and `ActiveRecord.after_all_transactions_commit` | read | Background writes must set `lock_version` explicitly; a post-commit hook can kick the publisher only after the event row exists |

## Decisions

| ID | Decision | Status | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| D1 | Event capture / T2 | supported | E1, E2 | `OutboxEvent.record!` inside `transition!`, `snooze!`, and the drafter's write; `record_all!` for scan inserts; kick `PublishOutboxJob` after commit, with a one-minute cron backstop |
| D2 | Relay / T2 | supported | E2, E4 | Claim 10 rows `FOR UPDATE SKIP LOCKED`, `publish_batch`, then mark only successful ids published; failed entries count attempts (cap 10); network errors leave rows for the next run. The lock is held across one SNS call, which is acceptable at this volume (the lease variant in E2 is the upgrade path) |
| D3 | Event content / T1 | supported | E1 | Ids, kinds, timestamps, decision categories, draft status and costs only; `OutboxEvent` validation rejects name, body, email, phone, address, note, subject, and text keys; dismiss notes become a fixed category |
| D4 | Consumer / T2 | supported | E2, E5 | SNS to SQS with raw delivery, a DLQ after 5 receives, `insert_all(unique_by: :event_id)`, and delete only after the insert; unreadable messages are left for the DLQ; the consumer survives missing queues and outages |
| D5 | Analytics / T3 | supported | E1 | Report built only from `domain_events` for the director's center: decisions, approval rate, median time to decision, how approved messages were written (draft as is, edited, without a draft), AI cost per approved message, daily decisions, pipeline lag and backlog |
| D6 | Local AWS / T3 | supported | E3, E4 | Moto 5.2.4 in compose and as a CI service container; outside production, events only go to an explicit `EVENTS_AWS_ENDPOINT`, never to a developer's real AWS account |

## Obligations

| ID | Decision | Invariant | Required authority | Check | Verified authority | Result | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| O1 | D1 | Each change writes exactly one event in its own transaction; a rejected transition writes none; a rescan writes no duplicate proposed events | integration | `api/spec/models/outbox_event_spec.rb` | integration | pass (2026-10-19, 159 examples) | closed |
| O2 | D2 | Batches of ten, only accepted rows marked published, rejected rows counted, outages lose nothing, no publishing without an endpoint outside production | integration | `api/spec/services/events/publisher_spec.rb` | integration | pass (2026-10-19, 159 examples) | closed |
| O3 | D3 | Payloads with personal keys are rejected; approval and dismissal events carry no names, message text, or notes | integration | `api/spec/models/outbox_event_spec.rb` | integration | pass (2026-10-19, 159 examples) | closed |
| O4 | D4 | A redelivered event is stored once; unreadable messages are not deleted; a missing queue doesn't stop the consumer | integration | `api/spec/services/events/consumer_spec.rb` | integration | pass (2026-10-19, 159 examples) | closed |
| O5 | D5 | Metrics computed correctly from events, scoped to the center, empty state safe | integration | `api/spec/requests/analytics_spec.rb` | integration | pass (2026-10-19, 159 examples) | closed |
| O6 | D6 | Approve to outbox to SNS to SQS to domain_events to S3 works against Moto | end-to-end | `api/spec/integration/event_pipeline_spec.rb` (Moto in CI) | end-to-end | pass locally against Moto 5.2.4 twice, plus a manual UI approve, dismiss, and snooze reaching analytics (2026-10-19) | closed |

## Coverage

| Source family | Status | Notes |
| --- | --- | --- |
| Local decisions and code | read | Phase 2 D9 and the transition seam (E1) |
| Pattern writeups | read | Outbox and idempotent consumer (E2), search summaries |
| Vendor and official docs | read | LocalStack licensing change (E3), SNS subscribe attributes (E5) |
| Live feasibility | read | Moto spike (E4) |
| Application repositories | not-applicable | The phase 2 record already surveyed queue implementations; the outbox here is a small, standard pattern |
| UI / product experience | searched-no-relevant-result | No product study for the analytics page; metrics follow the plan's goals |

## Limits

- E2, E3, and E5 were read as search summaries, not verbatim pages.
- Moto doesn't enforce IAM, KMS, or SQS throughput; phase 6 must re-run O6 on real AWS.
- The relay holds row locks across one SNS call; at higher volume, switch to the claim-with-lease variant in E2.
- Analytics reads events into memory for the window. That's fine for one center over 90 days, but would need SQL aggregation or the S3 export with Athena at scale.
- Review triggers: phase 6 deploy, a second consumer of the topic, event schema changes (add a version field then), or a center with more than a few thousand events per window.
