#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_force_vsp5_${TS}"
echo "[BACKUP] ${F}.bak_force_vsp5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_FORCE_DEFAULT_VSP5_P1_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

# Try to replace any redirect('/') -> '/vsp4' to '/vsp5'
s2 = s
s2 = re.sub(r"(redirect\(\s*['\"])\/vsp4(['\"]\s*\))", r"redirect('/vsp5')", s2)
s2 = re.sub(r"(Location:\s*/vsp4)", r"Location: /vsp5", s2)

# Also patch common nav link label "href='/vsp4'" to vsp5 inside gateway if any inline HTML
s2 = s2.replace("href='/vsp4'", "href='/vsp5'")
s2 = s2.replace('href="/vsp4"', 'href="/vsp5"')

# Add a tiny forced redirect middleware at end as safety net (only for path == "/")
inject = r'''
# === VSP_P1_FORCE_DEFAULT_VSP5_P1_V1 ===
def _vsp_force_default_to_vsp5(environ, start_response, app=application):
    try:
        path = (environ.get("PATH_INFO") or "")
        if path == "/" or path == "":
            start_response("302 FOUND", [("Location","/vsp5")])
            return [b""]
    except Exception:
        pass
    return app(environ, start_response)

try:
    application = _vsp_force_default_to_vsp5
except Exception:
    pass
# === /VSP_P1_FORCE_DEFAULT_VSP5_P1_V1 ===
'''
s2 = s2 + "\n\n" + inject + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched default to /vsp5")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
