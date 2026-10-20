# Handoff after phase 4 (2026-10-19)

**Repo:** github.com/kvadou/cubby. Decisions: `docs/prior-art/2026-10-19-phase4-ai.md` (O1 to O6 closed, O7 to O9 open on AWS access).

## Done
- Bedrock wrapper `api/app/services/ai/bedrock.rb`: forced-tool `structured`, Titan `embed`, cost in micro-dollars, models from `BEDROCK_{DRAFT,AGENT,JUDGE,EMBED}_MODEL`.
- Handbook `api/db/seeds/policies/little_oaks_family_handbook.md` (fictional, 11 sections) to `policy_documents` / `policy_chunks` (vector(1024), HNSW cosine) via `Policies::Indexer` and `IndexPolicyDocumentJob`.
- Drafting: `Drafting::Prompt` (pure), `Drafting::Checks` (deterministic gate), `Drafting::Drafter` (one feedback retry, stores status, citations, tokens, cost), `DraftActionJob`, `Drafting::Enqueue` after every scan (`CUBBY_AI_DRAFTS`, off in tests).
- `ProposedAction.update_quietly`: Rails 8 `update_all` bumps `lock_version` under optimistic locking; background writes now don't. Regression assertions in enqueue and scan specs.
- Ask Cubby: `Agent::AskCubby` + `Agent::Tools`, `POST /api/v1/centers/:id/ask` (20 per 10 min per user, 503 when AI is unavailable).
- Evals: `api/evals/drafts/cases.yml` (9 cases), `Evals::DraftSuite`, `Evals::Recorder`, `Evals::Judge`, `bin/rails evals:drafts`, `GET /api/v1/evals/latest`.
- Web: draft pill on cards ("Drafting…", "Draft ready", polls while pending), review drawer shows Claude's draft with "Based on" citations and the latest eval score, Ask Cubby drawer with suggested questions and visible tool steps. Browser-checked: unavailable path, no-draft path, and the ready state (using a placeholder row that was reverted).
- 135 API specs, 7 web tests, rubocop and brakeman clean.

## Blocked: AWS Bedrock access on account 731956852586
During the session the account went from answering Claude 4.5 calls, to "Model use case details have not been submitted", to "Error 002: Access to Bedrock models is not allowed for this account" for Claude and Titan alike. Doug's steps:
1. AWS console (cubby account, us-east-1) > Amazon Bedrock > Model catalog > Claude Haiku 4.5 > submit the Anthropic use case form if it's offered.
2. If Error 002 persists after that, open an AWS Support case (Account and billing) asking to enable Bedrock model access on a new account.
3. `! bin/aws-env`, then tell Claude to resume.

## Resume checklist (when access works)
1. `aws bedrock-runtime converse --profile cubby ...` smoke test (see the record's E7).
2. `cd api && AWS_PROFILE=cubby bin/rails cubby:policies:index` and check retrieval (O9): past-due query should return Late payments, Payment plans, Payment methods; waitlist query should return Enrollment offers and Waitlist.
3. `AWS_PROFILE=cubby bin/rails cubby:draft` (O7), then look at the drafts in the UI.
4. `cd api && AWS_PROFILE=cubby EVALS_LIVE=1 bin/rails evals:drafts` (O8), commit `api/evals/drafts/recordings/*.json`, add `bin/rails evals:drafts` to `.github/workflows/api.yml`.
5. Close O7 to O9 and run record-lint with `--require-closed`.

## Next: phase 5
Events: an outbox row written inside `ProposedAction#transition!`, published to SNS, SQS consumer writing `domain_events`, `/analytics` page (LocalStack locally, so it doesn't depend on Bedrock).
