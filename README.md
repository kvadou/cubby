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
| 2 | Detectors and the idempotent action queue | Done |
| 3 | Auth, center scoping, React + TypeScript director app | Done |
| 4 | Bedrock drafting, policy retrieval, agent, evals | Next |
| 5 | Events: SNS to SQS to analytics | Planned |
| 6 | AWS via Terraform, EKS, FluxCD | Planned |
| 7 | iOS parent app | Planned |
| 8 | Android parent app | Planned |

The full plan is in [`docs/plans/2026-10-19-cubby-plan.md`](docs/plans/2026-10-19-cubby-plan.md).

## Run it locally

```bash
docker compose up --build          # Postgres (5433), Redis (6380), API (3000), Sidekiq
cd web && npm install && npm run dev   # director app on http://localhost:5173
```

Compose seeds **Little Oaks Early Learning**, a fictional center with four classrooms, about 55 families, a waitlist, six past-due invoices, and one classroom deliberately under ratio tomorrow (all dates relative to today), plus a second center, **Birchwood Kids Club**, so tenancy is visible. Sign in as `renee@littleoaks.test` (Little Oaks) or `marcus@birchwood.test` (Birchwood); the local demo password is in `api/db/seeds/demo_users.rb`, and the sign-in page has a "fill in the demo director" link in development. Demo users are only ever seeded in development.

Without Docker for the app itself:

```bash
docker compose up -d db redis
cd api && bundle install && bin/rails db:prepare && bin/rails server
bundle exec rspec
```

## Director app (phase 3)

React 19 + TypeScript (strict) with TanStack Query and React Router, in `web/`. The inbox groups the day's proposed actions by type (staffing, tuition, waitlist) with the facts behind each one. A director can:

- **Review message**: opens a drawer (a bottom sheet on phones) with starting text built from the action's facts, editable before approval. Phase 4 replaces the starting text with a Claude draft grounded in the center's policies.
- **Mark handled** for staffing warnings, **Snooze** (tomorrow, 3 days, next Monday), or **Dismiss** with a reason.
- See **Approved** and **Dismissed** lists with who decided and when.

Custom dialogs only (no browser `alert`/`confirm`), focus trapped and restored, Escape to close, keyboard-navigable menus, labelled controls, reduced-motion support. Checked in a real browser at 1280 px and 375 px.

## API

Every endpoint except sign-in needs a session, and every center endpoint is scoped to the signed-in director's centers: another center's data is a 404. Design and evidence: [`docs/prior-art/2026-10-19-phase3-auth.md`](docs/prior-art/2026-10-19-phase3-auth.md).

| Endpoint | Returns |
|---|---|
| `POST /api/v1/session` / `DELETE` | Web sign-in and sign-out (signed, httpOnly, SameSite=Lax cookie) |
| `POST /api/v1/tokens` / `DELETE /api/v1/tokens/current` | Mobile sign-in: an opaque bearer token, shown once and stored only as a SHA-256 digest |
| `GET /api/v1/me` | The director and their centers |
| `GET /api/v1/centers/:id` | Center summary with enrolled, waitlisted, and past-due counts |
| `GET /api/v1/centers/:id/classrooms?on=YYYY-MM-DD` | Capacity, open seats, expected children, scheduled staff, and staff required by ratio |
| `GET /api/v1/centers/:id/enrollments?status=waitlisted` | Enrollments with child age and days on the waitlist |
| `GET /api/v1/centers/:id/invoices?status=past_due` | Invoices with days past due |
| `GET /api/v1/centers/:id/proposed_actions?status=inbox\|approved\|dismissed` | The queue (inbox hides snoozed and closed actions) |
| `POST /api/v1/centers/:id/proposed_actions/:id/approve\|dismiss\|snooze` | Decisions; send the `lock_version` you saw, and a stale one returns 409 with the current row |

**Security model.** Cookie-authenticated writes must come from the app's own origin (`Sec-Fetch-Site: same-origin`, or a trusted `Origin` from older browsers), modeled on Rails 8.2's header-based CSRF protection; bearer requests are exempt because browsers never attach them on their own. Sign-in is rate limited per IP and per email across both endpoints. The web app is served from the same origin as the API (Vite proxy locally, CloudFront path routing in AWS), so there is no CORS.

## How the action queue works (phase 2)

Design decisions and their evidence are in [`docs/prior-art/2026-10-19-phase2-action-queue.md`](docs/prior-art/2026-10-19-phase2-action-queue.md).

- **Detectors** (plain Ruby, `api/app/services/detectors/`) return candidates with a minimal facts snapshot:
  - `StaleWaitlist`: an age-appropriate room has an open seat (age at the requested start date), the family has gone 14+ days without contact, and the start date is within 60 days.
  - `PastDueInvoice`: one action per family covering every open invoice due before today in the center's time zone.
  - `RatioRisk`: next weekday, teaching staff scheduled vs. children scheduled, using the stricter of the room ratio and the Minnesota ratio for the youngest child (Minn. R. 9503.0040), plus the Minnesota group size limit. Directors don't count toward ratio.
- **`CenterScan`** reconciles the queue: inserts new conditions, refreshes unchanged ones, supersedes changed ones, resolves cleared ones, and skips keys still cooling down after a dismissal or approval. A per-center advisory lock serializes scans; a partial unique index (`one open action per dedupe_key`) with `insert_all(unique_by:)` is the backstop.
- **Transitions** (`proposed -> approved | dismissed | resolved`) go through one guarded UPDATE with `lock_version`, writing an append-only history row in the same transaction. Closed actions are never reopened.
- **Sidekiq**: `NightlyScanJob` runs at 4:00 AM Central via sidekiq-cron and fans out one `ScanCenterJob` per center. `bin/rails cubby:scan` runs a scan inline.

## Data rules enforced in the database, not just the model

- One active enrollment per child (partial unique index).
- One open action per dedupe key (partial unique index); a resolution only on resolved actions.
- An enrolled child must have a classroom; a paid invoice must have a paid date; classroom age ranges must be ordered (check constraints).
