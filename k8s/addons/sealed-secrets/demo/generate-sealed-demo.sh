#!/usr/bin/env bash
# Run on a machine with kubectl (kubeconfig for the target cluster) and kubeseal installed.
# Produces sealedsecret-demo.yaml — safe to commit; only this cluster's controller can decrypt.
set -euo pipefail
NS=ml-platform
OUT="$(dirname "$0")/sealedsecret-demo.yaml"

kubectl create secret generic demo-api-key \
  --dry-run=client \
  --namespace="$NS" \
  --from-literal=api-key="${DEMO_API_KEY:-demo-value-for-video}" \
  -o yaml | kubeseal -o yaml >"$OUT"

echo "Wrote $OUT — apply with: kubectl apply -f $OUT"
