#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="out_ci/ui_8910.error.log"
VENV_PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"

echo "== [1] systemd status (short) =="
systemctl --no-pager status "$SVC" -n 25 || true

echo "== [2] tail error log =="
if [ -f "$ERRLOG" ]; then
  tail -n 220 "$ERRLOG" || true
else
  echo "[WARN] missing $ERRLOG"
fi

echo "== [3] import wsgi module (should show real exception) =="
if [ -x "$VENV_PY" ]; then
  "$VENV_PY" - <<'PY' || true
import traceback
try:
    import wsgi_vsp_ui_gateway  # noqa
    print("[OK] imported wsgi_vsp_ui_gateway")
except Exception as e:
    print("[ERR] import failed:", repr(e))
    traceback.print_exc()
PY
else
  echo "[WARN] missing venv python: $VENV_PY"
fi

echo "== [4] grep markers around rid_latest patch =="
grep -n "VSP_P0_RID_LATEST_JSON_V1B\|/api/vsp/rid_latest" -n wsgi_vsp_ui_gateway.py | head -n 80 || true
