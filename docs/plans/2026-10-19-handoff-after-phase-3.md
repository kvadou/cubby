# Handoff after phase 3 (2026-10-19)

**Repo:** github.com/kvadou/cubby. Plan: `docs/plans/2026-10-19-phase3-plan.md`. Decisions: `docs/prior-art/2026-10-19-phase3-auth.md` (O1 to O6 closed).

## Done
- **Auth** adapted from the Rails 8.1 generator: `users`, `sessions` (cookie or bearer, 30-day expiry, bearer stored as SHA-256 digest), `memberships` (director role). `Authentication`, `SameOriginRequests` (Sec-Fetch-Site / Origin CSRF guard), `LoginThrottle` (10 per IP and 5 per email per 3 min, shared by both sign-in endpoints) under `api/app/controllers/concerns/`.
- **Tenancy:** `current_center = Current.user.centers.find(...)`; centers index and show scoped too.
- **Decisions:** `POST .../proposed_actions/:id/approve|dismiss|snooze` with `lock_version`; 409 carries the current row. Family-facing kinds need a message body.
- **Web app** `web/`: React 19, TS strict, TanStack Query, React Router 7, Vite 8 proxy to :3000. Inbox grouped by kind with filters, review drawer with starter text (`web/src/present.ts`, deterministic, no model), mark handled, snooze menu, dismiss with reason, approved and dismissed lists, toasts, sign out. Verified in a real browser at 1280 and 375 px; screenshots in `~/.playwright-mcp/cubby/`.
- **Seeds:** `api/db/seeds/` (little_oaks, demo_users), development only. Second center Birchwood proves isolation.
- **Security review** (independent agent): no HIGH. Fixed dev-only seeds, session retirement on re-login, two 500s.
- **CI:** `api.yml` (rspec 103, rubocop, brakeman, bundler-audit) and new `web.yml` (typecheck, vitest, build, npm audit).

## Gotchas
- `rack-cors` is gone on purpose. Don't call the API cross-origin from a browser; serve the app same-origin.
- Test cache store is `:memory_store` (rate limits); `spec/support/auth.rb` clears it per request spec.
- Mobile token sign-in skips the origin check (no cookie set, response unreadable cross-site).

## Phase 6 deploy checklist
In `docs/plans/2026-10-19-phase3-plan.md`: trusted proxies for CloudFront, Redis cache store for rate limits, `APP_ORIGINS`, password change and sign-out-everywhere before real users.

## Next: phase 4
Re-test Bedrock invocation on the `cubby` profile first (blocked on account verification 10/19). Then `Drafting::Drafter` via Bedrock `converse` with a tool-forced schema, filling `draft_subject`/`draft_body` (the review drawer already shows `draft_body` when present, else the starter text), pgvector policy chunks, "Ask Cubby" read-only agent, `rake evals:drafts`.
