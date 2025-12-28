#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_settingsboot_${TS}"
echo "[BACKUP] ${F}.bak_settingsboot_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_SETTINGS_BOOT_INJECT_MW_V1"

if MARK in s:
    print("[OK] marker already present, skip")
else:
    inject = f"""

# {MARK}
# P1: /settings page is served by custom HTML; inject boot script tag if missing.
try:
    from flask import request
except Exception:
    request = None

def _vsp_p1_inject_boot(resp):
    try:
        if request is None:
            return resp
        if not request.path.startswith("/settings"):
            return resp
        ct = (resp.headers.get("Content-Type","") or "").lower()
        if "text/html" not in ct:
            return resp

        data = resp.get_data(as_text=True)
        if "vsp_p1_page_boot_v1.js" in data:
            return resp

        tag = '<script src="/static/js/vsp_p1_page_boot_v1.js?v=VSP_P1_PAGE_BOOT_V1"></script>'
        if "</body>" in data.lower():
            # insert before </body> (case-insensitive)
            idx = data.lower().rfind("</body>")
            data = data[:idx] + "\\n" + tag + "\\n" + data[idx:]
        else:
            data = data + "\\n" + tag + "\\n"

        resp.set_data(data)
        # length may change
        try:
            resp.headers.pop("Content-Length", None)
        except Exception:
            pass
        return resp
    except Exception:
        return resp

for _name in ("application","app"):
    try:
        _a = globals().get(_name)
        if _a is not None:
            try:
                _a.after_request(_vsp_p1_inject_boot)
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
