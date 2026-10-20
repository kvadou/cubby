# Prior art: Cubby phase 2 action queue (detectors, ProposedAction, scan job)

Retrieved 2026-10-19. Research only; no code changed.

## Decision first

- **Recommendation:** ADAPT-PATTERNS, build in-repo. One `proposed_actions` table keyed by a detector-computed `dedupe_key`, a partial unique index on open rows, `insert_all(unique_by:)` from a per-center Sidekiq job fanned out by sidekiq-cron, Rails enum plus guarded conditional transitions (no state machine gem), an append-only transitions table, immutable `facts` jsonb, `snoozed_until` / `suppressed_until` cooldowns, and auto-resolve when a condition clears (D2 to D9, D15).
- **Evidence:** Discourse reopens one row per `(type, target_id)` under a UNIQUE index with an atomic UPDATE because a SELECT-then-INSERT "is not safe under concurrency" (E27). Rails 8.1 `insert_all` appends a partial index's WHERE to `ON CONFLICT` (E24), which PostgreSQL requires to infer a partial arbiter index (E25). Sidekiq is at-least-once (E21).
- **Limitation:** no surveyed child-care product documents automated waitlist follow-up or a past-due cadence beyond day 1 (E4, E5, E35), so the waitlist thresholds and the 7-day re-nudge are product proposals, not prior art. Ratio forecasting uses schedules without per-child hours (E1).
- **Next check:** write O1 and O2 (double scan and concurrent scan create one open row) against real PostgreSQL before any detector logic.

## Run header

- Outcome: foundation for phase 2 (detectors + `ScanCenterJob` + idempotent queue) that does not block phases 3 to 5. Mode greenfield. Profile Standard (about 15 searches/fetch groups, 6 deep reads, about 30 min).
- Known constraints (E1): Rails 8.1.4, Sidekiq 8, sidekiq-cron ~> 2.3 already wired, PostgreSQL 17, single seeded center in Minneapolis (America/Chicago), unauthenticated local API until phase 3, nothing sent without a human click, phase 4 Bedrock drafting with "only minimal facts leave the app", phase 5 SNS/SQS events.
- Assumptions: one center now, multiple later (phase 3 scoping). Fictional data. No real families contacted.
- Local-first: read the plan, handoff, `api/db/schema.rb`, all models, Gemfile, `config/sidekiq.yml`, seeds. No prior `docs/prior-art/` records existed. sidekiq-cron is already installed, so the scheduler question is KEEP vs replace.
- Readers: three bounded subagent reads (product docs, Sidekiq/Rails docs, Discourse/GitLab/Chatwoot code). Primary agent read MN rules directly and re-verified Discourse, GitLab, Chatwoot and Rails claims in the clones (`/tmp/prior-art/`). Nothing from clones was executed. WebFetch returns model summaries, so quotes from E2 to E14 and E18 to E23 are paraphrase-grade unless marked verbatim.

## Questions

| ID | Question | Needs | Status | Answer |
| --- | --- | --- | --- | --- |
| Q1 | How do child-care products surface waitlist follow-up, overdue tuition, ratio alerts (triggers, cadence, automated vs human)? | Help-center docs | partial | D10, D11, D12, D13. Past-due and ratio documented (E2, E3, E5, E6, E7); waitlist automation not found (E35); Procare, Kangarootime help centers failed (E11, E12) |
| Q2 | Minnesota 9503 ratios, group sizes, how ratio applies, mixed age; compare seeds | Official revisor text | answered | D14 (E15, E16, E17) |
| Q3 | Scheduler choice, per-tenant fan-out, idempotency, DB dedupe, races | Library docs, Sidekiq wiki, Rails/PG docs | answered | D1, D2, D15 |
| Q4 | Review-queue data model prior art (status, cooldowns, auto-resolve, history, uniqueness, facts) | Source code | answered | D3 to D8 |
| Q5 | Phase 2 decisions that constrain later phases (facts snapshot, outbox, edit-before-send, state machine gem) | Pattern docs, gem docs, our plan | answered | D4, D8, D9, D16 |

## Evidence register

