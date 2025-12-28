#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need date; need ls; need tail; need head; need node

JS1="static/js/vsp_dashboard_luxe_v1.js"
JS2="static/js/vsp_tabs4_autorid_v1.js"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

check_js(){
  local f="$1"
  if node --check "$f" >/dev/null 2>&1; then
    ok "syntax OK: $f"
    return 0
  else
    warn "syntax FAIL: $f"
    node --check "$f" || true
    return 1
  fi
}

restore_latest_bak(){
  local f="$1"
  local bak
  bak="$(ls -1 "${f}".bak_* 2>/dev/null | tail -n 1 || true)"
  if [ -z "$bak" ]; then
    warn "no backup found for $f"
    return 1
  fi
  cp -f "$f" "${f}.broken_${TS}"
  cp -f "$bak" "$f"
  ok "restored: $bak -> $f (saved broken as ${f}.broken_${TS})"
  return 0
}

echo "== [1] check current JS syntax =="
fail=0
check_js "$JS1" || fail=1
check_js "$JS2" || fail=1

if [ "$fail" -eq 1 ]; then
  echo "== [2] restore from latest backups =="
  restore_latest_bak "$JS1" || true
  restore_latest_bak "$JS2" || true
fi

echo "== [3] re-check syntax after restore =="
check_js "$JS1" || err "still broken: $JS1 (need a backup or manual fix)"
check_js "$JS2" || err "still broken: $JS2 (need a backup or manual fix)"

ok "DONE. Now HARD refresh browser (Ctrl+Shift+R) and confirm console has no SyntaxError."
