#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE=${1:-secure-web}
DEPLOYMENT=${2:-secure-web}
EXPECTED=${3:-3}
TIMEOUT_SECONDS=${4:-120}

start=$(date +%s)
while (( $(date +%s) - start < TIMEOUT_SECONDS )); do
  ready=$(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  available=$(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
  updated=$(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" \
    -o jsonpath='{.status.updatedReplicas}' 2>/dev/null || true)

  if [[ "${ready:-0}" == "$EXPECTED" && "${available:-0}" == "$EXPECTED" && "${updated:-0}" == "$EXPECTED" ]]; then
    echo "Deployment has $EXPECTED ready, available and updated replicas."
    exit 0
  fi
  sleep 2
done

kubectl -n "$NAMESPACE" get deployment,pods -o wide || true
kubectl -n "$NAMESPACE" describe deployment "$DEPLOYMENT" || true
exit 1