| ID | Family | Authority | Source / revision / locator | Status | Establishes |
| --- | --- | --- | --- | --- | --- |
| E1 | Local project | source | `docs/plans/2026-10-19-cubby-plan.md`, `docs/plans/2026-10-19-handoff-after-phase-1.md`, `api/db/schema.rb` (version 2026_10_19_000008), `api/app/models/*.rb`, `api/db/seeds.rb:25-28` | read | Current model; plan's index is `(kind, subject_type, subject_id) WHERE status='proposed'`; `Classroom#expected_children_on` counts schedule days only; no center hours; seeds ratios 4/7/10/10, capacities 8/14/20/20 |
| E2 | Product docs | documentation | help.mybrightwheel.com/en/articles/12631477-send-payment-reminders | read | Automatic notices on invoice post, due, and past due "the morning after the due date"; manual reminder only when a past-due balance exists; preset text |
| E3 | Product docs | documentation | help.mybrightwheel.com/en/articles/5672333-charge-late-payment-fees | read | Opt-in auto late fees: grace days, flat fee, optional compounding, created nightly, no approval step, void/waive after |
| E4 | Product docs | documentation | help.mybrightwheel.com/en/articles/4000095-manage-program-waitlists | read | Waitlist add/move is manual by Admin/Manager; bulk or single message from Admissions; no automated aging or reminders described |
| E5 | Product docs | documentation | help.famly.co/en-us/articles/9732638-automatic-payment-reminders | read | Exactly two automatic reminders: due date (day 0) and day 1; then manual reminders from Debt report |
| E6 | Product docs | documentation | help.famly.co/en/articles/6673963-the-overview | read | Real-time ratio indicator "based on the age ranges of the children signed into each room"; separate forecast "required staff" graph from projected attendance |
| E7 | Product docs | documentation | help.tryplayground.com/en/articles/8017549-late-charges-for-overdue-payments | read | Beta auto late fees land in a "Fee approvals" queue where staff Charge/Edit/Forgive (human-gated); grace days counted from due date |
| E8 | Product marketing | secondary | procaresoftware.com/capabilities/monitor-staff-child-ratios/ | read | Claims real-time ratios and configurable "off ratio" alerts by room/day/time; no thresholds or recipients |
| E9 | Product marketing | secondary | procaresoftware.com/blog/how-to-set-and-actually-collect-late-payment-fees-at-your-daycare/ | read | Advice only: reminders 3-5 days before due, escalate second late payment with a director note; not a product spec |
| E10 | Product blog | secondary | lillio.com/blog/april-2020-product-update/ (2020) | read | "Out of Ratio Alerts" for Staff Management module, admin enters target ratios; real-time vs schedule unstated |
| E11 | Product docs | documentation | Procare help center (not located by search) | failed | Nothing; Procare past-due automation unverified |
| E12 | Product docs | documentation | help.kangarootime.com/hc/en-us/articles/43715463370132 | failed | HTTP 403; snippets only, not counted |
| E13 | Product docs | documentation | help.famly.co/en/articles/4912134 (debt collection) | failed | Cross-host redirect not followed; late-fee article not retrieved |
| E14 | Product marketing | secondary | tryplayground.com/g/attendance | failed | Only front matter returned; ratio-alert claims from snippets not counted |
| E15 | Standard / regulation | standard | Minn. R. 9503.0040 subp. 1-4, revisor.mn.gov/rules/9503.0040/ (published electronically 2007-10-08; history 13 SR 173; 18 SR 2748), raw HTML read verbatim | read | Ratios/group sizes: infant 1:4/8, toddler 1:7/14, preschooler 1:10/20, school-age 1:15/30; only teacher/assistant/aide working directly with children count; group size waived for meals, outdoors, naps; mixed groups use youngest child present, no infants mixed, 36-month max range; infant designation up to 18 mo by agreement; kindergarten attendee is school-age |
| E16 | Standard / regulation | standard | Minn. R. 9503.0005 subp. 2 (verbatim) | read | Infant 6 weeks to <16 mo; toddler 16 to <33 mo; preschooler 33 mo until first day of kindergarten; school-age per statute |
| E17 | Statute | standard | Minn. Stat. 245A.02 subd. 16 "[Renumbered 142B.01, subd 25]"; 142B.01 subd. 25 (2025 Statutes), verbatim | read | Center school-age child: sufficient age to have attended first day of kindergarten, or eligible within 4 months, and under 13 |
| E18 | Library docs | documentation | github.com/sidekiq-cron/sidekiq-cron README + CHANGELOG; rubygems.org/api/v1/versions/sidekiq-cron.json | read | MIT; Sidekiq 8 support since 2.2.0; latest 2.4.0 (2026-05-06, fixes UI XSS); Redis sorted set so "only the first process who asks can enqueue"; per-line timezone in cron string |
| E19 | Library docs | documentation | github.com/sidekiq-scheduler/sidekiq-scheduler README + CHANGELOG (6.0.2, 2026-04-17) | read | MIT; Sidekiq 8 from 6.0.0; README admits load/latency "can cause duplicate pushes"; schedule overwritten by last booted process |
| E20 | Library docs | documentation | github.com/sidekiq/sidekiq/wiki/Ent-Periodic-Jobs | read | Commercial; "only a single process creates jobs"; missed runs not backfilled; price not verified |
| E21 | Library docs | documentation | github.com/sidekiq/sidekiq/wiki/Best-Practices | read | "at least once, not exactly once"; jobs must be idempotent; simple JSON args |
| E22 | Library docs | documentation | github.com/sidekiq/sidekiq/wiki/Bulk-Queueing | read | `perform_bulk` (6.3+), batches of 1000, `Sidekiq::Job` only, not ActiveJob |
| E23 | Framework docs | documentation | api.rubyonrails.org/classes/ActiveRecord/Relation.html (`create_or_find_by`, `find_or_create_by`) | read | `find_or_create_by` not atomic; `create_or_find_by` needs a unique constraint, burns ids, find can raise RecordNotFound |
| E24 | Framework source | source | rails/rails tag v8.1.0 `activerecord/lib/active_record/insert_all.rb:270-277`, `connection_adapters/postgresql_adapter.rb:660-677` | read | `conflict_target` emits `(cols) WHERE <index.where>` when `unique_by` names a partial index; PG builds `ON CONFLICT ... DO NOTHING` with optional RETURNING; insert_all skips validations and callbacks |
| E25 | Database docs | documentation | postgresql.org/docs/current/sql-insert.html (PG 18), ON CONFLICT `index_predicate` | read | Partial unique index inference needs the predicate; example `ON CONFLICT (did) WHERE is_active DO NOTHING` |
| E26 | Framework docs | documentation | github.com/rails/solid_queue README | not-applicable | Recurring tasks exist but Solid Queue is a different backend from Sidekiq |
| E27 | Implementation | source | discourse/discourse @ 3f2bf92368c78a7fa9a755f3d046adf35dd4459b `app/models/reviewable.rb:39` (status enum), `:173-247` (`needs_review!` atomic UPDATE...RETURNING old status, reopen + `log_history(:transitioned)`), `:428-440` (`perform` in a transaction), `:979-1003` (version-guarded UPDATE), `:1278` UNIQUE `(type, target_id)`, `payload` json | read | One row per subject reopened rather than duplicated; DB unique index plus atomic upsert; optimistic version; facts in `payload` and per-score `reason`/`context` |
| E28 | Implementation | source | Discourse same SHA `app/models/reviewable_history.rb:1-30`, `reviewable_score.rb:9,44-91`, `reviewable_flagged_post.rb:234-256` | read | Append-only history (created, transitioned, edited, claimed, unclaimed) with status snapshot and actor; "ignore" defers without a snooze timestamp |
| E29 | Implementation | source | gitlab-org/gitlab @ 244dace0f7e0b3b513c4d2ecd56f11bc7c2f6b74 `app/models/todo.rb:101-102,136-146,242-243`, `app/services/todo_service.rb:15-21,45-46,241-260,348,412-422` | read | Two states pending/done; `resolved_by_action` records system vs user resolution; passive `snoozed_until` filtered at read time, cleared on resolve; app-level dedupe on pending rows only; auto-resolve on issue close/MR merge (`system_done`); 10-minute same-review window |
| E30 | Implementation | source | GitLab same SHA `db/structure.sql` todos indexes (subagent-reported lines 52219-52237) | failed | Claim "no unique index on todos" not reproduced: file absent from sparse checkout. Treated as unverified |
| E31 | Implementation | source | chatwoot/chatwoot @ 9e916a2d7a5ff39e999aa346506a15d9a36c9255 `app/models/conversation.rb:86,136-137,290-295` | read | enum open/resolved/pending/snoozed; `before_save` nulls `snoozed_until` unless snoozed; `status_changed_at` stamped; no transition guard |
| E32 | Pattern docs | documentation | microservices.io/patterns/data/transactional-outbox.html (Chris Richardson) | read | Outbox row in the same transaction; relay may publish more than once, consumers must be idempotent |
| E33 | Library docs | documentation | github.com/gocardless/statesman README (~> 13.0) | read | MIT; transitions table with `to_state`, `sort_key`, `most_recent`, `metadata`; DB indexes guard duplicate transitions |
| E34 | Library docs | documentation | github.com/aasm/aasm README | read | MIT; column state, guards, `requires_lock`, event `after_commit` only on bang methods, recommends `after_commit_everywhere` for nested transactions |
| E35 | Search | secondary | WebSearch + help-center browsing 2026-10-19 for automated waitlist follow-up and past-due cadence beyond day 1 in Brightwheel, Procare, Kangarootime, Playground, Lillio, Famly | searched-no-relevant-result | No documented automated waitlist follow-up or day 7/14/30 escalation in reachable docs; Procare/Kangarootime help gaps (E11, E12) limit this |
| E36 | Library docs | documentation | github.com/sidekiq/sidekiq/wiki/Iteration | read | `Sidekiq::IterableJob` (7.3+) resumable cursor; keep iterations under 25s; not needed at one-center scale |

