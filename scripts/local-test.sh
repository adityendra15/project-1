#!/usr/bin/env bash
set -Eeuo pipefail

for command in docker kind kubectl curl python3 trivy; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install --requirement requirements-dev.txt
pytest

build_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
docker build \
  --build-arg APP_VERSION=baseline \
  --build-arg VCS_REF=baseline \
  --build-arg BUILD_TIME="$build_time" \
  --tag secure-web:baseline .
docker build \
  --build-arg APP_VERSION=candidate \
  --build-arg VCS_REF=local \
  --build-arg BUILD_TIME="$build_time" \
  --tag secure-web:candidate .

mkdir -p artifacts
trivy image --ignore-unfixed --severity HIGH,CRITICAL \
  --format json --output artifacts/trivy-image.json secure-web:candidate
trivy image --ignore-unfixed --severity CRITICAL --exit-code 1 secure-web:candidate
trivy image --format cyclonedx --output artifacts/sbom.cdx.json secure-web:candidate

BASELINE_IMAGE=secure-web:baseline \
CANDIDATE_IMAGE=secure-web:candidate \
COMMIT_SHA=local \
  ./scripts/kubernetes-e2e.sh
