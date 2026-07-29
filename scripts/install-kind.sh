#!/usr/bin/env bash
set -Eeuo pipefail

KIND_VERSION=${KIND_VERSION:-v0.31.0}
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) KIND_ARCH=amd64 ;;
  aarch64|arm64) KIND_ARCH=arm64 ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

binary="kind-linux-${KIND_ARCH}"
base_url="https://kind.sigs.k8s.io/dl/${KIND_VERSION}"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

curl --fail --silent --show-error --location "$base_url/$binary" \
  --output "$tmp_dir/$binary"
curl --fail --silent --show-error --location "$base_url/$binary.sha256sum" \
  --output "$tmp_dir/$binary.sha256sum"
(
  cd "$tmp_dir"
  sha256sum --check --strict "$binary.sha256sum"
)
sudo install -m 0755 "$tmp_dir/$binary" /usr/local/bin/kind
kind version
