#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rootforce_v3_${TS}"
echo "[BACKUP] ${F}.bak_rootforce_v3_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_FORCE_ROOT_200_DASHBOARD_V3"

if MARK in s:
    print("[OK] marker already present, skip")
else:
    inject = f"""

# {MARK}
# P1: force '/' to return dashboard template (200), even if existing routes/middleware mapped '/'.
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

def _p1_root_dashboard_v3():
    return render_template("vsp_dashboard_2025.html")

if render_template is not None:
    for _a in _candidates:
        try:
            # If any rule already exists for '/', override its endpoint handler
            _over = 0
            for _r in list(getattr(_a, "url_map", []).iter_rules()):
                if getattr(_r, "rule", None) == "/" and "GET" in getattr(_r, "methods", set()) and getattr(_r, "endpoint", "") != "static":
                    ep = _r.endpoint
                    try:
                        _a.view_functions[ep] = _p1_root_dashboard_v3
                        _over += 1
                    except Exception:
                        pass
            # If no rule existed, add one
            if _over == 0:
                try:
                    _a.add_url_rule("/", endpoint="vsp_p1_root_dashboard_v3", view_func=_p1_root_dashboard_v3, methods=["GET"])
                except Exception:
                    pass
        except Exception:
            pass
"""
    p.write_text(s + inject, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
