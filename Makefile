# On-demand AWS deploy (docs/plans/2026-10-19-phase6-plan.md). Everything runs as the `cubby` profile
# in Doug's personal account, and the providers refuse any other account. Each apply shows its plan and
# asks for "yes" before changing anything.
#
#   make bootstrap   once: Terraform state bucket
#   make base        persistent, near-free pieces: ECR, web bucket + CloudFront, analytics bucket, CI role, budget
#   make up          cluster: VPC, EKS, RDS, Valkey, SNS/SQS, ALB, Flux (about 25 minutes, about $5 a day)
#   make down        removes the cluster; the site stays up and says the demo is offline
#   make status      what's running
#   make kubeconfig  writes infra/.kubeconfig for kubectl

export AWS_PROFILE := cubby
export AWS_REGION := us-east-1
export KUBECONFIG := $(CURDIR)/infra/.kubeconfig

BASE := infra/terraform/base
CLUSTER := infra/terraform/cluster
ORIGIN_VARS := $(BASE)/api_origin.auto.tfvars.json

.PHONY: guard bootstrap base up down status kubeconfig

guard:
	@test "$$(aws sts get-caller-identity --query Account --output text)" = "731956852586" || \
		{ echo "Refusing: the cubby profile is not account 731956852586" >&2; exit 1; }

bootstrap: guard
	bin/tf-bootstrap

base: guard
	@test -f $(ORIGIN_VARS) || echo '{"api_origin": null}' > $(ORIGIN_VARS)
	terraform -chdir=$(BASE) init -input=false
	terraform -chdir=$(BASE) apply

# The cluster first, then point CloudFront's /api/* at its private load balancer.
up: guard
	terraform -chdir=$(CLUSTER) init -input=false
	terraform -chdir=$(CLUSTER) apply
	echo "{\"api_origin\": $$(terraform -chdir=$(CLUSTER) output -json api_origin)}" > $(ORIGIN_VARS)
	terraform -chdir=$(BASE) apply
	$(MAKE) kubeconfig
	@echo "Up: https://$$(terraform -chdir=$(BASE) output -raw site_domain)"

# CloudFront lets go of the load balancer before the cluster is destroyed.
down: guard
	echo '{"api_origin": null}' > $(ORIGIN_VARS)
	terraform -chdir=$(BASE) apply
	terraform -chdir=$(CLUSTER) init -input=false
	terraform -chdir=$(CLUSTER) destroy
	@echo "Down. The site stays at https://$$(terraform -chdir=$(BASE) output -raw site_domain)"

status: guard
	@echo "Site: https://$$(terraform -chdir=$(BASE) output -raw site_domain)"
	@aws eks describe-cluster --name cubby --query 'cluster.status' --output text 2>/dev/null || echo "Cluster: down"

kubeconfig: guard
	aws eks update-kubeconfig --name cubby --alias cubby --kubeconfig $(KUBECONFIG) >/dev/null
	@echo "kubectl ready: export KUBECONFIG=$(KUBECONFIG)"
