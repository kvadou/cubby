#!/usr/bin/env bash
# Live checks for the AWS deploy (docs/prior-art/2026-10-19-phase6-deploy.md, O1 to O7).
#   bin/verify-deploy.sh up     after `make up`: site, API, approve-to-analytics, private edge, policies, viewer IP
#   bin/verify-deploy.sh down   after `make down`: nothing billable left, site says the demo is offline
# Read-only except for one approval on the fictional demo and a short-lived token it revokes.
set -uo pipefail
cd "$(dirname "$0")/.."
export AWS_PROFILE=cubby AWS_REGION=us-east-1 KUBECONFIG="$PWD/infra/.kubeconfig"
[ "$(aws sts get-caller-identity --query Account --output text)" = "731956852586" ] || { echo "Refusing: not the cubby account" >&2; exit 1; }

site="https://$(terraform -chdir=infra/terraform/base output -raw site_domain)"
fails=0
check() { if [ "$2" = "$3" ]; then echo "pass  $1"; else echo "FAIL  $1 (expected $3, got $2)"; fails=$((fails + 1)); fi; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

if [ "${1:-}" = "down" ]; then
  check "O6 cluster state empty" "$(terraform -chdir=infra/terraform/cluster state list 2>/dev/null | wc -l | tr -d ' ')" "0"
  check "O6 no EKS cluster" "$(aws eks list-clusters --query 'length(clusters)')" "0"
  check "O6 no RDS instance" "$(aws rds describe-db-instances --query 'length(DBInstances)')" "0"
  check "O6 no cache" "$(aws elasticache describe-replication-groups --query 'length(ReplicationGroups)')" "0"
  check "O6 no load balancer" "$(aws elbv2 describe-load-balancers --query 'length(LoadBalancers)')" "0"
  check "O6 no running instance" "$(aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running --query 'length(Reservations)')" "0"
  check "O6 no VPC origin" "$(aws cloudfront list-vpc-origins --query 'length(VpcOriginList.Items || `[]`)')" "0"
  check "O7 site loads" "$(code "$site/")" "200"
  check "O7 API says offline" "$(curl -s "$site/api/v1/me" | jq -r .error)" "offline"
  exit $fails
fi

[ "${1:-}" = "up" ] || { echo "usage: bin/verify-deploy.sh up|down" >&2; exit 2; }
aws eks update-kubeconfig --name cubby --alias cubby --kubeconfig "$KUBECONFIG" >/dev/null

check "O1 site loads" "$(code "$site/")" "200"
check "O1 client route serves the app" "$(code "$site/inbox")" "200"
check "O1 API reachable, signed out" "$(code "$site/api/v1/me")" "401"

# O1 / O4: approve through CloudFront with a token minted in the cluster, then find it in analytics.
token=$(kubectl -n cubby exec deploy/api -c api -- ./bin/rails runner \
  'u = User.find_by!(email_address: "renee@littleoaks.test"); _s, t = Session.issue_bearer!(user: u, user_agent: "verify-deploy", ip_address: "127.0.0.1"); print t' 2>/dev/null)
auth="Authorization: Bearer $token"
center=$(curl -s -H "$auth" "$site/api/v1/me" | jq '.centers[0].id')
before=$(curl -s -H "$auth" "$site/api/v1/centers/$center/analytics?days=7" | jq '.totals.approved')
action=$(curl -s -H "$auth" "$site/api/v1/centers/$center/proposed_actions" | jq -c '[.[] | select(.kind == "stale_waitlist")][0] | {id, lock_version}')
id=$(jq -r .id <<<"$action")
if [ "$id" != "null" ]; then
  check "O1 approve" "$(code -X POST -H "$auth" -H 'Content-Type: application/json' "$site/api/v1/centers/$center/proposed_actions/$id/approve" \
    -d "{\"lock_version\": $(jq .lock_version <<<"$action"), \"final_body\": \"A spot has opened up. Would you like to visit this week?\"}")" "200"
  after=$before
  for _ in $(seq 1 12); do
    after=$(curl -s -H "$auth" "$site/api/v1/centers/$center/analytics?days=7" | jq '.totals.approved')
    [ "$after" -gt "$before" ] && break
    sleep 5
  done
  check "O4 approval reached analytics through SNS and SQS" "$((after - before))" "1"
else
  echo "skip  O1 approve (no open waitlist action left; re-seed with make down / make up)"
fi
check "O1 token revoked" "$(code -X DELETE -H "$auth" "$site/api/v1/tokens/current")" "204"

# O2: no path around CloudFront.
alb=$(terraform -chdir=infra/terraform/cluster output -json api_origin | jq -r .domain_name)
check "O2 ALB has only private addresses" "$(dig +short "$alb" | grep -cvE '^10\.')" "0"
for ip in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}'); do
  check "O2 node $ip NodePort closed" "$(code -m 5 "http://$ip:30080/up")" "000"
done

# O3: a forged viewer address is overwritten by CloudFront.
code -X POST "$site/api/v1/session" -H 'Content-Type: application/json' -H 'Sec-Fetch-Site: same-origin' \
  -H 'CloudFront-Viewer-Address: 1.2.3.4:1' -d '{"email_address":"verify@example.test","password":"not-a-password"}' >/dev/null
forged=$(kubectl -n cubby exec deploy/api -c api -- ./bin/rails runner \
  'Rails.cache.redis.then { |r| puts r.scan_each(match: "cache:rate-limit:login:ip:1.2.3.4").count }' 2>/dev/null)
check "O3 forged viewer address ignored" "$forged" "0"

# O4: nobody but the worker publishes, nobody but the topic sends.
topic=$(aws sns list-topics --query "Topics[?ends_with(TopicArn, 'cubby-domain-events-production')].TopicArn" --output text)
queue=$(aws sqs get-queue-url --queue-name cubby-analytics-production --query QueueUrl --output text)
check "O4 outside publish denied" "$(aws sns publish --topic-arn "$topic" --message '{}' 2>&1 | grep -c AuthorizationError)" "1"
check "O4 outside send denied" "$(aws sqs send-message --queue-url "$queue" --message-body '{}' 2>&1 | grep -c AccessDenied)" "1"

# O5: Flux runs what main says.
want=$(sed -n 's/^    newTag: //p' deploy/production/kustomization.yaml)
check "O5 api runs the tag on main" "$(kubectl -n cubby get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')" "$want"
exit $fails
