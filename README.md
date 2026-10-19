# Cubby

A preschool operations copilot. Center software usually records what happened; Cubby turns those records into a daily queue of proposed next actions (waitlist follow-ups, past-due tuition nudges, staffing ratio warnings). Plain Ruby rules find the work, Claude on AWS Bedrock drafts the message using the center's own policies, a director approves before anything goes out, parents see it in native iOS and Android apps, and an eval suite grades the drafts.

Personal project by [Doug Kvamme](https://dougkvamme.vercel.app), built to go deep on one production stack end to end.

## Stack

| Layer | Tech |
|---|---|
| API and jobs | Ruby on Rails 8.1 (API mode), Sidekiq + sidekiq-cron |
| Data | PostgreSQL 17 with pgvector, Redis |
| Director web app | React + TypeScript (Vite) |
| Parent apps | SwiftUI (iOS), Kotlin + Jetpack Compose (Android) |
| AI | Claude on AWS Bedrock, Titan embeddings, pgvector retrieval, tool-use agent, eval suite |
| Infra | Docker, Kubernetes on Amazon EKS, Terraform, GitHub Actions, FluxCD, RDS, ElastiCache, S3 + CloudFront, SNS/SQS, CloudWatch |

## Status

| Phase | Scope | State |
|---|---|---|
| 1 | Rails API, Sidekiq, Postgres, Redis, schema, seed data, RSpec, CI | Done |
| 2 | Detectors and the idempotent action queue | Next |
| 3 | React + TypeScript director app | Planned |
| 4 | Bedrock drafting, policy retrieval, agent, evals | Planned |
| 5 | Events: SNS to SQS to analytics | Planned |
| 6 | AWS via Terraform, EKS, FluxCD | Planned |
| 7 | iOS parent app | Planned |
| 8 | Android parent app | Planned |

The full plan is in [`docs/plans/2026-10-19-cubby-plan.md`](docs/plans/2026-10-19-cubby-plan.md).

## Run it locally

```bash
docker compose up --build
curl localhost:3000/api/v1/centers
```

That starts Postgres (host port 5433), Redis (6380), the API on port 3000, and a Sidekiq worker, then seeds **Little Oaks Early Learning**, a fictional center with four classrooms, about 55 families, a waitlist, six past-due invoices, and one classroom deliberately under ratio tomorrow. All seed dates are relative to today.

Without Docker for the app itself:

```bash
docker compose up -d db redis
cd api && bundle install && bin/rails db:prepare && bin/rails server
bundle exec rspec
```

## API (phase 1, read only)

| Endpoint | Returns |
|---|---|
| `GET /api/v1/centers/:id` | Center summary with enrolled, waitlisted, and past-due counts |
| `GET /api/v1/centers/:id/classrooms?on=YYYY-MM-DD` | Capacity, open seats, expected children, scheduled staff, and staff required by ratio |
| `GET /api/v1/centers/:id/enrollments?status=waitlisted` | Enrollments with child age and days on the waitlist |
| `GET /api/v1/centers/:id/invoices?status=past_due` | Invoices with days past due |

## Data rules enforced in the database, not just the model

- One active enrollment per child (partial unique index).
- An enrolled child must have a classroom; a paid invoice must have a paid date; classroom age ranges must be ordered (check constraints).
