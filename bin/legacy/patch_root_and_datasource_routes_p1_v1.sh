#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rootds_${TS}"
echo "[BACKUP] ${F}.bak_rootds_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_ROOT_AND_DATASOURCE_ROUTES_V1"

if MARK in s:
    print("[OK] marker already present, skip")
else:
    inject = f"""

# {MARK}
# P1: ensure Dashboard (/) and Data Source (/data_source) pages are reachable on UI gateway.
try:
    from flask import render_template
except Exception:
    render_template = None

try:
    app  # noqa
except Exception:
    app = None

if app is not None and render_template is not None:
    @app.get("/")
    def vsp_root_dashboard_p1():
        return render_template("vsp_dashboard_2025.html")

    @app.get("/data_source")
    def vsp_data_source_p1():
        return render_template("vsp_data_source_v1.html")
"""
    p.write_text(s + inject, encoding="utf-8")
    print("[OK] appended routes block:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

# restart best-effort
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^vsp-ui-8910\.service'; then
  sudo systemctl restart vsp-ui-8910.service
  echo "[OK] restarted: vsp-ui-8910.service"
else
  echo "[WARN] systemd unit vsp-ui-8910.service not found (restart manually if needed)"
fi
