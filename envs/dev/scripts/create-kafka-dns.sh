#!/usr/bin/env bash
# Create Route 53 CNAME records for Kafka bootstrap and brokers.
# Canonical copy: repo root scripts/create-kafka-dns.sh (same content).
# Run from envs/dev: ZONE_ID=$(terraform output -raw kafka_dns_zone_id) && ZONE_ID=$ZONE_ID ./scripts/create-kafka-dns.sh
# Requires: kubectl, jq, aws CLI, bash.

set -euo pipefail

ZONE_ID="${ZONE_ID:-${1:-}}"
NAMESPACE="${NAMESPACE:-confluent}"
DOMAIN="${DOMAIN:-confluent.local}"

if [[ -z "$ZONE_ID" ]]; then
  echo "Usage: ZONE_ID=<route53-zone-id> $0" >&2
  echo "   or: $0 <route53-zone-id>" >&2
  echo "From envs/dev: ZONE_ID=\$(terraform output -raw kafka_dns_zone_id) && ZONE_ID=\$ZONE_ID ./scripts/create-kafka-dns.sh" >&2
  exit 1
fi

DOMAIN="${DOMAIN%.}"

echo "Getting all LoadBalancer services from namespace=$NAMESPACE (bootstrap + broker NLBs) ..."
SVC_JSON=$(kubectl get svc -n "$NAMESPACE" -o json 2>/dev/null)
if [[ -z "$SVC_JSON" ]]; then
  echo "No services found. Ensure Kafka is deployed and namespace $NAMESPACE exists." >&2
  exit 1
fi

# Any service with LoadBalancer ingress; we match by name so broker services are found even if labels differ
declare -A RECORDS
while IFS= read -r line; do
  name="${line%% *}"
  hostname="${line#* }"
  if [[ -z "$hostname" || "$hostname" == "$name" ]]; then
    echo "Skipping $name (no LoadBalancer hostname yet)" >&2
    continue
  fi
  if [[ "$name" == *bootstrap* ]]; then
    RECORDS["kafka"]="$hostname"
  elif [[ "$name" =~ ^kafka-([0-9]+)(-lb)?$ ]]; then
    # CFK uses kafka-0, kafka-1, kafka-2 or kafka-0-lb, kafka-1-lb, kafka-2-lb
    RECORDS["b${BASH_REMATCH[1]}"]="$hostname"
  else
    echo "Skipping $name (not bootstrap or kafka-0/1/2[-lb])" >&2
  fi
done < <(echo "$SVC_JSON" | jq -r '.items[] | select(.status.loadBalancer.ingress != null and (.status.loadBalancer.ingress | length) > 0) | "\(.metadata.name) \(.status.loadBalancer.ingress[0].hostname // .status.loadBalancer.ingress[0].ip)"')

if [[ ${#RECORDS[@]} -eq 0 ]]; then
  echo "No LoadBalancer hostnames found. Wait for Kafka services to get EXTERNAL-IP and retry." >&2
  exit 1
fi

CHANGES=""
for dns_name in kafka b0 b1 b2; do
  if [[ -n "${RECORDS[$dns_name]:-}" ]]; then
    target="${RECORDS[$dns_name]}"
    target="${target//$'\r'/}"
    target="${target//$'\n'/}"
    [[ "$target" != *. ]] && target="${target}."
    full_name="${dns_name}.${DOMAIN}."
    if [[ -n "$CHANGES" ]]; then CHANGES="$CHANGES,"; fi
    CHANGES="$CHANGES{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$full_name\",\"Type\":\"CNAME\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"$target\"}]}}"
    echo "  $full_name -> $target"
  fi
done

if [[ -z "$CHANGES" ]]; then
  echo "No records to create." >&2
  exit 1
fi

BATCH="{\"Changes\":[$CHANGES]}"
echo "Applying Route 53 changes to zone $ZONE_ID ..."
aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch "$BATCH"
echo "Done. Use bootstrap server: kafka.${DOMAIN}:9092 (from pods/EC2 in the same VPC)."
