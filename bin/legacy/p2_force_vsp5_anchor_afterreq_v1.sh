#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_AFTERREQ_VSP5_ANCHOR_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_afterreq_vsp5_${TS}"
echo "[BACKUP] ${F}.bak_afterreq_vsp5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

MARK = "VSP_P2_AFTERREQ_VSP5_ANCHOR_V1"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

block = r'''
# ===================== VSP_P2_AFTERREQ_VSP5_ANCHOR_V1 =====================
try:
    from flask import request
except Exception:
    request = None

def _vsp__inject_vsp5_anchor(html: str) -> str:
    try:
        if not isinstance(html, str):
            return html
        if 'id="vsp-dashboard-main"' in html:
            return html
        needle = '<div id="vsp5_root"></div>'
        if needle in html:
            return html.replace(
                needle,
                f'<!-- {MARK} -->\n  <div id="vsp-dashboard-main"></div>\n\n  <div id="vsp5_root"></div>',
                1
            )
    except Exception:
        pass
    return html

try:
    _VSP_APP = app  # common name
except Exception:
    try:
        _VSP_APP = application  # wsgi export
    except Exception:
        _VSP_APP = None

if _VSP_APP is not None:
    @_VSP_APP.after_request
    def _vsp__afterreq_vsp5_anchor(resp):
        try:
            if request is None:
                return resp
            if request.path != "/vsp5":
                return resp
            ct = (resp.content_type or "").lower()
            if "text/html" not in ct:
                return resp
            body = resp.get_data(as_text=True)
            body2 = _vsp__inject_vsp5_anchor(body)
            if body2 != body:
                resp.set_data(body2)
        except Exception:
            pass
        return resp
# ===================== /VSP_P2_AFTERREQ_VSP5_ANCHOR_V1 =====================
'''

# append near end of file to avoid interfering with existing definitions
s2 = s + ("\n\n" + block + "\n")
p.write_text(s2)
print("[OK] appended after_request injector:", MARK)
PY

python3 -m py_compile "$F"

echo "== restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC"
fi

echo "== verify /vsp5 contains marker+anchor =="
HTML="$(curl -fsS "$BASE/vsp5")"
echo "$HTML" | grep -n 'VSP_P2_AFTERREQ_VSP5_ANCHOR_V1' | head -n 2 || echo "[ERR] marker missing"
echo "$HTML" | grep -n 'id="vsp-dashboard-main"' | head -n 2 || echo "[ERR] anchor missing"
