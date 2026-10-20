# Prior art: Cubby phase 6 on-demand AWS deploy

Retrieved 2026-10-19. Research record for the phase 6 build.

## Decision first

- **Recommendation:**
  - Two Terraform stacks with S3-native state locking. `base` is persistent and near free: ECR, S3 + CloudFront, analytics bucket, the GitHub OIDC role, alerts and the budget. `cluster` is created and destroyed on demand.
  - CloudFront serves the React build from S3 and sends `/api/*` through a CloudFront VPC origin to an internal ALB, which forwards to a NodePort on EKS managed Graviton nodes.
  - Pods get AWS access through EKS Pod Identity, one role per workload.
  - Flux syncs `deploy/production` from the public repo, with no write credentials.
  - Decisions D1 to D8.
- **Evidence:**
  - VPC origins put ALBs in private subnets and make CloudFront the single entry point. They require an internet gateway, a private subnet and the origin-facing prefix list or the service security group, and they exclude `use1-az3` (E1).
  - The installed provider exposes `aws_cloudfront_vpc_origin` (E2).
  - The installed Ruby SDK reads Pod Identity's container credentials (E3).
  - The EKS v21 module exposes Pod Identity addons, access entries and node group ASG names (E4).
  - A production-mode container booted, migrated, seeded and served correctly against local Postgres and Redis (E7).
- **Limitation:** Bedrock is still blocked on this account (phase 4 E7), so the deployed AI features report unavailable. CloudFront to ALB is HTTP inside AWS's network: there is no custom domain, so no certificate on the ALB.
- **Next check:** O1 to O7 below, on the live stack.

## Run header

- **Outcome:** a live demo URL that works end to end; teardown leaves only S3, CloudFront, ECR and state.
- **Mode:** greenfield. Profile Standard (6 lookups, installed module and SDK source, live account probes).
- **Known constraints:**
  - Personal account 731956852586 only. The `cubby` profile, never the STC `doug` profile. `allowed_account_ids` in both providers.
  - About $5 a day while up, and a $50 budget.
  - Fictional data.
  - Phase 3 deploy checklist.
  - Phase 5 IAM and queue policy notes.
- **Local-first:** I read the phase 3 checklist, the phase 5 handoff, the Rails 8.1 production config and Dockerfile, `aws-sdk-core` 3.258.0, and terraform-aws-modules eks 21.29.0 and vpc 6.7.3 as downloaded by `terraform init`.

## Questions

| ID | Question | Needs | Status | Answer |
| --- | --- | --- | --- | --- |
| Q1 | How does the API stay private behind CloudFront without a domain or certificate? | Official docs, provider schema | answered | D2 |
| Q2 | How do pods get least-privilege AWS access? | SDK source, module source | answered | D4 |
| Q3 | What keeps an on-demand cluster cheap and clean to tear down? | Module defaults, pricing knowledge | answered | D1, D3 |
| Q4 | How does GitOps work without giving the cluster write access to GitHub? | Chart values | answered | D5 |
| Q5 | How do rate limits and CSRF behave behind CloudFront? | Phase 3 checklist, live test | answered | D6 |
| Q6 | How does a fresh cluster get demo data and secrets? | Local seeds | answered | D7 |

## Evidence register

| ID | Family | Authority | Source / revision / locator | Status | Establishes |
| --- | --- | --- | --- | --- | --- |
| E1 | Official docs | documentation | docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html | read | VPC origins: ALB/NLB/EC2 in private subnets, internet gateway required, origin SG must allow the `com.amazonaws.global.cloudfront.origin-facing` prefix list or the service SG, origin deploy up to 15 minutes, us-east-1 except use1-az3, no inbound NACL evaluation |
| E2 | Library source | source | hashicorp/aws 6.69.1 provider schema (`terraform providers schema -json`) | read | `aws_cloudfront_vpc_origin.vpc_origin_endpoint_config{arn, name, http_port, https_port, origin_protocol_policy, origin_ssl_protocols}`; distribution origins take `vpc_origin_config{vpc_origin_id, origin_read_timeout, origin_keepalive_timeout}` |
| E3 | Library source | source | aws-sdk-core 3.258.0 `lib/aws-sdk-core/ecs_credentials.rb:172,227`, `credential_provider_chain.rb:237` | read | The SDK reads `AWS_CONTAINER_CREDENTIALS_FULL_URI` and `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE` and allows the EKS host 169.254.170.23, which is Pod Identity |
| E4 | Library source | source | terraform-aws-modules/eks 21.29.0 `variables.tf` (addons, `before_compute`, `encryption_config` nullable), `outputs.tf:264` | read | Addons can install before nodes; `encryption_config = null` disables the KMS key; node group ASG names are an output; node IMDS hop limit defaults to 1 |
| E5 | Live account probe | observed-artifact | Account 731956852586, 2026-10-19: `aws eks describe-cluster-versions`, RDS engine versions, Valkey versions, AZ ids, CloudFront managed policy ids, EC2 vCPU quota | read | EKS 1.37 standard support; Postgres 17.11; Valkey 8.2; use1-az1/az2 map to us-east-1a/b; managed policy ids used in `base/main.tf`; 64 vCPU quota |
| E6 | Chart values | source | fluxcd-community flux2 2.19.1 and flux2-sync 1.15.1 (`helm show values`) | read | Controllers can be turned off individually; flux2-sync renders a GitRepository and Kustomization from values, and a public repo needs no secret |
| E8 | Local project | source | `docs/plans/2026-10-19-handoff-after-phase-5.md` phase 6 notes; `docs/prior-art/2026-10-19-phase5-events.md` limits | read | Per-pod IAM actions the app calls, and that queue access without policies lets anyone inject analytics events |
| E7 | Live feasibility | observed-artifact | `cubby-api:prodcheck` image, RAILS_ENV=production on the compose network, 2026-10-19 | read | `db:prepare db:seed cubby:scan` created, seeded (idempotent on re-run) and scanned; `/up` 200; cross-site POST 403; sign-in 201 with a Secure, HttpOnly, SameSite=Lax cookie and HSTS; session IP and the rate-limit key used the CloudFront-Viewer-Address value; limits stored in Redis |

