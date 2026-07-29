#!/usr/bin/env bash
set -Eeuo pipefail

BASELINE_IMAGE=${BASELINE_IMAGE:-secure-web:baseline}
CANDIDATE_IMAGE=${CANDIDATE_IMAGE:-secure-web:candidate}
CLUSTER_NAME=${CLUSTER_NAME:-secure-pipeline-ci}
NAMESPACE=secure-web
PORT=${PORT:-18080}
BUILD_DIR=${BUILD_DIR:-build}

mkdir -p "$BUILD_DIR"

cleanup() {
  for pid in "${MONITOR_PID:-}" "${FAILURE_MONITOR_PID:-}" "${PORT_FORWARD_PID:-}"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  if [[ "${KEEP_CLUSTER:-false}" != "true" ]]; then
    kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER_NAME" --wait 120s
kind load docker-image "$BASELINE_IMAGE" --name "$CLUSTER_NAME"
kind load docker-image "$CANDIDATE_IMAGE" --name "$CLUSTER_NAME"

IMAGE="$BASELINE_IMAGE" \
APP_VERSION="baseline" \
COMMIT_SHA="baseline" \
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
OUTPUT_DIR="$BUILD_DIR/k8s-baseline" \
  ./scripts/render-manifests.sh

kubectl apply -f "$BUILD_DIR/k8s-baseline/namespace.yaml"
kubectl apply -f "$BUILD_DIR/k8s-baseline/service-account.yaml"
kubectl apply -f "$BUILD_DIR/k8s-baseline/deployment.yaml"
kubectl apply -f "$BUILD_DIR/k8s-baseline/service.yaml"
kubectl apply -f "$BUILD_DIR/k8s-baseline/pod-disruption-budget.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/secure-web --timeout=180s
./scripts/wait-for-replicas.sh "$NAMESPACE" secure-web 3 180

kubectl -n "$NAMESPACE" port-forward service/secure-web "$PORT:80" \
  >"$BUILD_DIR/port-forward.log" 2>&1 &
PORT_FORWARD_PID=$!

for _ in {1..30}; do
  if curl --fail --silent "http://127.0.0.1:$PORT/health/ready" >/dev/null; then
    break
  fi
  sleep 1
done
curl --fail --silent "http://127.0.0.1:$PORT/version" | python3 -m json.tool

./scripts/monitor-availability.sh \
  "http://127.0.0.1:$PORT/version" 45 "$BUILD_DIR/rolling-update-availability.json" &
MONITOR_PID=$!

IMAGE="$CANDIDATE_IMAGE" \
APP_VERSION="candidate" \
COMMIT_SHA="${COMMIT_SHA:-local}" \
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
OUTPUT_DIR="$BUILD_DIR/k8s-candidate" \
  ./scripts/render-manifests.sh

kubectl apply -f "$BUILD_DIR/k8s-candidate/deployment.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/secure-web --timeout=180s
./scripts/wait-for-replicas.sh "$NAMESPACE" secure-web 3 180
wait "$MONITOR_PID"

actual_version=$(curl --fail --silent "http://127.0.0.1:$PORT/version" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')
[[ "$actual_version" == "candidate" ]]

before_pods=$(kubectl -n "$NAMESPACE" get pods \
  -l app.kubernetes.io/name=secure-web -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)
pod_to_delete=$(printf '%s\n' "$before_pods" | head -n 1)
kubectl -n "$NAMESPACE" delete pod "$pod_to_delete" --wait=false
kubectl -n "$NAMESPACE" wait --for=delete "pod/$pod_to_delete" --timeout=90s
./scripts/wait-for-replicas.sh "$NAMESPACE" secure-web 3 180
after_pods=$(kubectl -n "$NAMESPACE" get pods \
  -l app.kubernetes.io/name=secure-web -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)
replacement_pod=$(comm -13 <(printf '%s\n' "$before_pods") <(printf '%s\n' "$after_pods") | head -n 1)
if [[ -z "$replacement_pod" ]]; then
  echo "No replacement Pod was detected." >&2
  exit 1
fi
printf '{\n  "deleted_pod": "%s",\n  "replacement_observed": true,\n  "replacement_pod": "%s"\n}\n' \
  "$pod_to_delete" "$replacement_pod" >"$BUILD_DIR/self-healing-report.json"

./scripts/monitor-availability.sh \
  "http://127.0.0.1:$PORT/version" 35 "$BUILD_DIR/failed-rollout-availability.json" &
FAILURE_MONITOR_PID=$!

kubectl -n "$NAMESPACE" set image deployment/secure-web \
  web=registry.invalid/secure-web:does-not-exist
if kubectl -n "$NAMESPACE" rollout status deployment/secure-web --timeout=25s; then
  echo "The intentionally broken rollout unexpectedly succeeded." >&2
  exit 1
else
  echo "Broken rollout failed as expected; healthy old replicas remained available."
fi
wait "$FAILURE_MONITOR_PID"
kubectl -n "$NAMESPACE" rollout undo deployment/secure-web
kubectl -n "$NAMESPACE" rollout status deployment/secure-web --timeout=180s
./scripts/wait-for-replicas.sh "$NAMESPACE" secure-web 3 180

kubectl -n "$NAMESPACE" get deployment,pods,service,pdb -o wide \
  >"$BUILD_DIR/kubernetes-state.txt"
echo "Kubernetes end-to-end verification passed."