## Decisions

| ID | Decision | Status | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| D1 | Scheduler gem / T3 | supported | E18, E19, E20, E26 | KEEP sidekiq-cron (MIT, Sidekiq 8, single-enqueuer via Redis sorted set); bump constraint to allow 2.4.0 (UI XSS fix) |
| D2 | DB-enforced dedupe / T2 | supported | E21, E23, E24, E25, E27 | Partial unique index on `(dedupe_key) WHERE status = 'proposed'`; write with `insert_all(..., unique_by: :one_open_action_per_key, returning: %w[id dedupe_key])`; never `find_or_create_by` |
| D3 | Dedupe key semantics / T2 | supported | E1, E27, E29 | `dedupe_key` = condition identity computed by the detector, not just `(kind, subject)`: ratio risk needs the date |
| D4 | Status model and transition enforcement / T2 | contested | E27, E29, E31, E33, E34 | `proposed -> approved / dismissed / resolved`; Rails enum + `lock_version` + conditional UPDATE in one `transition!` seam; no aasm/statesman |
| D5 | Snooze and dismiss cooldowns / T4 | supported | E27, E29, E31 | `snoozed_until` on open rows (passive, read-time filter); `suppressed_until` stamped on dismissed/approved rows and checked by detectors |
| D6 | Auto-resolve and supersede / T2 | supported | E27, E29 | Each scan resolves open rows of that detector not re-detected (`resolution: condition_cleared`); a changed facts digest supersedes |
| D7 | Audit history / T2 | supported | E28, E33 | Append-only `proposed_action_transitions` written in the same transaction as every status change |
| D8 | Facts snapshot / T2 | supported | E1, E27 | Immutable minimal `facts` jsonb + `facts_digest` + `detector_version`; never mutated after insert |
| D9 | Event publishing / T2 | supported | E32, E34 | Transactional outbox in phase 5, added inside the D4 `transition!` seam; no inline SNS publish |
| D10 | PastDueInvoice trigger / T4 | supported | E2, E3, E5, E7 | Trigger day 1 after `due_on` in center tz (matches E2/E5 timing), one action per family covering all its past-due invoices, human-approved |
| D11 | Past-due re-nudge cadence / T4 | unknown | E5, E9, E35 | Proposal only: 7 days after an approved nudge or a dismissal; revisit with director feedback |
| D12 | StaleWaitlist detector / T4 | not-found-in-surveyed-sources | E4, E35 | No product automates it; Cubby's differentiator. Proposed thresholds below, labeled proposals |
| D13 | RatioRisk detector method / T3 | supported | E6, E8, E10, E15, E16 | Forecast next operating day from schedules; required staff from MN category of youngest child present; count only teaching roles; also flag group size |
| D14 | Seeded MN ratios / T4 | supported | E15, E16, E17 | No ratio correction needed; add caveats on kindergarteners, director counting, group size, infant designation |
| D15 | Scan job structure / T3 | supported | E18, E21, E22, E36 | Cron dispatcher `perform_bulk([[center_id, as_of]])` to `ScanCenterJob` (`Sidekiq::Job`), per-center advisory lock, each detector in its own transaction |
| D16 | Tenancy column on queue / T1 | supported | E1, E29 | `center_id NOT NULL` FK on `proposed_actions` now, so phase 3 scoping is a WHERE, not a backfill |

