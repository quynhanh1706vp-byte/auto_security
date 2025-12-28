#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

echo "== [0] import check (will show real traceback) =="
set +e
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')" 2>&1 | sed -n '1,260p'
rc=$?
set -e
echo "[import_rc]=$rc"

echo "== [1] status/journal tail =="
sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
sudo journalctl -u "$SVC" -n 200 --no-pager || true

if [ "$rc" -ne 0 ]; then
  echo "== [2] rollback to latest bak_p3i_* =="
  bak="$(ls -1t ${W}.bak_p3i_* 2>/dev/null | head -n 1 || true)"
  if [ -z "${bak:-}" ]; then
    echo "[ERR] no ${W}.bak_p3i_* found to rollback"
    exit 2
  fi
  cp -f "$bak" "$W"
  echo "[RESTORE] $bak -> $W"

  echo "== [3] import check after rollback =="
  "$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK_AFTER_ROLLBACK')" 2>&1 | sed -n '1,220p'

  echo "== [4] restart service =="
  sudo systemctl restart "$SVC"
  sleep 0.6
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
    echo "[ERR] service still not active"
    sudo systemctl status "$SVC" --no-pager | sed -n '1,260p' || true
    sudo journalctl -u "$SVC" -n 220 --no-pager || true
    exit 3
  }
else
  echo "[INFO] import OK, service may still fail due to other reasons; try restart anyway"
  sudo systemctl restart "$SVC" || true
  sleep 0.6
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || true
fi

echo "[DONE] p3i_rescue_rollback_restart_v1"
