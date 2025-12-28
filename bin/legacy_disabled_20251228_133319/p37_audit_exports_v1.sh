#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need wc; need head

# warm
for i in $(seq 1 60); do
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1 && break
  sleep 0.2
done

RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1&offset=0" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin); runs=j.get("runs") or []
r0=runs[0] if runs and isinstance(runs[0], dict) else {}
print((r0.get("rid") or r0.get("id") or "").strip())
PY
)"
echo "RID=$RID"
[ -n "$RID" ] || { echo "[ERR] cannot pick RID"; exit 2; }

check(){
  local fmt="$1"
  local url="$BASE/api/vsp/export?rid=$RID&fmt=$fmt"
  local out="/tmp/_p37_${fmt}.bin"
  local hdr="/tmp/_p37_${fmt}.hdr"
  echo "== export fmt=$fmt =="
  curl -sS -D "$hdr" -o "$out" "$url" || true
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:|^Content-Length:/{print}' "$hdr" || true
  echo "bytes=$(wc -c <"$out" 2>/dev/null || echo 0)"
  head -c 120 "$out"; echo
  echo
}

check html
check pdf
check zip
