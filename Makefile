# On-demand AWS deploy (docs/plans/2026-10-19-phase6-plan.md). Everything runs as the `cubby` profile
# in Doug's personal account, and the providers refuse any other account. Each apply shows its plan and
# asks for "yes" before changing anything.
#
#   make bootstrap   once: Terraform state bucket
#   make base        persistent, near-free pieces: ECR, web bucket + CloudFront, analytics bucket, CI role, budget
#   make demo        always-on demo: one t4g.small running the app under Docker Compose (about $18 a month)
#   make demo-down   removes the demo host
#   make up          cluster: VPC, EKS, RDS, Valkey, SNS/SQS, ALB, Flux (about 25 minutes, about $5 a day)
#   make down        removes the cluster; the site goes back to the demo host (or says it's offline)
#   make status      what's running
#   make kubeconfig  writes infra/.kubeconfig for kubectl

export AWS_PROFILE := cubby
export AWS_REGION := us-east-1
export KUBECONFIG := $(CURDIR)/infra/.kubeconfig

BASE := infra/terraform/base
CLUSTER := infra/terraform/cluster
DEMO := infra/terraform/demo
ORIGIN_VARS := $(BASE)/api_origin.auto.tfvars.json

.PHONY: guard bootstrap base demo demo-down up down status kubeconfig

guard:
	@test "$$(aws sts get-caller-identity --query Account --output text)" = "731956852586" || \
		{ echo "Refusing: the cubby profile is not account 731956852586" >&2; exit 1; }

bootstrap: guard
	bin/tf-bootstrap

base: guard
	@test -f $(ORIGIN_VARS) || echo '{"api_origin": null}' > $(ORIGIN_VARS)
	terraform -chdir=$(BASE) init -input=false
	terraform -chdir=$(BASE) apply

# The host first, then point CloudFront's /api/* at it (unless the cluster is up, which takes precedence).
demo: guard
	terraform -chdir=$(DEMO) init -input=false
	terraform -chdir=$(DEMO) apply
	bin/api-origin > $(ORIGIN_VARS)
	terraform -chdir=$(BASE) apply
	@echo "Demo: https://$$(terraform -chdir=$(BASE) output -raw site_domain) (first boot takes about 5 minutes)"

demo-down: guard
	terraform -chdir=$(DEMO) init -input=false
	terraform -chdir=$(CLUSTER) output -json api_origin 2>/dev/null | grep -q vpc_origin_id || echo '{"api_origin": null}' > $(ORIGIN_VARS)
	terraform -chdir=$(BASE) apply
	terraform -chdir=$(DEMO) destroy

# The cluster first, then point CloudFront's /api/* at its private load balancer.
up: guard
	terraform -chdir=$(CLUSTER) init -input=false
	terraform -chdir=$(CLUSTER) apply
	bin/api-origin > $(ORIGIN_VARS)
	terraform -chdir=$(BASE) apply
	$(MAKE) kubeconfig
	@echo "Up: https://$$(terraform -chdir=$(BASE) output -raw site_domain)"

# CloudFront lets go of the load balancer (back to the demo host if there is one) before the cluster goes.
down: guard
	bin/api-origin --without-cluster > $(ORIGIN_VARS)
	terraform -chdir=$(BASE) apply
	terraform -chdir=$(CLUSTER) init -input=false
	terraform -chdir=$(CLUSTER) destroy
	@echo "Down. The site stays at https://$$(terraform -chdir=$(BASE) output -raw site_domain)"

status: guard
	@echo "Site: https://$$(terraform -chdir=$(BASE) output -raw site_domain)"
	@aws eks describe-cluster --name cubby --query 'cluster.status' --output text 2>/dev/null || echo "Cluster: down"
	@aws ec2 describe-instances --filters Name=tag:Name,Values=cubby-demo Name=instance-state-name,Values=pending,running \
		--query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text | sed 's/^/Demo host: /' | grep . || echo "Demo host: down"

kubeconfig: guard
	aws eks update-kubeconfig --name cubby --alias cubby --kubeconfig $(KUBECONFIG) >/dev/null
	@echo "kubectl ready: export KUBECONFIG=$(KUBECONFIG)"