### D2 / D3: uniqueness and dedupe key

- **Observed:** Discourse enforces one reviewable per `(type, target_id)` with a UNIQUE index (E27 `reviewable.rb:1278`) and explains that ActiveRecord's SELECT-before-INSERT "is not safe under concurrency" (E27 `:196-204`). GitLab dedupes against pending todos in application code only (E29 `todo_service.rb:412-422`); whether a DB constraint backs it is unverified (E30). Rails 8.1 emits `ON CONFLICT (cols) WHERE <predicate> DO NOTHING` for a named partial index (E24 `insert_all.rb:270-277`); PostgreSQL needs that predicate to infer a partial arbiter (E25). Sidekiq runs jobs at least once (E21).
- **Inferred:** the plan's index `(kind, subject_type, subject_id) WHERE status='proposed'` (E1) is right in shape but the wrong identity for RatioRisk: a Classroom has a separate risk per date, and yesterday's open row for today would block tomorrow's. A detector-built key handles all three kinds uniformly.
- **Recommendation:** `dedupe_key` examples: `stale_waitlist:enrollment:42`, `past_due:family:7`, `ratio_risk:classroom:3:2026-10-20`. Keep `kind`, `subject_type`, `subject_id` (subject: Enrollment, Family, Classroom) for joins and UI. Index: `add_index :proposed_actions, :dedupe_key, unique: true, where: "status = 'proposed'", name: :one_open_action_per_key`. Add a CHECK that `dedupe_key LIKE kind || ':%'`.
- **Verification:** O1, O2, O3.

