#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE=${IMAGE:?Set IMAGE, for example secure-web:candidate}
APP_VERSION=${APP_VERSION:?Set APP_VERSION}
COMMIT_SHA=${COMMIT_SHA:-local}
BUILD_TIME=${BUILD_TIME:-unknown}
OUTPUT_DIR=${OUTPUT_DIR:-build/k8s}

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cp k8s/*.yaml "$OUTPUT_DIR/"

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

image_escaped=$(escape_sed "$IMAGE")
version_escaped=$(escape_sed "$APP_VERSION")
commit_escaped=$(escape_sed "$COMMIT_SHA")
build_time_escaped=$(escape_sed "$BUILD_TIME")

sed -i \
  -e "s|__IMAGE__|${image_escaped}|g" \
  -e "s|__APP_VERSION__|${version_escaped}|g" \
  -e "s|__COMMIT_SHA__|${commit_escaped}|g" \
  -e "s|__BUILD_TIME__|${build_time_escaped}|g" \
  "$OUTPUT_DIR/deployment.yaml"

if grep -R "__[A-Z_]*__" "$OUTPUT_DIR"; then
  echo "A manifest placeholder was not rendered." >&2
  exit 1
fi

echo "Rendered Kubernetes manifests to $OUTPUT_DIR"
