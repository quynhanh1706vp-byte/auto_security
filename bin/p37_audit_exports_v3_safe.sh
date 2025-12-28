#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_OVERRIDE="${RID_OVERRIDE:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need wc; need head; need date

warm(){
  for i in $(seq 1 80); do
    if curl -fsS --connect-timeout 2 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      echo "[OK] selfcheck ok (try#$i)"
      return 0
    fi
    sleep 0.2
  done
  echo "[ERR] selfcheck not OK"
  return 2
}

pick_rid(){
  if [ -n "$RID_OVERRIDE" ]; then
    echo "$RID_OVERRIDE"
    return 0
  fi

  local url="$BASE/api/vsp/runs?limit=5&offset=0"
  rm -f /tmp/_p37_runs.hdr /tmp/_p37_runs.bin || true

  for i in $(seq 1 80); do
    rm -f /tmp/_p37_runs.hdr /tmp/_p37_runs.bin || true
    # timeout cao hơn để tránh “2s là chết”
    curl -sS --connect-timeout 2 --max-time 8 -D /tmp/_p37_runs.hdr -o /tmp/_p37_runs.bin "$url" || true
    [ -f /tmp/_p37_runs.bin ] || : > /tmp/_p37_runs.bin
    [ -f /tmp/_p37_runs.hdr ] || : > /tmp/_p37_runs.hdr

    ct="$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/{print $0; exit}' /tmp/_p37_runs.hdr | tr -d '\r' || true)"
    bytes="$(wc -c </tmp/_p37_runs.bin 2>/dev/null || echo 0)"

    if echo "$ct" | grep -qi 'application/json' && [ "${bytes:-0}" -gt 20 ]; then
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

    sleep 0.25
  done

  echo "[ERR] cannot pick RID from /api/vsp/runs"
  echo "Last headers:"
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:/{print}' /tmp/_p37_runs.hdr || true
  echo "Last body head:"
  head -c 240 /tmp/_p37_runs.bin || true
  echo
  return 2
}

check(){
  local rid="$1" fmt="$2"
  local url="$BASE/api/vsp/export?rid=$rid&fmt=$fmt"
  local out="/tmp/_p37_${fmt}.bin"
  local hdr="/tmp/_p37_${fmt}.hdr"
  rm -f "$out" "$hdr" || true

  echo "== export fmt=$fmt =="
  curl -sS --connect-timeout 2 --max-time 20 -D "$hdr" -o "$out" "$url" || true
  [ -f "$out" ] || : > "$out"
  [ -f "$hdr" ] || : > "$hdr"

  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:|^Content-Length:/{print}' "$hdr" || true
  echo "bytes=$(wc -c <"$out" 2>/dev/null || echo 0)"
  head -c 160 "$out"; echo
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
