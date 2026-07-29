#!/usr/bin/env bash
set -Eeuo pipefail

TRIVY_VERSION=${TRIVY_VERSION:-0.71.0}
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) TRIVY_ARCH=64bit ;;
  aarch64|arm64) TRIVY_ARCH=ARM64 ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

archive="trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz"
base_url="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

curl --fail --silent --show-error --location "$base_url/$archive" \
  --output "$tmp_dir/$archive"
curl --fail --silent --show-error --location "$base_url/trivy_${TRIVY_VERSION}_checksums.txt" \
  --output "$tmp_dir/checksums.txt"
(
  cd "$tmp_dir"
  grep "  ${archive}$" checksums.txt | sha256sum --check --strict
)
tar -xzf "$tmp_dir/$archive" -C "$tmp_dir" trivy
sudo install -m 0755 "$tmp_dir/trivy" /usr/local/bin/trivy
trivy --version
