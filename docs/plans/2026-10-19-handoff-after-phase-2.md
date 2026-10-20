# Handoff after phase 2 (2026-10-19)

## Done
- `proposed_actions` + append-only `proposed_action_transitions` (migration `20261020000001`). Partial unique index `one_open_action_per_key` on `dedupe_key WHERE status = 'proposed'`; check constraints on kind, status, resolution.
- `ProposedAction#transition!`: guarded UPDATE on status + `lock_version`, history row in the same transaction. **This is the seam for the phase 5 outbox** (record D9). `approve!` stores `final_body` (edit-before-send) and sets `suppressed_until`.
- Detectors `StaleWaitlist`, `PastDueInvoice`, `RatioRisk` (+ `Ratios::Minnesota`), `CenterScan` reconciler, `ScanCenterJob`, `NightlyScanJob`, `config/schedule.yml` loaded on Sidekiq startup, `bin/rails cubby:scan`.
- Read-only `GET /api/v1/centers/:id/proposed_actions`.
- 58 RSpec examples incl. a real-Postgres concurrency test; prior-art record obligations O1-O15 closed. Record lint exit 2 only for honest gaps (Q1 partial, D11 cadence unknown).
- Verified live: seeded center yields 10 actions (5 past due, 1 ratio, 4 waitlist); rescan creates 0; compose Sidekiq ran NightlyScanJob -> ScanCenterJob.

## Gotchas
- `facts` is `attr_readonly`: Rails 8 raises `ReadonlyAttributeError` on update.
- insert_all skips validations; `CenterScan#row_for` calls `validate!` before building each row.
- The concurrency spec disables transactional tests and cleans up with `delete_all`.

## Next: phase 3
Auth first (deploy gate): director sessions for the web app, JWT for mobile, every query scoped to the signed-in user's center (replace `BaseController#current_center`). Then approve/edit/dismiss/snooze endpoints calling the `ProposedAction` methods, and the React + TypeScript director inbox (Vite) under `web/`. Consider running /prior-art for auth (Rails 8 authentication generator vs devise vs rodauth; JWT for native apps).
