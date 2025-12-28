#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

j="$(curl -sS "$BASE/api/vsp/runs?limit=20")"
echo "$j" | jq -e '
  .ok==true
  and (.items|type=="array")
  and (.limit|type=="number")
  and (.rid_latest|type=="string")
  and (.cache_ttl|type=="number")
  and (.roots_used|type=="array")
  and (.scan_cap_hit|type=="boolean")
' >/dev/null

echo "[OK] runs contract schema looks good"
echo "$j" | jq -r '.limit,.rid_latest,.cache_ttl,.scan_cap_hit, (.roots_used|length)'
