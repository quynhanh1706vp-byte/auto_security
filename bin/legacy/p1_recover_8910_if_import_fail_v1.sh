#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ls; need head; need sudo; need systemctl; need tail; need grep

PY="./.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

echo "== import check (wsgi_vsp_ui_gateway) =="
set +e
"$PY" - <<'PY'
import importlib, traceback
try:
    m=importlib.import_module("wsgi_vsp_ui_gateway")
    print("[OK] import wsgi_vsp_ui_gateway")
    app=getattr(m,"application",None)
    print("[OK] application=", type(app))
except Exception as e:
    print("[ERR] import failed:", e)
    traceback.print_exc()
    raise SystemExit(4)
PY
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
  echo "[WARN] import failed -> rollback latest healthz_wsgimw backups"
  for f in wsgi_vsp_ui_gateway.py vsp_demo_app.py; do
    bak="$(ls -1t ${f}.bak_healthz_wsgimw_* 2>/dev/null | head -n1 || true)"
    if [ -n "$bak" ] && [ -f "$bak" ]; then
      cp -f "$bak" "$f"
      echo "[OK] restored $f <= $bak"
    else
      echo "[WARN] no backup for $f"
    fi
  done
  "$PY" -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"
fi

echo "== restart service =="
sudo systemctl restart vsp-ui-8910.service || true
sudo systemctl status vsp-ui-8910.service --no-pager | sed -n '1,30p' || true

echo "== probe :8910 =="
curl -fsS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p' || true