## Decisions

| ID | Decision | Status | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| D1 | Stacks and state / T2 | supported | E5 | `base` (persistent, cents a month) and `cluster` (on demand); S3 backend with `use_lockfile`; both providers pinned to the account with `allowed_account_ids`; every apply shows its plan |
| D2 | Edge / T1 | supported | E1, E2 | CloudFront VPC origin to an internal ALB in private subnets, SG limited to the origin-facing prefix list; CloudFront terminates TLS; `/api/*` uncached with all viewer headers plus CloudFront headers; a viewer-request function serves index.html for client routes and a 503 for `/api/*` while the cluster is down |
| D3 | Cost shape / T3 | supported | E4, E5 | No NAT gateway: nodes in public subnets with public IPs and no inbound from the internet; database, cache, ALB and control plane ENIs in private subnets; 2× t4g.small; no control plane logs, no customer KMS key; db.t4g.micro without backups; cache.t4g.micro |
| D4 | Workload identity / T1 | supported | E3, E4 | EKS Pod Identity over IRSA (no OIDC provider; current AWS recommendation): `cubby-api` Bedrock; `cubby-worker` Bedrock, `sns:Publish` on the topic, `s3:PutObject` on `events/*`; `cubby-events` receive, delete, get URL on the queue. Node IMDS hop limit 1 keeps pods off the node role |
| D5 | GitOps / T3 | supported | E6 | Flux source and kustomize controllers only, installed by Terraform, syncing the public repo read only; CI pushes an immutable arm64 image tag and commits the tag bump to `deploy/production` |
| D6 | Proxies, CSRF, rate limits / T1 | supported | E1, E7 | Trust `CloudFront-Viewer-Address` only when `CUBBY_TRUST_VIEWER_ADDRESS=1` (production, behind the VPC origin); Redis cache store; `APP_ORIGINS` = the CloudFront origin; `assume_ssl` so HTTP from the ALB is not redirected |
| D7 | Demo data and secrets / T2 | supported | E7 | Seeds run in production only with `CUBBY_DEMO=1`, and demo users need `DEMO_PASSWORD` (Terraform `random_password`, never the public local one); the api init container runs `db:prepare db:seed cubby:scan`; secrets live in a Kubernetes Secret and the encrypted, private state bucket |
| D8 | Event policies / T1 | supported | E8 | Topic policy denies `sns:Publish` unless `aws:PrincipalArn` is the worker role; queue policy denies `sqs:SendMessage` unless `aws:SourceArn` is the topic |

## Obligations

