#!/usr/bin/env bash
set -Eeuo pipefail

URL=${1:-http://127.0.0.1:18080/version}
DURATION_SECONDS=${2:-45}
OUTPUT_FILE=${3:-build/availability-report.json}
INTERVAL_SECONDS=${INTERVAL_SECONDS:-0.2}

mkdir -p "$(dirname "$OUTPUT_FILE")"
start_epoch=$(date +%s)
requests=0
successes=0
failures=0
versions_file=$(mktemp)
trap 'rm -f "$versions_file"' EXIT

while (( $(date +%s) - start_epoch < DURATION_SECONDS )); do
  requests=$((requests + 1))
  response_file=$(mktemp)
  status=$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --max-time 2 "$URL" || true)

  if [[ "$status" == "200" ]] && python3 -m json.tool "$response_file" >/dev/null 2>&1; then
    successes=$((successes + 1))
    python3 - "$response_file" >>"$versions_file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("version", "unknown"))
PY
  else
    failures=$((failures + 1))
    echo "Request $requests failed with HTTP status ${status:-curl-error}" >&2
  fi
  rm -f "$response_file"
  sleep "$INTERVAL_SECONDS"
done

python3 - "$OUTPUT_FILE" "$requests" "$successes" "$failures" "$versions_file" <<'PY'
import collections
import json
import sys
from pathlib import Path

output, requests, successes, failures, versions_path = sys.argv[1:]
versions = Path(versions_path).read_text(encoding="utf-8").splitlines()
payload = {
    "requests": int(requests),
    "successes": int(successes),
    "failures": int(failures),
    "observed_versions": dict(collections.Counter(versions)),
}
Path(output).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(json.dumps(payload, indent=2))
PY

if (( failures > 0 )); then
  exit 1
fi