### D4: statuses and transitions

- **Observed:** Discourse uses a plain enum with no transition guard but validates allowed actions and uses a version-guarded UPDATE (E27 `:419-440`, `:979-1003`). GitLab uses the state_machine gem for one event, but its undo path bypasses it with `update_all` (E29 `todo.rb:138-146`). Chatwoot allows every transition with no guard (E31). statesman gives a transitions table with DB-guarded `most_recent` (E33); aasm needs `after_commit_everywhere` care for nested transactions (E34).
- **Contested because:** a gem buys enforcement and history (statesman) but adds a second persistence model; mature apps mostly run without one and bypass it when they have one.
- **Recommendation:** statuses `proposed` (open), `approved`, `dismissed`, `resolved` (system: condition cleared, superseded, or expired). Legal moves: `proposed -> approved | dismissed | resolved`; `proposed` with `snoozed_until` stays `proposed`. Terminal states never reopen; a returning condition inserts a new row (GitLab behavior, E29), which keeps facts immutable (D8). Enforcement: `ProposedAction#transition!(to:, actor:, reason:, attrs: {})` runs `UPDATE ... SET status = :to, lock_version = lock_version + 1 WHERE id = :id AND status = 'proposed' AND lock_version = :v`, raises on 0 rows, and inserts the D7 transition row in the same transaction. Edit-before-send: approval stores `final_body` (phase 3/4) beside `draft_body`; editing is not a separate status, it is the approval payload, so evals can diff draft vs final. Sending/delivery state belongs to the phase 3/5 `Message`, not this enum. DB CHECK on the status list, matching the repo's existing style (E1).
- **Verification:** O4, O5.

### D5 / D6: cooldowns, auto-resolve, supersede

- **Observed:** GitLab snooze is a `snoozed_until` timestamp filtered at read time with no wake job, cleared on resolve (E29 `todo.rb:101-102`, `todo_service.rb:250,260,348`). Chatwoot enforces "snoozed_until only meaningful when snoozed" in `before_save` (E31 `:290-292`). GitLab auto-resolves todos when an issue closes or an MR merges and records `system_done` (E29 `:45-46`, `todo.rb:136`). Discourse has no snooze; re-detection reopens and rescores (E27, E28).
- **Recommendation:**
  - Snooze: `snoozed_until timestamptz` on open rows; inbox scope `proposed.where("snoozed_until IS NULL OR snoozed_until <= now()")`; cleared on any transition.
  - Dismiss cooldown: on dismiss/approve, stamp `suppressed_until` (per-kind default: stale_waitlist 14 days, past_due 7 days, ratio_risk end of that date). Detectors skip a candidate whose `dedupe_key` has any row with `suppressed_until > now()`. Index `(dedupe_key, suppressed_until)`.
  - Auto-resolve: after inserting, each detector resolves its open rows for the center whose keys were not produced this run (`resolution = 'condition_cleared'`, actor = system). RatioRisk rows for past dates resolve as `expired`.
  - Supersede: if a still-open row's `facts_digest` differs from the new candidate (amount changed, new invoice), resolve old with `superseded` and insert new, in one transaction.
- **Verification:** O6, O7, O8.

### D8 / D9: facts snapshot and outbox (constraints on phases 4 and 5)

- **Observed:** Discourse keeps detection-time facts in `payload` json and per-score `reason`/`context` (E27, E28). The outbox writes the message in the business transaction; the relay may publish more than once (E32).
- **Recommendation:** columns `facts jsonb NOT NULL`, `facts_digest text NOT NULL` (SHA-256 of canonical JSON), `detector_version integer NOT NULL`, `rationale text NOT NULL` (deterministic, rule-written). Facts are minimal and drafting-safe: guardian first name, child first name, amounts in cents, dates, days past due, classroom name, counts. No email/phone in facts (phase 4 says only minimal facts leave the app). Phase 4 adds `draft_body`, `final_body`, `model`, token/cost columns as nullable (cheap later). Phase 5 adds `outbox_events` inserted inside `transition!` and a relay job; consumers dedupe on event id. Do not publish to SNS from callbacks or inline.
- **Verification:** O9, O10.

### D10 to D13: detector thresholds (proposals unless cited)