| ID | Decision | Invariant | Required authority | Check | Verified authority | Result | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| O1 | D1, D2 | `make up` yields a site where a director signs in, approves, and sees the change | end-to-end | `bin/verify-deploy.sh up` (Live stack through CloudFront) | end-to-end | pass (2026-10-19, the same commands run by hand; the script's `up` mode first runs at the next `make up`): `/`, `/inbox` 200; `/api/v1/me` 401 signed out; with a bearer token minted in the cluster, `me`, the 10-action inbox, approve 200, a stale retry 409, and analytics showing the approval; the sign-in page browser-checked at 1280 and 375 px with no CSP errors. A browser sign-in with the demo password was left to Doug (public host) | closed |
| O2 | D2 | The ALB and NodePort can't be reached from the internet; only CloudFront can | end-to-end | `bin/verify-deploy.sh up` (Direct requests to the ALB name and to a node's public IP) | end-to-end | pass (2026-10-19, the same commands run by hand; the script's `up` mode first runs at the next `make up`): the ALB name resolves to 10.40.x private addresses only; both nodes' public IPs time out on 30080 | closed |
| O3 | D6 | A viewer-supplied `CloudFront-Viewer-Address` does not change the recorded IP | end-to-end | `bin/verify-deploy.sh up` (Login attempt (fictional account) with a forged header; read the rate-limit keys in Valkey) | end-to-end | pass (2026-10-19, the same commands run by hand; the script's `up` mode first runs at the next `make up`): forged `1.2.3.4:1`; the limiter keyed on the real viewer address, so CloudFront overwrites the header | closed |
| O4 | D8, D4 | An approval reaches analytics through real SNS and SQS, and an outside principal can't publish or send | end-to-end | `bin/verify-deploy.sh up` (API approve, then analytics; `aws sns publish` / `aws sqs send-message` as the admin user) | end-to-end | pass (2026-10-19, the same commands run by hand; the script's `up` mode first runs at the next `make up`): the approval appeared in analytics within 20 s; the scan's proposed events arrived first; admin publish returned AuthorizationError and send returned AccessDenied | closed |
| O5 | D5 | CI pushes an image and Flux rolls it out with no manual step | end-to-end | `bin/verify-deploy.sh up` (Push to main, watch the Kustomization) | end-to-end | pass (2026-10-19, the same commands run by hand; the script's `up` mode first runs at the next `make up`): the image job pushed `06a3568`, committed `32e4a2b`, and Flux applied that revision; all three pods ran the new tag. First attempt failed on the OIDC trust (the repo uses GitHub's immutable subject `repo:kvadou@15655389/cubby@1426276158`), fixed in `01c50fd` | closed |
| O6 | D1, D3 | `make down` leaves only the base stack | end-to-end | `bin/verify-deploy.sh down` (Detach CloudFront, destroy the cluster, list what's left) | end-to-end | pass (2026-10-19, `bin/verify-deploy.sh down` 9/9): 93 destroyed, cluster state empty; no EKS, RDS, ElastiCache, load balancer, instance, EBS volume, VPC, VPC origin, or queue left | closed |
| O7 | D2 | The site says the demo is offline while the cluster is down | end-to-end | `bin/verify-deploy.sh down` (Browser at the CloudFront URL after teardown) | end-to-end | pass (2026-10-19, `bin/verify-deploy.sh down` 9/9): `/api/*` returns the function's JSON 503; the app shows "The demo is offline" at once (no retries since `4594657`) | closed |

## Coverage

| Source family | Status | Notes |
| --- | --- | --- |
| Official docs | read | CloudFront VPC origins (E1) |
| Library and module source | read | AWS provider schema, aws-sdk-core, EKS and VPC modules, Flux charts (E2 to E4, E6) |
| Live account | read | Versions, quotas, managed policies (E5); production image (E7) |
| Application repositories | not-applicable | The terraform-aws-modules examples are the standard reference; the shape here is a small variation |
| Failure history | searched-no-relevant-result | No postmortem search; the known teardown trap (CloudFront holding a VPC origin) is handled by `make down` ordering |

## Limits

- The Fargate/ALB-controller variants were not compared in depth. The NodePort plus Terraform-owned ALB avoids the load balancer controller and its IAM, and leaves nothing for `terraform destroy` to miss.
- No custom domain means CloudFront's default certificate and HTTP between CloudFront and the ALB inside AWS's network (E1). A domain plus an ACM certificate is the upgrade.
- The EKS API endpoint is public (IAM-authenticated) so Terraform and kubectl run from a laptop.
- Not done: password change and sign out everywhere. The demo directors are shared accounts, so a visitor changing the password would lock everyone else out. Both are required before any real user.
- Not done: an alarm on outbox rows stuck unpublished, which needs an app metric. The analytics page shows the backlog, and the queue-age alarm covers a stopped consumer.
- Independent security review (2026-10-19), no HIGH in the code. Fixed:
  - Plan files are now gitignored. The one created was deleted after apply and never committed.
  - The per-email login limit is keyed on email plus IP, so one address can't lock out the shared demo directors. A 50-per-hour backstop per account remains.
  - Ask Cubby has daily ceilings, 100 per user and 300 overall, as a Bedrock spend cap.
  - The API sends security headers and a CSP.
  - Image pushes are idempotent for the immutable tags.
  - The third-party AWS actions are pinned to commit SHAs.
- Accepted:
  - The EKS endpoint is public: IAM-gated, and the operator's IP changes.
  - Pods or nodes inside the VPC could forge the viewer header.
  - No customer KMS key for Kubernetes secrets.
  - A sustained attacker (50 a hour) can still lock one account out. That's the tradeoff of having any per-account limit.
  - IPv6 viewers aren't grouped by /64 for rate limits.
- Review triggers: a custom domain, a second environment, real users, Bedrock access restored, or a node group above two nodes.
