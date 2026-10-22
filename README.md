# Cubby

A preschool operations copilot. Center software usually records what happened; Cubby turns those records into a daily queue of proposed next actions (waitlist follow-ups, past-due tuition nudges, staffing ratio warnings). Plain Ruby rules find the work, Claude drafts the message using the center's own policies, a director approves before anything goes out, parents see it in native iOS and Android apps, and an eval suite grades the drafts.

Personal project by [Doug Kvamme](https://dougkvamme.vercel.app), built to go deep on one production stack end to end.

**Try it:** [drpv8p7ep5jv3.cloudfront.net](https://drpv8p7ep5jv3.cloudfront.net). "Try the demo" signs you in as a fictional center director, no password needed. The data is fictional and resets every night. Screenshots of the iPhone and Android parent apps are at [/apps](https://drpv8p7ep5jv3.cloudfront.net/apps).

## Stack

| Layer | Tech |
|---|---|
| API and jobs | Ruby on Rails 8.1 (API mode), Sidekiq + sidekiq-cron |
| Data | PostgreSQL 17 with pgvector, Redis |
| Director web app | React + TypeScript (Vite) |
| Parent apps | SwiftUI (iOS), Kotlin + Jetpack Compose (Android) |
| AI | Claude on AWS Bedrock or the Anthropic API (one Converse-shaped client), Titan embeddings with pgvector or Postgres full-text retrieval, tool-use agent, eval suite |
| Infra | Docker, Kubernetes on Amazon EKS, Terraform, GitHub Actions, FluxCD, RDS, ElastiCache, S3 + CloudFront, SNS/SQS, CloudWatch |

## Status

| Phase | Scope | State |
|---|---|---|
| 1 | Rails API, Sidekiq, Postgres, Redis, schema, seed data, RSpec, CI | Done |
| 2 | Detectors and the idempotent action queue | Done |
| 3 | Auth, center scoping, React + TypeScript director app | Done |
| 4 | Drafting, policy retrieval, agent, evals | Live on the demo through the Anthropic API (Haiku 5.5 drafts, Sonnet 5.5 agent and judge); the Bedrock path is built and waiting on account access |
| 5 | Events: SNS to SQS to analytics | Done |
| 6 | AWS via Terraform, EKS, FluxCD | Done; runs on demand |
| 7 | iOS parent app (SwiftUI) | Done; runs in the simulator |
| 8 | Android parent app (Kotlin, Jetpack Compose) | Done; runs in the emulator |
| - | Always-on public demo with one-click sign-in | Done |

The full plan is in [`docs/plans/2026-10-19-cubby-plan.md`](docs/plans/2026-10-19-cubby-plan.md).

## Run it locally

```bash
docker compose up --build          # Postgres (5433), Redis (6380), API (3000), Sidekiq, Moto (5055), events consumer
cd web && npm install && npm run dev   # director app on http://localhost:5173
```

Compose seeds **Little Oaks Early Learning**, a fictional center with four classrooms, about 55 families, a waitlist, six past-due invoices, and one classroom deliberately under ratio tomorrow (all dates relative to today), plus a second center, **Birchwood Kids Club**, so tenancy is visible. Sign in as `renee@littleoaks.test` (Little Oaks) or `marcus@birchwood.test` (Birchwood); the local demo password is in `api/db/seeds/demo_users.rb`. The sign-in page's "Try the demo" button signs in as Renee with no password, locally and on the deployed demo. Demo users are only ever seeded in development.

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

## Deploy (phase 6)

There are two ways to run it on AWS, and CloudFront sends `/api/*` to whichever is up (the cluster wins):

- **Always-on demo (`make demo`, about $18 a month):** one t4g.small instance runs Postgres, Valkey, the API, Sidekiq and the events consumer under Docker Compose, behind the same CloudFront distribution through a VPC origin. Only CloudFront's VPC-origin security group can reach it; there's no SSH (Session Manager instead), and Postgres and Valkey are on an internal Docker network with no way out. Every 5 minutes it deploys the image tag CI committed to `deploy/production`, the same GitOps source Flux reads. A nightly job rebuilds the fictional data. Details: [`docs/plans/2026-10-20-demo-host-plan.md`](docs/plans/2026-10-20-demo-host-plan.md).
- **The full EKS stack (`make up` / `make down`, about $5 a day while up):** what's described below.

The EKS stack runs on demand: about $5 a day while up, a few cents a month while down. Details and decisions: [`docs/plans/2026-10-19-phase6-plan.md`](docs/plans/2026-10-19-phase6-plan.md), [`docs/prior-art/2026-10-19-phase6-deploy.md`](docs/prior-art/2026-10-19-phase6-deploy.md).

- **Edge:**
  - CloudFront serves the React build from S3.
  - It sends `/api/*` through a VPC origin to an internal load balancer. That load balancer has no public address, and only CloudFront can reach it.
- **Cluster:**
  - EKS 1.37 on two Graviton nodes, running the API, Sidekiq and the analytics consumer.
  - Postgres 17 (RDS) and Valkey 8 sit in private subnets.
  - SNS and SQS policies allow only the worker to publish and only the topic to deliver.
- **Access:** each workload has its own IAM role through EKS Pod Identity.
- **Delivery:**
  - CI builds an arm64 image, pushes it to ECR and commits the new tag to `deploy/production`.
  - Flux applies it.
  - The web app goes to S3 with a CloudFront refresh.

```bash
make bootstrap   # once: Terraform state bucket
make base        # persistent pieces (registry, site, budget, CI role)
make demo        # always-on demo host, about 10 minutes (first boot seeds itself)
make up          # cluster, about 25 minutes
make down        # cluster gone; the site goes back to the demo host (or says it's offline)
make demo-down   # demo host gone
```

Each apply shows its plan and asks before changing anything. Everything runs as the `cubby` AWS profile, and the providers refuse any other account. Visitors use the one-click demo; for a typed sign-in, the password is generated per stack: `terraform -chdir=infra/terraform/demo output -raw demo_password` (or `cluster`).

## Parent app for iOS (phase 7)

A SwiftUI app for parents, in `ios/`: iOS 18+, Swift 6 strict concurrency, with the project generated from `project.yml` by XcodeGen. It has three tabs:
- **Today:** whether each child is checked in, plus two weeks of attendance in the center's time zone.
- **Messages:** what the center sent, with unread state.
- **Billing:** what's due first, then paid invoices.

When a director approves a family message in the web app, it lands in that family's Messages tab, written in the same transaction as the approval. The app signs in with a bearer token kept in the Keychain. On the API side, parents are scoped to their own family the way directors are scoped to their centers, so neither can see the other's endpoints.

```bash
brew install xcodegen
cd ios && xcodegen generate && open Cubby.xcodeproj   # run on an iPhone simulator, API on localhost:3000
```

Sign in as `parent@littleoaks.test` with the local demo password. The UI test (`CubbyUITests`) signs in, walks every tab and saves screenshots; it needs `docker compose up`. CI runs the client tests on a macOS runner.

## Parent app for Android (phase 8)

The same three tabs in Kotlin and Jetpack Compose (Material 3), in `android/`: Android 10+, with OkHttp and kotlinx.serialization against the same family endpoints. The bearer token is encrypted with an AES key held in the Android Keystore, and backups are off. Debug builds talk to the Mac's `localhost:3000` through the emulator's `10.0.2.2` (cleartext allowed for that host only, debug only); release builds use the CloudFront URL.

```bash
brew install openjdk@21 && brew install --cask android-commandlinetools   # then sdkmanager for platform 37 and an emulator image
cd android && ./gradlew testDebugUnitTest assembleDebug
./gradlew connectedDebugAndroidTest   # with an emulator running and `docker compose up`
```

`ParentFlowTest` signs in as `parent@littleoaks.test`, walks every tab, saves screenshots to `/data/local/tmp/cubby-screenshots` on the emulator, and signs out. CI runs the unit tests, lint and a release build.

## Events and analytics (phase 5)

Design and evidence: [`docs/prior-art/2026-10-19-phase5-events.md`](docs/prior-art/2026-10-19-phase5-events.md).

```
approve / dismiss / snooze / scan / draft
        │ same transaction
        ▼
  outbox_events ──PublishOutboxJob──► SNS topic ──raw delivery──► SQS queue (+ DLQ) ──consumer──► domain_events ──► /analytics
                  (SKIP LOCKED, batches of 10)                                     (dedupe on event_id)    └─► S3 JSON lines, nightly
```

- **Transactional outbox:** every change to an action writes an event row in the same transaction, so an event exists if and only if the change committed. A post-commit kick publishes it within a second; a one-minute cron job is the backstop.
- **At-least-once, deduplicated:** the relay marks rows published only after SNS accepts them, and the consumer stores each `event_id` once, so a crash anywhere means a duplicate delivery, never a lost or double-counted event. Unreadable messages go to a dead-letter queue.
- **No personal data in events:** ids, kinds, timings, decision categories, and AI costs only; the model refuses name, body, note, and contact fields.
- **Analytics page:** decisions, approval rate, median time to decision, how approved messages were written (Claude's draft as is, edited, or without a draft), AI cost per approved message, decisions per day, and pipeline lag, all from delivered events.
- **Local AWS:** Moto (SNS, SQS, S3) runs in compose and as a CI service, so the pipeline spec runs end to end on every push. Outside production, events only ever go to an explicit local endpoint.

## AI (phase 4)

Design and evidence: [`docs/prior-art/2026-10-19-phase4-ai.md`](docs/prior-art/2026-10-19-phase4-ai.md).

- **Provider** (`api/app/services/ai/`): `AI_PROVIDER=anthropic` swaps the Bedrock client for `Ai::AnthropicConverse`, which answers the same Converse calls from the Anthropic API, so the drafter, judge, and agent don't change. A forced tool call becomes a structured output (current Sonnet models reject forced `tool_choice`), and handbook search falls back to Postgres full text because there is no embedding model. Locally: export `CUBBY_ANTHROPIC_API_KEY` before `docker compose up`. On the demo host: `bin/set-anthropic-key`.
- **Drafting** (`api/app/services/drafting/`): after each scan, a Sidekiq job drafts a message for every new family-facing action. Claude on Bedrock (Haiku 4.5 by default, set by `BEDROCK_DRAFT_MODEL`) receives only the action's facts snapshot (never contact details) and the most relevant sections of the center's handbook, and must answer through a forced `submit_draft` tool call with a subject, body, and policy citations.
- **Checks before a director sees it** (`Drafting::Checks`): the balance is stated, every dollar amount comes from the facts or a cited policy, any fee is backed by a cited policy, the greeting and sign-off are right, there are no contact details, markdown, or placeholders, and the length is sane. A failing draft gets one retry with the failures as feedback; if it still fails, the director gets plain starting text instead. Background draft writes never bump `lock_version`, so a director mid-review is never interrupted.
- **Retrieval** (`api/app/services/policies/`): the handbook is split into one chunk per section, embedded with Titan Text Embeddings V2 (1024 dimensions) and searched by cosine distance in pgvector (HNSW), always within one center.
- **Ask Cubby** (`api/app/services/agent/`): a director's question answered by Claude with five read-only, center-scoped tools (find a family, staffing by date, waitlist, handbook search, the queue), at most six turns, with every tool call shown in the UI. It cannot change or send anything.
- **Evals** (`bin/rails evals:drafts`): nine golden cases, including one with an instruction planted in the facts, run through the real prompt, checks, and retry path, then graded for tone and clarity by a different model. Responses are recorded so CI can grade without AWS; `EVALS_LIVE=1` re-records. The latest score appears in the review drawer.

To run AI features locally, give the containers the `cubby` profile's credentials with `bin/aws-env` (writes a gitignored `.env.aws`), then `docker compose up -d api sidekiq` and `docker compose exec api bin/rails cubby:policies:index`.

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
