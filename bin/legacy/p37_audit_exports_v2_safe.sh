#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need wc; need head

warm(){
  for i in $(seq 1 80); do
    if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      echo "[OK] selfcheck ok (try#$i)"
      return 0
    fi
    sleep 0.2
  done
  echo "[ERR] selfcheck not OK"
  return 2
}

pick_rid(){
  local url="$BASE/api/vsp/runs?limit=5&offset=0"
  for i in $(seq 1 60); do
    curl -sS --connect-timeout 1 --max-time 2 -D /tmp/_p37_runs.hdr -o /tmp/_p37_runs.bin "$url" || true
    ct="$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/{print $0; exit}' /tmp/_p37_runs.hdr 2>/dev/null | tr -d '\r')"
    bytes="$(wc -c </tmp/_p37_runs.bin 2>/dev/null || echo 0)"
    if echo "$ct" | grep -qi 'application/json' && [ "${bytes:-0}" -gt 10 ]; then
      RID="$(python3 - <<'PY'
import json
j=json.load(open("/tmp/_p37_runs.bin","r",encoding="utf-8", errors="replace"))
runs=j.get("runs") or []
r0=runs[0] if runs and isinstance(runs[0], dict) else {}
print((r0.get("rid") or r0.get("id") or r0.get("run_id") or "").strip())
PY
)"
      if [ -n "${RID:-}" ]; then
        echo "$RID"
        return 0
      fi
    fi
    sleep 0.2
  done

  echo "[ERR] cannot pick RID from /api/vsp/runs (not stable JSON). Last response:"
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:/{print}' /tmp/_p37_runs.hdr 2>/dev/null || true
  head -c 240 /tmp/_p37_runs.bin 2>/dev/null || true
  echo
  return 2
}

check(){
  local rid="$1" fmt="$2"
  local url="$BASE/api/vsp/export?rid=$rid&fmt=$fmt"
  local out="/tmp/_p37_${fmt}.bin"
  local hdr="/tmp/_p37_${fmt}.hdr"
  echo "== export fmt=$fmt =="
  curl -sS -D "$hdr" -o "$out" "$url" || true
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:|^Content-Length:/{print}' "$hdr" || true
  echo "bytes=$(wc -c <"$out" 2>/dev/null || echo 0)"
  head -c 120 "$out"; echo
  echo
}

echo "== [0] warm =="
warm

echo "== [1] pick RID =="
RID="$(pick_rid)"
echo "RID=$RID"

check "$RID" html
check "$RID" pdf
check "$RID" zip
