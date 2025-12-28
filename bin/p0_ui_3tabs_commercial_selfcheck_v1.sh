#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need sed; need wc; need egrep

OK=0; WARN=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR] $*"; ERR=$((ERR+1)); }

tab(){
  local path="$1"
  echo; echo "==================== TAB $path ===================="
  local h="/tmp/vsp_tab_h.$$" b="/tmp/vsp_tab_b.$$"
  curl -sS -I "$BASE$path" >"$h" || true
  curl -sS "$BASE$path" -o "$b" || true
  sed -n '1,12p' "$h" || true
  local n; n="$(wc -c <"$b" 2>/dev/null || echo 0)"
  echo "BODY_BYTES=$n"
  if grep -q "HTTP/1.1 200" "$h" && [ "$n" -ge 400 ]; then ok "$path 200 and bytes>=400"; else warn "$path weak (need 200 and bytes>=400)"; fi
  rm -f "$h" "$b" || true
}

api_json(){
  local path="$1"
  echo; echo "==================== API $path ===================="
  local b="/tmp/vsp_api_b.$$"
  local http; http="$(curl -sS -w "%{http_code}" "$BASE$path" -o "$b" || true)"
  echo "HTTP=$http BYTES=$(wc -c <"$b" 2>/dev/null || echo 0)"
  head -c 220 "$b"; echo
  python3 - <<PY >/dev/null 2>&1 && ok "$path json ok" || warn "$path json parse failed"
import json; json.load(open("$b","r",encoding="utf-8",errors="replace"))
PY
  rm -f "$b" || true
}

echo "== Tabs =="
tab "/runs"
tab "/data_source"
tab "/settings"

echo
echo "== APIs =="
api_json "/api/vsp/ui_status_v1"
api_json "/api/vsp/runs?limit=1"
api_json "/api/vsp/release_latest"

echo
echo "== Audit pack HEAD (lite+full) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
echo "[RID]=$RID"
curl -sS -I "$BASE/api/vsp/audit_pack_download?rid=$RID&lite=1" | egrep -i 'HTTP/|content-type|content-disposition|x-vsp-audit-pack|content-length' || true
curl -sS -I "$BASE/api/vsp/audit_pack_download?rid=$RID" | egrep -i 'HTTP/|content-type|content-disposition|x-vsp-audit-pack|content-length' || true

echo
echo "== SUMMARY =="
echo "OK=$OK WARN=$WARN ERR=$ERR"
if [ "$ERR" -gt 0 ]; then echo "STATUS=RED"; elif [ "$WARN" -gt 0 ]; then echo "STATUS=AMBER"; else echo "STATUS=GREEN"; fi
