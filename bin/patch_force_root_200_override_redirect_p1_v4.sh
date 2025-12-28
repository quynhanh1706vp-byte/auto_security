#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_root200v4_${TS}"
echo "[BACKUP] ${F}.bak_root200v4_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_FORCE_ROOT_200_OVERRIDE_REDIRECT_V4"
if MARK in s:
    print("[OK] marker already present, skip")
else:
    inject = f"""

# {MARK}
# Ensure '/' returns 200 HTML (dashboard) even if existing route redirects to /vsp4
try:
    from flask import render_template, redirect
except Exception:
    render_template = None
    redirect = None

def _vsp_p1_root_200_v4():
    # Prefer dashboard template if exists; fallback to redirect /vsp5
    if render_template is not None:
        try:
            return render_template("vsp_dashboard_2025.html")
        except Exception:
            pass
        try:
            return render_template("vsp_5tabs_enterprise_v2.html")
        except Exception:
            pass
    if redirect is not None:
        return redirect("/vsp5")
    return ("OK", 200)

for _name in ("application","app"):
    try:
        _a = globals().get(_name)
        if _a is None:
            continue
        # Override any existing endpoint mapped to '/'
        try:
            _over = 0
            for _r in list(_a.url_map.iter_rules()):
                if getattr(_r, "rule", None) == "/" and getattr(_r, "endpoint", "") != "static":
                    try:
                        _a.view_functions[_r.endpoint] = _vsp_p1_root_200_v4
                        _over += 1
                    except Exception:
                        pass
            if _over == 0:
                try:
                    _a.add_url_rule("/", endpoint="vsp_p1_root_200_v4", view_func=_vsp_p1_root_200_v4, methods=["GET"])
                except Exception:
                    pass
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
