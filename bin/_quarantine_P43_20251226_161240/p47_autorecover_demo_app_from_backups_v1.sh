#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_autorecover_demo_app_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need grep; need python3; need sudo; need systemctl; need curl; need awk; need sed

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

APP="vsp_demo_app.py"
[ -f "$APP" ] || fail "missing $APP"

ok "== [P47-RECOVER] demo_app restore from backups =="
ok "svc=$SVC ts=$TS"

# Keep current broken file
cp -f "$APP" "${APP}.bak_before_autorecover_${TS}"
ok "backup current: ${APP}.bak_before_autorecover_${TS}"

# Candidate backups (newest first)
cands="$(ls -1t ${APP}.bak_* 2>/dev/null | grep -v 'bak_before_autorecover' | head -n 80 || true)"
[ -n "$cands" ] || fail "no backups found: ${APP}.bak_*"

tmp="$(mktemp -d /tmp/vsp_demo_recover_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

probe(){
  local url="$1"
  curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$url" 2>/dev/null || true
}

restart_and_check(){
  sudo systemctl restart "$SVC" || true
  # wait short
  for i in $(seq 1 20); do
    c1="$(probe http://127.0.0.1:8910/vsp5)"
    c2="$(probe http://127.0.0.1:8910/api/vsp/dashboard_extras_v1)"
    if [ "$c1" = "200" ] && [ "$c2" = "200" ]; then
      echo "OK"
      return 0
    fi
    sleep 0.4
  done
  echo "NO"
  return 1
}

try_one(){
  local bak="$1"
  local t="$tmp/try.py"
  cp -f "$bak" "$t"

  # minimal disable ONLY decorator lines for dashboard_extras_v1 (avoid endpoint overwrite)
  python3 - <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
pat = re.compile(r'(?m)^[ \t]*@app\.route\((["\'])/api/vsp/dashboard_extras_v1\1[^)]*\)\s*$')
s, n = pat.subn(lambda m: "# [DISABLED_BY_AUTORECOVER] " + m.group(0).lstrip(), s)
# loose fallback: any decorator line containing dashboard_extras_v1
pat2 = re.compile(r'(?m)^[ \t]*@app\.route\([^\\n]*dashboard_extras_v1[^\\n]*\)\s*$')
s, n2 = pat2.subn(lambda m: "# [DISABLED_BY_AUTORECOVER] " + m.group(0).lstrip(), s)
p.write_text(s, encoding="utf-8")
print(f"disabled_decorators exact={n} loose={n2}")
PY "$t" >>"$LOG" 2>&1 || true

  # compile test
  python3 -m py_compile "$t" >>"$LOG" 2>&1 || return 1

  # install
  cp -f "$APP" "${APP}.bak_before_install_${TS}"
  cp -f "$t" "$APP"
  python3 -m py_compile "$APP" >>"$LOG" 2>&1 || return 1
  ok "installed candidate: $bak"

  # restart + probe
  if restart_and_check >/dev/null 2>&1; then
    ok "SERVICE UP with $bak"
    ok "probe: /vsp5=200 and /api/vsp/dashboard_extras_v1=200"
    echo "$bak" > "$OUT/p47_recovered_from_${TS}.txt"
    return 0
  fi

  warn "candidate didn't boot cleanly: $bak"
  return 1
}

picked=""
while read -r bak; do
  [ -n "$bak" ] || continue
  ok "-- try $bak --"
  if try_one "$bak"; then
    picked="$bak"
    break
  fi
done <<<"$cands"

if [ -z "$picked" ]; then
  warn "no candidate succeeded; show status+journal+error tail"
  systemctl status "$SVC" --no-pager | tee -a "$LOG" >/dev/null || true
  sudo journalctl -u "$SVC" --no-pager -n 120 | tee -a "$LOG" >/dev/null || true
  tail -n 120 "$OUT/ui_8910.error.log" 2>/dev/null | tee -a "$LOG" >/dev/null || true
  fail "AUTO-RECOVER failed (see $LOG)"
fi

ok "DONE: recovered using $picked"
ok "log: $LOG"
