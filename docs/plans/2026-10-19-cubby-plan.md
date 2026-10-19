# Cubby: preschool ops copilot on Brightwheel's stack (personal project)

**Goal:** a real, deployed personal project built on the exact stack in Brightwheel's posting, so Doug can list Rails, Sidekiq, React+TS, native iOS and Android, EKS/FluxCD, and Bedrock as hands-on experience and walk through it in interviews. Every resume claim must be true of this repo, and each piece only goes on the resume once it is real.

**Pitch:** Center software that records what happened is table stakes. Cubby turns the records into a daily queue of proposed next actions (waitlist follow-ups, past-due tuition nudges, staffing ratio warnings). Plain Ruby rules find the work, Claude on Bedrock drafts the message using the center's own policies, a director approves before anything goes out, parents receive it in native apps, and an eval suite grades the drafts.

## Decisions (2026-10-19)
- Stack: everything in Brightwheel's posting.
- Infra: Terraform, spin up on demand for demos (~15 min), tear down after. Static React site stays live.
- Scope: core + AWS, iOS (Swift), Android (Kotlin).
- AWS: **personal account required.** The `doug` CLI profile is Story Time Chess's company account (727667355798) and must not be used. New profile `cubby`, set up by Doug.

## Architecture

```
React+TS (Vite) ──► CloudFront + S3           iOS (SwiftUI)   Android (Compose)
        │                                           │               │
        └──────────────► ALB ──► EKS ◄──────────────┴───────────────┘
                                 │  rails-api (Rails 8, JSON API, JWT for mobile, session for web)
                                 │  sidekiq   (detectors, drafting, nightly scan via sidekiq-cron)
                                 │  analytics-consumer (SQS → events table + S3 parquet/json)
                                 ▼
          RDS Postgres (+pgvector)   ElastiCache Redis   SNS ─► SQS   S3   Bedrock (Claude, Titan embeddings)
          CloudWatch: logs (Fluent Bit), metrics, alarms → SNS email
GitHub Actions: test → build → push ECR → bump image tag in gitops repo path → FluxCD reconciles
```

## Data model (Rails)
`Center, Classroom(capacity, ratio, age range), Family, Guardian(User), Child, Enrollment(waitlisted|enrolled|withdrawn), StaffMember, StaffShift, Invoice, Attendance, DailyReport, ProposedAction(kind, polymorphic subject, status, rationale, facts jsonb, draft, edited_body, model, tokens, cost), Message(to family, delivered via app + push), PolicyDoc + PolicyChunk(embedding vector(1024)), DomainEvent, EvalRun`

Idempotency for the queue:
```ruby
add_index :proposed_actions, %i[kind subject_type subject_id],
          unique: true, where: "status = 'proposed'", name: "one_open_action_per_subject"
```

## AI on Bedrock
- **Drafting:** `Drafting::Drafter` calls Claude via `Aws::BedrockRuntime::Client#converse` with a tool-forced JSON schema (subject, body, facts_used, policy_citations). Only minimal facts leave the app.
- **Retrieval:** the center's handbook (late pickup fees, tuition policy, illness policy) is chunked and embedded with Titan Embeddings into pgvector. Drafts cite the policy they rely on.
- **Agent:** "Ask Cubby" for directors: a tool-use loop with read-only tools (`find_children`, `invoices_for_family`, `classroom_ratio`, `search_policies`). No write tools.
- **Evals:** `rake evals:drafts` runs golden cases. Deterministic checks first (right amount and date, no facts outside the payload, policy cited when a fee is mentioned, length), then a Claude judge on tone. Runs in CI on recorded responses, live on demand.
- **Guardrails:** nothing reaches a family without a human click; payload logged per action; AI failure leaves "draft unavailable, write your own".

## Events and analytics
Rails publishes domain events (`action.proposed`, `action.approved`, `invoice.paid`, `child.checked_in`) to SNS. SQS fans out to an analytics consumer that writes a `domain_events` table and daily JSON to S3. A small `/analytics` React page shows the approval funnel, time-to-decision, and AI cost per approved message.

## Mobile (parent apps, same API)
- **iOS (SwiftUI):** sign in, child's day (check-in/out, daily report), messages from the center, invoices. Push via SNS mobile push to APNs is a stretch goal (needs an Apple developer account).
- **Android (Kotlin + Jetpack Compose):** same screens, Retrofit + Kotlin coroutines, Material 3.
- Demo: simulator/emulator recordings and screenshots for the portfolio; not published to app stores.

## Phases (each done and verified before the next)

| # | Phase | Done when |
|---|---|---|
| 1 | Rails API + Sidekiq + Postgres + Redis in Docker Compose, schema, realistic seeds, RSpec, GitHub Actions CI | `docker compose up` gives a seeded center; CI green |
| 2 | Detectors + `ScanCenterJob`, idempotent queue | Specs cover each rule; double scan creates no duplicates |
| 3 | Auth (director sessions for web, JWT for mobile), every query scoped to the signed-in user's center; React + TypeScript director app: inbox, approve/edit/dismiss, outbox | Request specs prove one center can't read another's data; full loop in browser, desktop and phone widths |
| 4 | Bedrock drafting, pgvector policy retrieval, "Ask Cubby" agent, evals | Drafts cite policies; eval score prints and shows in UI |
| 5 | Events: SNS → SQS → analytics consumer, `/analytics` page (LocalStack locally) | Approving an action shows up in analytics |
| 6 | AWS via Terraform: VPC, EKS, RDS, ElastiCache, ECR, S3+CloudFront, SNS/SQS, IAM (IRSA for Bedrock), CloudWatch; FluxCD GitOps; `make up` / `make down` | Live demo URL works end to end; teardown leaves only S3/CloudFront/ECR/state |
| 7 | iOS parent app (SwiftUI) | Runs in simulator against the live or local API; screenshots |
| 8 | Android parent app (Kotlin, Compose) | Runs in emulator; screenshots |
| 9 | README with architecture diagram, portfolio case study, resume line | pw-verify clean, case study live |

**Deploy gate:** nothing is deployed (phase 6) until phase 3 auth and center scoping are in place. Phase 1 and 2 APIs are unauthenticated on purpose, local only, fictional data.

## Cost (on-demand mode)
Running: about $5 to $6 a day (EKS control plane, two small Graviton nodes, db.t4g.micro RDS, cache.t4g.micro, ALB, minimal NAT). Idle: S3, CloudFront, ECR, Terraform state, and RDS snapshots, roughly $2 to $5 a month. Bedrock usage is cents. An AWS Budgets alarm at $50/month is created in phase 6.

## Tooling to install (Homebrew unless noted)
terraform, fluxcd/tap/flux, helm, eksctl, awscli (present), LocalStack (Docker image), Temurin JDK 21, Android Studio (cask, multi-GB), Rails gem for Homebrew Ruby 4.0. Xcode and Docker are already installed.

## Resume line (added piece by piece, only once live)
**Cubby (personal project):** preschool operations copilot on Rails 8 and Sidekiq with a React + TypeScript director app and native SwiftUI and Jetpack Compose parent apps. Claude on AWS Bedrock drafts family messages grounded in center policies via pgvector, a director approves every send, and an eval suite grades drafts in CI. Deployed to EKS with Terraform, GitHub Actions, and FluxCD; events flow through SNS/SQS into an analytics pipeline.
