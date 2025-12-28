#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

echo "== [0] import check (trace if broken) =="
set +e
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')" 2>&1 | sed -n '1,220p'
rc=$?
set -e
echo "[import_rc]=$rc"

echo "== [1] status/journal (before) =="
sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
sudo journalctl -u "$SVC" -n 180 --no-pager || true

echo "== [2] rollback to latest bak_p3k2_* =="
bak="$(ls -1t ${W}.bak_p3k2_* 2>/dev/null | head -n 1 || true)"
if [ -z "${bak:-}" ]; then
  echo "[ERR] no ${W}.bak_p3k2_* found"
  exit 2
fi
cp -f "$bak" "$W"
echo "[RESTORE] $bak -> $W"

echo "== [3] import check after rollback =="
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK_AFTER_ROLLBACK')" 2>&1 | sed -n '1,160p'

echo "== [4] restart service =="
sudo systemctl restart "$SVC"
sleep 0.6
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] still not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,260p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 3
}

echo "[DONE] p3k2_rescue_rollback_restart_v1"
