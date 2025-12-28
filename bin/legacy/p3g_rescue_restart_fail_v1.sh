#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

echo "== [0] quick import check (shows real traceback if broken) =="
set +e
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')" 2>&1 | sed -n '1,220p'
rc=$?
set -e
echo "[import_rc]=$rc"

echo "== [1] systemctl status (before) =="
sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true

echo "== [2] journal tail (before) =="
sudo journalctl -u "$SVC" -n 160 --no-pager || true

echo "== [3] try restart =="
set +e
sudo systemctl restart "$SVC"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  echo "[ERR] restart failed rc=$rc"
  echo "== [4] status (after fail) =="
  sudo systemctl status "$SVC" --no-pager | sed -n '1,260p' || true
  echo "== [5] journal tail (after fail) =="
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  echo
  echo "[HINT] If you see a Python traceback, paste it here. We'll patch exactly that file/line."
  exit 3
fi

sleep 0.6
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active after restart"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,260p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 4
}

echo "== [6] health =="
curl -fsS "http://127.0.0.1:8910/api/vsp/rid_latest" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("rid_latest=",j.get("rid"),"mode=",j.get("mode"))'
echo "[DONE] p3g_rescue_restart_fail_v1"
