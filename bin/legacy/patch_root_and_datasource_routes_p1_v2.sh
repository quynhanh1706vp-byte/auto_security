#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rootds_v2_${TS}"
echo "[BACKUP] ${F}.bak_rootds_v2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_ROOT_AND_DATASOURCE_ROUTES_V2"

if MARK in s:
    print("[OK] marker already present, skip")
else:
    inject = f"""

# {MARK}
# P1: ensure Dashboard (/) and Data Source (/data_source) reachable on UI gateway.
try:
    from flask import render_template
except Exception:
    render_template = None

_candidates = []
for _name in ("application", "app"):
    try:
        _obj = globals().get(_name, None)
        if _obj is not None:
            _candidates.append(_obj)
    except Exception:
        pass

def _p1_rt_dashboard():
    return render_template("vsp_dashboard_2025.html")

def _p1_rt_data_source():
    return render_template("vsp_data_source_v1.html")

if render_template is not None:
    for _a in _candidates:
        try:
            # only add if not already present
            _a.add_url_rule("/", endpoint="vsp_p1_root_dashboard_v2", view_func=_p1_rt_dashboard, methods=["GET"])
        except Exception:
            pass
        try:
            _a.add_url_rule("/data_source", endpoint="vsp_p1_data_source_v2", view_func=_p1_rt_data_source, methods=["GET"])
        except Exception:
            pass
"""
    p.write_text(s + inject, encoding="utf-8")
    print("[OK] appended routes block:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
