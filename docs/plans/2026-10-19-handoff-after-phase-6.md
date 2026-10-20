# Handoff after phase 6

## Done
- **Terraform base stack.** Live and persistent: ECR, the web app on S3 behind CloudFront (`https://drpv8p7ep5jv3.cloudfront.net`, with a CSP and security headers), the analytics bucket, the GitHub OIDC deploy role, the alerts topic and a $50 monthly budget.
- **Terraform cluster stack.** Brought up, checked live, and destroyed again through the `make down` order:
  - VPC with no NAT; EKS 1.37 on 2× t4g.small.
  - Internal ALB behind a CloudFront VPC origin.
  - RDS Postgres 17 and Valkey 8.
  - SNS/SQS with publish and send policies.
  - Pod Identity roles.
  - Flux, and CloudWatch alarms.
- **CI:**
  - The api workflow builds and pushes an arm64 image and commits the tag bump.
  - The web workflow deploys to S3 and CloudFront.
  - The infra workflow checks Terraform fmt/validate and renders the kustomization.
- **Rails:**
  - The real viewer IP comes from CloudFront.
  - Rate limits are stored in Redis, and the email throttle is keyed on email plus IP, with a per-account backstop.
  - Ask Cubby has daily ceilings.
  - Demo seeds run in production with a generated password.
  - Specs refuse to run against a non-test database. That guard was added after a run hit the dev DB through compose's `DATABASE_URL`; run specs with `-e DATABASE_URL=postgres://cubby:cubby@db:5432/cubby_test`.
- **Live checks O1 to O5:** all pass. Details are in the record.

## Commands
- `make up` takes about 25 minutes and costs about $5 a day while up. Then:
  - Read the demo password: `terraform -chdir=infra/terraform/cluster output -raw demo_password`.
  - Sign in at the site as `renee@littleoaks.test`.
- `make down` leaves only the base stack. The site then says the demo is offline.
- Optional alert email: put `alert_email = "you@example.com"` in `infra/terraform/base/terraform.tfvars` (gitignored), run `make base`, then confirm the email AWS sends. Until then, budget and alarm notices go to an SNS topic with no subscriber.

## Still open
- **Bedrock access** (phase 4, Error 002). Once it's restored, the deployed AI features work with no infra change: the Pod Identity roles already allow the models.
- **Before any real user:** password change, sign out everywhere, and a custom domain with an ACM certificate.

## Next: phase 7
iOS parent app (SwiftUI) against the bearer-token API.
