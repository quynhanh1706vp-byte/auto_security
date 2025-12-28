#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

pick_latest() {
  ls -1t "$1" 2>/dev/null | head -n 1 || true
}

echo "== 1) stop services =="
sudo systemctl stop vsp-ui-8910 2>/dev/null || true
sudo systemctl stop vsp-ui-8911-dev 2>/dev/null || true

echo "== 2) restore vsp_demo_app.py from latest backup =="
B="$(pick_latest "vsp_demo_app.py.bak_*")"
if [ -z "$B" ]; then
  echo "[ERR] no backup found for vsp_demo_app.py.bak_*"
  exit 1
fi
cp -f "$B" vsp_demo_app.py
echo "[OK] restored vsp_demo_app.py <= $B"

echo "== 3) restore template from latest backup =="
TB="$(pick_latest "templates/vsp_dashboard_2025.html.bak_*")"
if [ -n "$TB" ]; then
  cp -f "$TB" templates/vsp_dashboard_2025.html
  echo "[OK] restored template <= $TB"
else
  echo "[WARN] no template backup found (skipped)"
fi

echo "== 4) remove broken degraded hook if exists =="
rm -f static/js/vsp_degraded_panel_hook_v3.js 2>/dev/null || true

echo "== 5) syntax check =="
/home/test/Data/SECURITY_BUNDLE/.venv/bin/python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile vsp_demo_app.py"

echo "== 6) start services back =="
sudo systemctl start vsp-ui-8910
sudo systemctl start vsp-ui-8911-dev

sleep 1
echo "== 7) healthz =="
curl -sS -o /dev/null -w "healthz_8910 HTTP=%{http_code}\n" http://127.0.0.1:8910/healthz || true
curl -sS -o /dev/null -w "healthz_8911 HTTP=%{http_code}\n" http://127.0.0.1:8911/healthz || true

echo "== 8) if still down, show journal tail =="
if ! curl -sS http://127.0.0.1:8910/healthz >/dev/null 2>&1; then
  sudo journalctl -u vsp-ui-8910 -n 80 --no-pager || true
fi
if ! curl -sS http://127.0.0.1:8911/healthz >/dev/null 2>&1; then
  sudo journalctl -u vsp-ui-8911-dev -n 80 --no-pager || true
fi
