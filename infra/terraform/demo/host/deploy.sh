#!/bin/bash
# Deploys the image that deploy/production/kustomization.yaml names on main: the tag CI commits after
# pushing to ECR, which Flux follows on EKS. Runs at boot and every 5 minutes (cubby-deploy.timer).
set -euo pipefail
cd /opt/cubby

source=https://raw.githubusercontent.com/kvadou/cubby/main/deploy/production/kustomization.yaml
tag=$(curl -fsS --max-time 20 "$source" | sed -n 's/^ *newTag: *\([0-9a-f]\{40\}\) *$/\1/p')
[[ -n "$tag" ]] || { echo "No image tag in $source" >&2; exit 1; }
image="$REGISTRY/cubby-api:$tag"

current=$(sed -n 's/^CUBBY_IMAGE=//p' .env 2>/dev/null || true)
if [[ "$image" == "$current" ]] && docker compose ps --status running --services | grep -qx api; then
  exit 0
fi

echo "Deploying $image"
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
docker pull --quiet "$image"
echo "CUBBY_IMAGE=$image" > .env.next && mv .env.next .env
docker compose up -d --remove-orphans
docker image prune -af --filter "until=72h" >/dev/null || true