- **PastDueInvoice (D10, D11):** candidate per family with any `Invoice.open` and `due_on < center.today` (fires the morning after due, matching E2; E5 sends day 0 and day 1 automatically). Facts: invoice numbers, amounts, due dates, total cents, max days past due. Re-nudge after 7 days via `suppressed_until` (proposal, E35 found no documented cadence). Paid or voided invoices drop out and the action auto-resolves.
- **StaleWaitlist (D12):** enrollment `waitlisted`; a classroom in the same center with `open_seats > 0` that `accepts_age?` the child's age on `max(today, requested_start_on)`; and `last_contacted_at` NULL or older than 14 days (proposal); and `requested_start_on` NULL or within 60 days (proposal). Order facts by `waitlisted_at` so the director sees FIFO position. Approval updates `last_contacted_at` (phase 3).
- **RatioRisk (D13):** for the next operating weekday in center tz: per classroom, expected children = enrolled with that weekday in `schedule_days`. Required staff = `ceil(children / r)` where `r` = the stricter of `classroom.ratio` and the MN ratio for the youngest child's age category on that date (E15 subp. 3B(3), E16). Available staff = minimum concurrent count of shifts whose staff role is `lead_teacher`, `assistant_teacher` or `floater` (director excluded unless assigned a shift: E15 subp. 2A counts only staff working directly with children) across the center's operating window, sampled every 15 minutes. Also flag `children > MN max group size` (E15 subp. 1, 2C). Requires adding `opens_at`/`closes_at` local times to `centers` (proposal; schema has none, E1). Limitation: no per-child drop-off/pick-up times, so this is a conservative full-day forecast; real-time check-in ratios (E6, E8) are out of scope for phase 2.

### D14: Minnesota ratios vs seeds

- **Observed (verbatim, E15 subp. 1):** Infant 1:4, max group 8; Toddler 1:7, 14; Preschooler 1:10, 20; School-age 1:15, 30. Categories (E16): infant 6 weeks to under 16 months; toddler 16 to under 33 months; preschooler 33 months until the first day of kindergarten. School-age (E17): attended first day of kindergarten or eligible within 4 months, under 13. A child attending kindergarten must be designated school-age (E15 subp. 4B). Mixed groups: ratio and group size of the youngest child present; infants not mixed; 36-month max range (E15 subp. 3B).
- **Comparison:** Acorns 6-16 mo 1:4 cap 8 matches infant. Saplings 16-33 mo 1:7 cap 14 matches toddler. Maples 33-48 mo 1:10 cap 20 matches preschooler. Oaks 48-72 mo 1:10 cap 20 is correct while any preschooler is present (youngest-present rule); a room of only kindergarten attendees could legally run 1:15/30, so 1:10 is conservative, not wrong. No ratio or capacity corrections needed.
- **Caveats to encode:** (a) ratio is by age category of children present, not room label; (b) directors count only when working directly with children; (c) group size limits are separate from ratio and waived at meals/outdoors/naps; (d) an infant designation may extend to 18 months by parent/teacher/director agreement (defer a per-child override); (e) the arrival/departure 25 percent rules (E15 subp. 2B, 3A) are ignored in phase 2. Cubby is not a compliance tool; label the alert "ratio risk", not "violation".

### D15: scan job structure

- `NightlyScanJob` (sidekiq-cron `config/schedule.yml`: `cron: "0 4 * * * America/Chicago"`) enqueues `ScanCenterJob.perform_bulk(Center.ids.map { [it, nil] })`. `ScanCenterJob#perform(center_id, as_of = nil)` derives `as_of ||= center.today` (center tz) so a test or on-demand run is deterministic. Use `Sidekiq::Job` (E22 `perform_bulk` is not ActiveJob). Per detector: one transaction with `pg_advisory_xact_lock(hashtext('scan:' || center_id || ':' || kind))`, then candidates, suppression filter, `insert_all` with RETURNING, transition rows for inserted ids, supersede, auto-resolve. Missed nights self-heal because detectors are state-based, not event-based (E20 notes missed runs are not backfilled). Retries are safe by D2.

## Obligations

