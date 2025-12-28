#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_FALLBACK="${RID_FALLBACK:-VSP_CI_20251211_133204}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need wc; need head

echo "== [warm] =="
ok=0
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 2 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    echo "[OK] selfcheck ok (try#$i)"; ok=1; break
  fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] selfcheck failing"; exit 2; }

echo "== [pick RID] =="
rm -f /tmp/_p37_runs.bin /tmp/_p37_runs.hdr || true
curl -sS --connect-timeout 2 --max-time 10 -D /tmp/_p37_runs.hdr -o /tmp/_p37_runs.bin \
  "$BASE/api/vsp/runs?limit=1&offset=0" || true
[ -f /tmp/_p37_runs.bin ] || : > /tmp/_p37_runs.bin

RID="$(python3 - <<'PY' 2>/dev/null || true
import json
try:
    j=json.load(open("/tmp/_p37_runs.bin","r",encoding="utf-8", errors="replace"))
    runs=j.get("runs") or []
    r0=runs[0] if runs and isinstance(runs[0], dict) else {}
    print((r0.get("rid") or r0.get("id") or "").strip())
except Exception:
    print("")
PY
)"
RID="${RID:-$RID_FALLBACK}"
echo "RID=$RID"

for fmt in html pdf zip; do
  echo "== [CHECK export $fmt] =="
  curl -sS --connect-timeout 2 --max-time 25 -D /tmp/_e.hdr -o /tmp/_e.bin \
    "$BASE/api/vsp/export?rid=$RID&fmt=$fmt" || true
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:|^Content-Length:/{print}' /tmp/_e.hdr || true
  echo "bytes=$(wc -c </tmp/_e.bin 2>/dev/null || echo 0)"
  head -c 120 /tmp/_e.bin; echo
  echo
done
