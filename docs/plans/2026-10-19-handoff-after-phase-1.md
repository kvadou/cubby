# Handoff after phase 1 (2026-10-19)

**Repo:** github.com/kvadou/cubby (public), local `~/Projects/cubby`. CI (`.github/workflows/api.yml`) green on `8df8d26`.

## Done
- Rails 8.1.4 API (Homebrew Ruby 4.0.1: `export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"`), Sidekiq 8 + sidekiq-cron wired (`config/initializers/sidekiq.rb`, `config/sidekiq.yml`), ActiveJob adapter = sidekiq.
- Domain: Center, Classroom, Family, Child, Enrollment (waitlisted/enrolled/withdrawn, schedule_days array), StaffMember, StaffShift, Invoice, Attendance. DB constraints: one active enrollment per child (partial unique), enrolled needs classroom, paid needs paid_at, ordered age range.
- Seeds (`api/db/seeds.rb`): Little Oaks Early Learning, relative dates, idempotent, never runs in test. Saplings is under ratio on the next weekday; Saplings and Maples have open seats; 6 past-due invoices.
- Read-only API under `/api/v1/centers/:id/...` (classrooms, enrollments, invoices). 24 RSpec examples, rubocop and brakeman clean.
- `docker compose up --build`: Postgres pgvector pg17 on host 5433, Redis on 6380, API on 3000, Sidekiq worker.

## Gotchas
- Sandbox write rules are case sensitive: `~/Projects/cubby` needs unsandboxed git, bundle, and docker commands.
- `db:prepare` seeds a newly created DB. CI uses `db:create db:schema:load`.
- The API is unauthenticated on purpose (local, fictional data). Auth and center scoping are a phase 3 gate before any deploy.

## AWS
- Personal account 731956852586, CLI profile `cubby` (IAM user `cubby-cli`, AdministratorAccess for now). Never use the `doug` profile: that is Story Time Chess's company account.
- Bedrock lists Claude models (`us.anthropic.claude-haiku-5-5`, `us.anthropic.claude-sonnet-5-5`) but invocation returned "account is being verified" on 2026-10-19. Re-test before phase 4.

## Next: phase 2
`ProposedAction` model + partial unique index (one open action per kind and subject), detectors `StaleWaitlist`, `PastDueInvoice`, `RatioRisk` under `app/services/detectors/`, `ScanCenterJob` (Sidekiq, nightly via sidekiq-cron, plus on demand), specs for each rule's edge cases and for idempotency (double scan creates no duplicates). Read endpoints for actions.