| ID | Decision | Invariant | Required authority | Check | Verified authority | Result | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| O1 | D2 | Two sequential scans of the seeded center create zero new rows on the second run | integration | `api/spec/services/center_scan_spec.rb#is idempotent` | integration | pass: second scan created 0, refreshed 1; seeded center rescan created 0, refreshed 10 (2026-10-19, 58 examples, 0 failures) | closed |
| O2 | D2 | Two concurrent ScanCenterJob runs (threads, separate connections, real PG) leave exactly one open row per key | integration | `api/spec/services/center_scan_spec.rb#with concurrent scans` (4 threads, real PG, no transactional tests) | integration | pass, stable across 5 random-order runs (2026-10-19, 58 examples, 0 failures) | closed |
| O3 | D2 | The partial unique index rejects a second open row with the same key and allows one after the first is dismissed | integration | `api/spec/models/proposed_action_spec.rb#uniqueness (O3)` | integration | pass: RecordNotUnique on second open row; closed row may share key (2026-10-19, 58 examples, 0 failures) | closed |
| O4 | D4 | Only `proposed` can transition; approving a dismissed row or a stale `lock_version` raises and writes nothing | integration | `api/spec/models/proposed_action_spec.rb#transitions (O4, O5)` | integration | pass: closed row and stale lock_version both raise, no history written (2026-10-19, 58 examples, 0 failures) | closed |
| O5 | D7 | Every status change (insert, approve, dismiss, auto-resolve, supersede) writes exactly one transition row in the same transaction | integration | `api/spec/models/proposed_action_spec.rb#transitions` + `api/spec/services/center_scan_spec.rb` resolve/supersede history assertions + rollback spec | integration | pass: one row per insert, approve, dismiss, resolve, supersede; failure rolls back status (2026-10-19, 58 examples, 0 failures) | closed |
| O6 | D5 | A dismissed waitlist action does not reappear on the next scan, and does reappear after `suppressed_until` passes (travel_to) | integration | `api/spec/services/center_scan_spec.rb#respects the dismiss cooldown` + `api/spec/models/proposed_action_spec.rb#cooldowns (O6)` | integration | pass: suppressed at +3d, recreated at +8d (past-due 7d cooldown) (2026-10-19, 58 examples, 0 failures) | closed |
| O7 | D6 | Marking all of a family's past-due invoices paid resolves its open action as `condition_cleared` on the next scan | integration | `api/spec/services/center_scan_spec.rb#resolves an action when the invoice is paid` | integration | pass (2026-10-19, 58 examples, 0 failures) | closed |
| O8 | D6 | A new past-due invoice for a family with an open action supersedes it (old resolved `superseded`, new row with new digest) | integration | `api/spec/services/center_scan_spec.rb#supersedes an action when the facts change` | integration | pass; also observed live: 2 seeded waitlist rows superseded after the O11 age change (2026-10-19, 58 examples, 0 failures) | closed |
| O9 | D8 | `facts` and `facts_digest` cannot change after insert (model raises; spec tries update) and contain no email or phone keys | unit | `api/spec/models/proposed_action_spec.rb#facts snapshot (O9)` + `api/spec/services/detectors_spec.rb` facts key check | unit | pass: ReadonlyAttributeError on update; contact keys and embedded emails rejected (found and fixed an anchored-regex gap) (2026-10-19, 58 examples, 0 failures) | closed |
| O10 | D10 | Invoice due today is not flagged; due yesterday in America/Chicago is flagged even when UTC date differs | unit | `api/spec/services/detectors_spec.rb#uses the center's local date, not UTC` | unit | pass: 03:00 UTC Tue = Mon in Chicago, not flagged; 06:00 UTC flagged (2026-10-19, 58 examples, 0 failures) | closed |
| O11 | D12 | Waitlisted child is flagged only when an age-appropriate room has an open seat and last contact is older than 14 days; age computed on requested start | unit | `api/spec/services/detectors_spec.rb` StaleWaitlist examples | unit | pass: quiet, recent, no-room, too-far-out, full-room and age-at-requested-start cases (2026-10-19, 58 examples, 0 failures) | closed |
| O12 | D13 | Seeded Saplings is flagged for the next weekday; a director-only shift does not satisfy ratio; a weekend `as_of` scans Monday | integration | `api/spec/services/detectors_spec.rb#flags a room short on teaching staff and ignores the director` + `#looks at the next weekday`; seeded Saplings via `bin/rails cubby:scan` and the compose Sidekiq run | integration | pass: director shift not counted; Fri scans Mon; seeded Saplings flagged 1 of 2 staff for 11 children (2026-10-19, 58 examples, 0 failures) | closed |
| O13 | D13 | Required staff uses the stricter of room ratio and MN category of the youngest child (a 15-month-old in Saplings forces 1:4) and group size over MN max is flagged | unit | `api/spec/services/detectors_spec.rb#applies the youngest child's Minnesota ratio and group size` | unit | pass: one 14-month-old forces 1:4, 3 staff, group limit 8 exceeded (2026-10-19, 58 examples, 0 failures) | closed |
| O14 | D15 | Sidekiq cron schedule loads `NightlyScanJob` with America/Chicago and the dispatcher enqueues one job per center | unit | `api/spec/jobs/scan_jobs_spec.rb` + live compose run | integration | pass: one job per center; live Sidekiq registered nightly_scan 0 4 * * * America/Chicago and processed NightlyScanJob -> ScanCenterJob (2026-10-19, 58 examples, 0 failures) | closed |
| O15 | D16 | `proposed_actions.center_id` is NOT NULL and matches the subject's center (CHECK via detector + spec) | integration | `api/spec/services/center_scan_spec.rb#stamps the center that owns the subject`; center_id NOT NULL FK in migration | integration | pass (2026-10-19, 58 examples, 0 failures) | closed |

