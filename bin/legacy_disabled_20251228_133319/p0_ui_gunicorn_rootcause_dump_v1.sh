#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
ERR="out_ci/ui_8910.error.log"

echo "== [1] last error log =="
if [ -f "$ERR" ]; then
  tail -n 180 "$ERR"
else
  echo "[WARN] missing $ERR"
fi

echo
echo "== [2] import check wsgi_vsp_ui_gateway:application =="
"$PY" - <<'PY'
import traceback
try:
    import wsgi_vsp_ui_gateway as m
    print("IMPORT_OK wsgi_vsp_ui_gateway")
    print("application=", getattr(m,"application",None))
except Exception as e:
    print("IMPORT_FAIL wsgi_vsp_ui_gateway:", repr(e))
    traceback.print_exc()
PY

echo
echo "== [3] import check vsp_demo_app (optional) =="
"$PY" - <<'PY'
import traceback
try:
    import vsp_demo_app as m
    print("IMPORT_OK vsp_demo_app")
    print("has app=", hasattr(m,"app"), "app=", getattr(m,"app",None))
except Exception as e:
    print("IMPORT_FAIL vsp_demo_app:", repr(e))
    traceback.print_exc()
PY
