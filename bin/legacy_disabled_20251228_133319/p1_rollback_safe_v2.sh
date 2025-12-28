#!/usr/bin/env bash
set -u
cd /home/test/Data/SECURITY_BUNDLE/ui || { echo "[ERR] cd failed"; exit 2; }

say(){ echo "[$(date +%H:%M:%S)] $*"; }
run(){ say "+ $*"; "$@" ; return $?; }

say "== rollback SAFE v2 =="

LAST="$(ls -1t wsgi_vsp_ui_gateway.py.bak_infer_overall_paging_* 2>/dev/null | head -n 1 || true)"
if [ -z "${LAST:-}" ]; then
  LAST="$(ls -1t wsgi_vsp_ui_gateway.py.bak_* 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${LAST:-}" ]; then
  say "[ERR] no wsgi backup found. Available:"
  ls -1 wsgi_vsp_ui_gateway.py.bak_* 2>/dev/null | head -n 20 || true
  exit 2
fi

say "[OK] using backup: $LAST"
run cp -f "$LAST" wsgi_vsp_ui_gateway.py || { say "[ERR] cp failed"; exit 2; }

say "== py_compile (non-fatal) =="
python3 -m py_compile wsgi_vsp_ui_gateway.py && say "[OK] py_compile OK" || say "[WARN] py_compile FAILED (see error above)"

say "== restart best-effort =="
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q '^vsp-ui-8910\.service'; then
  say "[INFO] systemd unit found: vsp-ui-8910.service"
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl restart vsp-ui-8910.service && say "[OK] restarted via sudo systemctl" || say "[WARN] sudo systemctl restart failed"
  else
    systemctl restart vsp-ui-8910.service && say "[OK] restarted via systemctl" || say "[WARN] systemctl restart failed"
  fi
else
  say "[INFO] no systemd unit; try single-owner start"
  rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
  if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
    run bin/p1_ui_8910_single_owner_start_v2.sh || say "[WARN] start script returned non-zero"
  else
    say "[WARN] missing bin/p1_ui_8910_single_owner_start_v2.sh"
  fi
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
say "== quick verify =="
curl -sS -I "$BASE/" | sed -n '1,8p' || say "[WARN] curl / failed"
curl -sS "$BASE/api/ui/runs_v3?limit=1" | head -c 220; echo || say "[WARN] curl runs_v3 failed"

say "== DONE =="