## Proposed phase 2 schema (foundation)

```ruby
create_table :proposed_actions do |t|
  t.references :center, null: false, foreign_key: true
  t.string  :kind, null: false            # stale_waitlist | past_due | ratio_risk
  t.string  :subject_type, null: false    # Enrollment | Family | Classroom
  t.bigint  :subject_id, null: false
  t.string  :dedupe_key, null: false
  t.string  :status, null: false, default: "proposed"  # proposed | approved | dismissed | resolved
  t.string  :resolution                   # condition_cleared | superseded | expired (system only)
  t.text    :rationale, null: false
  t.jsonb   :facts, null: false
  t.string  :facts_digest, null: false
  t.integer :detector_version, null: false
  t.date    :occurs_on                    # ratio_risk target date
  t.datetime :detected_at, null: false
  t.datetime :last_seen_at, null: false
  t.datetime :snoozed_until
  t.datetime :suppressed_until
  t.datetime :decided_at
  t.integer :lock_version, null: false, default: 0
  t.timestamps
end
add_index :proposed_actions, :dedupe_key, unique: true, where: "status = 'proposed'", name: :one_open_action_per_key
add_index :proposed_actions, %i[center_id status kind]
add_index :proposed_actions, %i[dedupe_key suppressed_until]
add_index :proposed_actions, %i[subject_type subject_id]
# CHECKs: status list; resolution only when status = 'resolved'; snoozed_until NULL unless status = 'proposed';
#         dedupe_key LIKE kind || ':%'

create_table :proposed_action_transitions do |t|
  t.references :proposed_action, null: false, foreign_key: true
  t.string :from_status          # NULL on create
  t.string :to_status, null: false
  t.string :actor_type, null: false   # system | director (phase 3 adds actor_id)
  t.string :reason
  t.jsonb  :metadata, null: false, default: {}
  t.datetime :created_at, null: false
end
```

Rejected: a state machine gem (D4); `find_or_create_by` (E23); unique on `(kind, subject)` without date (D3); reopening terminal rows in place, Discourse-style (conflicts with immutable facts, D8); publishing events from callbacks (D9); sidekiq-scheduler (E19 duplicate pushes) and Enterprise periodic (paid) (D1).

## Coverage

| Source family | Status | Notes |
| --- | --- | --- |
| Application repositories | read | Discourse, GitLab, Chatwoot at pinned SHAs (E27 to E31); history not inspected (depth-1 clones) |
| Official contracts / regulation | read | MN Rules 9503.0005, 9503.0040, Minn. Stat. 142B.01 (E15 to E17); PostgreSQL INSERT (E25) |
| Libraries and framework | read | sidekiq-cron, sidekiq-scheduler, Sidekiq wiki, Rails v8.1.0 source, statesman, aasm (E18 to E24, E33, E34, E36) |
| Product help centers | read / failed | Brightwheel, Famly, Playground read; Procare and Kangarootime help failed; Lillio only a 2020 blog (E2 to E14) |
| Issue/PR history and postmortems | searched-no-relevant-result | Not deepened; only in-code rationale comments (E27 `:196-204`, E29 `:15-17`). Shallow clones, so no causal history claimed |
| Pattern writeups | read | Transactional outbox (E32) |
| UI / product experience | not-applicable | Phase 2 is backend only; the inbox UI is phase 3 |
| AI / evals research | not-applicable | Phase 4 |

## Limits

- Product evidence is from WebFetch summaries of help articles, not verbatim; Procare, Kangarootime, Lillio billing/waitlist docs were not retrieved. Absence of waitlist automation is scoped non-discovery (E35), not proof.
- GitLab's lack of a DB unique constraint on todos is unverified (E30).
- `create_or_find_by` details (E23) and Sidekiq Enterprise cost were not checked against raw text.
- RatioRisk is a schedule forecast without per-child hours; MN arrival/departure provisions and staff qualification patterns (E15 subp. 2D) are out of scope.
- Review triggers: sidekiq-cron major release, Rails `insert_all` changes, a second center with a different timezone, MN rule amendment (DCYF rulemaking), or phase 3 director feedback on cooldown lengths.
