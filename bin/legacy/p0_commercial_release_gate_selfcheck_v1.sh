#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need head; need tail; need date; need mktemp

OK=0; AMBER=0; RED=0
ok(){ echo -e "[GREEN] $*"; OK=$((OK+1)); }
amber(){ echo -e "[AMBER] $*"; AMBER=$((AMBER+1)); }
red(){ echo -e "[RED] $*"; RED=$((RED+1)); }

tmp="$(mktemp -d /tmp/vsp_release_gate_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "== VSP P0 COMMERCIAL RELEASE GATE SELFHECK V1 =="
echo "BASE=$BASE"
echo "TS=$(date +%F' '%T)"
echo

# --- 0) service status (best effort) ---
echo "== [0] service status =="
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet vsp-ui-8910.service; then ok "vsp-ui-8910.service active"
  else
    red "vsp-ui-8910.service NOT active"
    systemctl status vsp-ui-8910.service --no-pager -l | sed -n '1,40p' || true
  fi
else
  amber "systemctl not available (skip service check)"
fi
echo

# helper: fetch
fetch(){
  local path="$1"
  local out_h="$2"
  local out_b="$3"
  curl -sS --max-time 8 -D "$out_h" -o "$out_b" "$BASE$path" || return 1
  return 0
}

# --- 1) tabs reachable + has known marker ---
echo "== [1] tabs reachable =="
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  H="$tmp/h$(echo "$p"|tr '/' '_').txt"
  B="$tmp/b$(echo "$p"|tr '/' '_').html"
  if fetch "$p" "$H" "$B"; then
    code="$(sed -n '1s/HTTP\/[0-9.]* \([0-9][0-9][0-9]\).*/\1/p' "$H" | head -n1)"
    if [ "$code" = "200" ]; then
      # minimal markers
      if grep -qiE '<html|<!doctype html|id="vsp' "$B"; then ok "$p HTTP 200 + html ok"
      else amber "$p HTTP 200 but html marker weak"
      fi
    else
      red "$p HTTP $code"
    fi
  else
    red "$p fetch failed"
  fi
done
echo

# --- 2) core APIs must respond JSON ---
echo "== [2] core APIs =="
apis=(
  "/api/vsp/runs?limit=1"
  "/api/vsp/rid_latest"
  "/api/vsp/release_latest"
)
for p in "${apis[@]}"; do
  H="$tmp/hapi$(echo "$p"|tr '/?&=' '_').txt"
  B="$tmp/bapi$(echo "$p"|tr '/?&=' '_').json"
  if fetch "$p" "$H" "$B"; then
    ct="$(grep -i '^Content-Type:' "$H" | head -n1 | tr -d '\r')"
    if echo "$ct" | grep -qi 'application/json'; then
      if python3 -c 'import json,sys; json.load(open(sys.argv[1],"r",encoding="utf-8"));' "$B" >/dev/null 2>&1; then
        ok "$p JSON ok"
      else
        red "$p JSON parse fail"
        head -c 200 "$B"; echo
      fi
    else
      red "$p Content-Type not JSON: $ct"
      head -c 200 "$B"; echo
    fi
  else
    red "$p fetch failed"
  fi
done
echo

# --- 3) top findings contract check ---
echo "== [3] top findings contract =="
RID="$(curl -fsS --max-time 5 "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("rid") or "").strip())' 2>/dev/null || true)"
[ -n "$RID" ] || RID="VSP_CI_20251218_114312"
H="$tmp/top.h"; B="$tmp/top.b"
rm -f "$H" "$B"
if fetch "/api/vsp/top_findings_v1?rid=$RID&limit=5" "$H" "$B"; then
  if python3 - "$B" <<'PY' >/tmp/topchk.out 2>/tmp/topchk.err; then
import json,sys
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
ok=j.get("ok"); total=j.get("total"); rid_used=j.get("rid_used"); lim=j.get("limit_applied"); trunc=j.get("items_truncated")
if ok is not True: raise SystemExit(2)
if not isinstance(total,int): raise SystemExit(3)
print("ok",ok,"rid_used",rid_used,"total",total,"limit",lim,"trunc",trunc)
PY
    ok "top_findings_v1 contract OK: $(cat /tmp/topchk.out)"
  else
    amber "top_findings_v1 contract not OK (may be empty data)"; cat "$B" | head -c 260; echo
  fi
else
  red "top_findings_v1 fetch failed"
fi
echo

# --- 4) no debug/internal leaks (static + templates + py) ---
echo "== [4] no debug/internal wording leaks (best-effort) =="
cd /home/test/Data/SECURITY_BUNDLE/ui || true
pat='UNIFIED FROM|findings_unified\.json|/home/test/Data/|DEBUG|not available|N/A'
hit=0
if grep -RIn --line-number --exclude='*.bak_*' --exclude='*.disabled_*' -E "$pat" static/js templates *.py 2>/dev/null | head -n 10 >"$tmp/leaks.txt"; then
  if [ -s "$tmp/leaks.txt" ]; then
    amber "found possible leaks (show first 10):"
    cat "$tmp/leaks.txt"
    hit=1
  fi
fi
[ "$hit" -eq 0 ] && ok "no obvious debug/path leaks in static/js + templates + *.py"
echo

# --- 5) evidence logs present ---
echo "== [5] evidence/log pointers =="
if [ -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log ]; then
  ok "error log exists: out_ci/ui_8910.error.log"
else
  amber "missing out_ci/ui_8910.error.log"
fi
if [ -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.access.log ]; then
  ok "access log exists: out_ci/ui_8910.access.log"
else
  amber "missing out_ci/ui_8910.access.log"
fi
echo

echo "== SUMMARY =="
echo "GREEN=$OK AMBER=$AMBER RED=$RED"
if [ "$RED" -gt 0 ]; then
  echo "[VERDICT] NOT READY (has RED)"
  exit 2
fi
if [ "$AMBER" -gt 0 ]; then
  echo "[VERDICT] NEAR READY (only AMBER left)"
  exit 0
fi
echo "[VERDICT] READY (all GREEN)"
