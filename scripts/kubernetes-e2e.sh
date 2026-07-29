#!/usr/bin/env bash
set -Eeuo pipefail

BASELINE_IMAGE=${BASELINE_IMAGE:-secure-web:baseline}
CANDIDATE_IMAGE=${CANDIDATE_IMAGE:-secure-web:candidate}
CLUSTER_NAME=${CLUSTER_NAME:-secure-pipeline-ci}
NAMESPACE=secure-web
CLIENT_POD=availability-client
SERVICE_URL=http://secure-web/version
BUILD_DIR=${BUILD_DIR:-build}

mkdir -p "$BUILD_DIR"

cleanup() {
  for pid in "${MONITOR_PID:-}" "${FAILURE_MONITOR_PID:-}"; do
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

run_cluster_monitor() {
  local duration_seconds=$1
  local output_file=$2

  kubectl -n "$NAMESPACE" exec -i "$CLIENT_POD" -- \
    python - "$SERVICE_URL" "$duration_seconds" >"$output_file" <<'PY'
import collections
import json
import sys
import time
import urllib.error
import urllib.request

url = sys.argv[1]
duration = float(sys.argv[2])
deadline = time.monotonic() + duration
requests = 0
successes = 0
failures = 0
versions = []

while time.monotonic() < deadline:
    requests += 1
    try:
        with urllib.request.urlopen(url, timeout=2) as response:
            status = response.status
            payload = json.load(response)
        if status == 200:
            successes += 1
            versions.append(payload.get("version", "unknown"))
        else:
            failures += 1
            print(f"Request {requests} returned HTTP {status}", file=sys.stderr)
    except (OSError, ValueError, urllib.error.URLError) as exc:
        failures += 1
        print(f"Request {requests} failed: {exc}", file=sys.stderr)
    time.sleep(0.2)

report = {
    "requests": requests,
    "successes": successes,
    "failures": failures,
    "observed_versions": dict(collections.Counter(versions)),
}
print(json.dumps(report, indent=2))
if failures:
    raise SystemExit(1)
PY
}

query_service_version() {
  kubectl -n "$NAMESPACE" exec "$CLIENT_POD" -- python -c \
    'import json,urllib.request; print(json.load(urllib.request.urlopen("http://secure-web/version", timeout=5))["version"])'
}

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

kubectl -n "$NAMESPACE" run "$CLIENT_POD" \
  --image="$BASELINE_IMAGE" \
  --image-pull-policy=IfNotPresent \
  --restart=Never \
  --command -- sleep 3600
kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$CLIENT_POD" --timeout=120s

baseline_version=$(query_service_version)
[[ "$baseline_version" == "baseline" ]]

run_cluster_monitor 45 "$BUILD_DIR/rolling-update-availability.json" &
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
unset MONITOR_PID

actual_version=$(query_service_version)
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

run_cluster_monitor 35 "$BUILD_DIR/failed-rollout-availability.json" &
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
unset FAILURE_MONITOR_PID
kubectl -n "$NAMESPACE" rollout undo deployment/secure-web
kubectl -n "$NAMESPACE" rollout status deployment/secure-web --timeout=180s
./scripts/wait-for-replicas.sh "$NAMESPACE" secure-web 3 180

kubectl -n "$NAMESPACE" get deployment,pods,service,pdb -o wide \
  >"$BUILD_DIR/kubernetes-state.txt"
echo "Kubernetes end-to-end verification passed."
