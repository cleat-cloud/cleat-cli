#!/usr/bin/env bash
# Compare the vendored CLI fixture with the canonical panel contract.
# Usage: scripts/check_panel_contract.sh
# Optional: CLEAT_DEPLOY_CONTRACT=/path/to/priv/api_contract.json
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$root/test/fixtures/api_contract.json"
canonical="${CLEAT_DEPLOY_CONTRACT:-}"

if [[ -z "$canonical" && -f "$root/../cleat-web/priv/api_contract.json" ]]; then
  canonical="$root/../cleat-web/priv/api_contract.json"
fi

if [[ -z "$canonical" ]]; then
  canonical="$(mktemp)"
  trap 'rm -f "$canonical"' EXIT
  curl -fsSL "https://raw.githubusercontent.com/cleat-cloud/cleat-deploy/main/priv/api_contract.json" \
    -o "$canonical"
fi

if [[ ! -f "$fixture" ]]; then
  echo "missing CLI fixture: $fixture" >&2
  exit 1
fi

if [[ ! -f "$canonical" ]]; then
  echo "missing panel contract: $canonical" >&2
  exit 1
fi

python3 - "$fixture" "$canonical" <<'PY'
import json, sys

fixture_path, canonical_path = sys.argv[1], sys.argv[2]
with open(fixture_path) as fh:
    fixture = json.load(fh)
with open(canonical_path) as fh:
    canonical = json.load(fh)
if fixture != canonical:
    print(
        f"CLI fixture {fixture_path} drifted from panel contract {canonical_path}",
        file=sys.stderr,
    )
    sys.exit(1)
print(f"ok: {fixture_path} matches {canonical_path}")
PY
