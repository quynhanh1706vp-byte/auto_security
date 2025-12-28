#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT="${VSP_UI_PORT:-8910}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:${PORT}}"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_${PORT}.error.log"

echo "== time =="; date -Is
echo "== svc =="; sudo systemctl is-active "$SVC" || true
echo "== status (short) =="; sudo systemctl status "$SVC" --no-pager -l | sed -n '1,120p' || true
echo "== show (pid/exec) =="; sudo systemctl show "$SVC" -p ExecMainStatus -p ExecMainPID -p MainPID -p ActiveEnterTimestamp -p FragmentPath --no-pager || true

echo "== listen check (ss) =="
(ss -ltnp || true) | grep -E "(:${PORT}\b)" || echo "[WARN] nothing listening on :${PORT}"

echo "== curl check =="
curl -vk --connect-timeout 1 --max-time 3 "$BASE/api/vsp" || true
echo
curl -vk --connect-timeout 1 --max-time 3 "$BASE/vsp5" || true
echo

echo "== journalctl last 200 =="
sudo journalctl -u "$SVC" -n 200 --no-pager || true

echo "== errlog tail =="
if [ -f "$ERRLOG" ]; then
  tail -n 200 "$ERRLOG" || true
else
  echo "[INFO] no errlog: $ERRLOG"
fi

echo "== grep common fatal patterns in ui code =="
grep -RIn --line-number --exclude='*.bak_*' --exclude='*.disabled_*' \
  'Traceback|SyntaxError|IndentationError|ModuleNotFoundError|Address already in use|EADDRINUSE|ImportError' \
  vsp_demo_app.py wsgi_vsp_ui_gateway.py 2>/dev/null || true

echo "[DONE] triage"
