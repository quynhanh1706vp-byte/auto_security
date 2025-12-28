#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_app_application_${TS}"
echo "[BACKUP] ${F}.bak_app_application_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

orig=s

# 1) Remove dangerous rebind: app = application
s = re.sub(r'(?m)^(\s*)app\s*=\s*application\s*$', r'\1# VSP_P1: removed unsafe "app = application" (keep Flask app stable)', s)

# 2) Remove dangerous: app = None
s = re.sub(r'(?m)^(\s*)app\s*=\s*None\s*$', r'\1# VSP_P1: removed unsafe "app = None"\n\1_app_disabled = None', s)

# 3) Redirect wrapper patterns: app = wrap(app...)  -> application = wrap(application...)
def _wrap_line(m):
    indent=m.group(1); fn=m.group(2)
    return f"{indent}# VSP_P1: redirect wrapper from app->application\n{indent}application = {fn}(application"
s = re.sub(r'(?m)^(\s*)app\s*=\s*([A-Za-z_][\w\.]*)\(\s*app\b', _wrap_line, s)

# 4) Ensure stable exports appended once
marker = "VSP_P1_EXPORT_APP_APPLICATION_V1"
if marker not in s:
    s += "\n\n# --- {} (do not edit below) ---\n".format(marker)
    s += "try:\n    flask_app\nexcept NameError:\n    flask_app = globals().get('app')\n"
    s += "try:\n    application\nexcept NameError:\n    application = flask_app\n"
    s += "# Keep legacy name 'app' as Flask for blueprints/routes; gunicorn should use 'application'\n"
    s += "app = flask_app\n"

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched wsgi (conservative)")
else:
    print("[WARN] no changes applied (patterns not found)")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

echo "[NEXT] 1) run gate: bash bin/p1_gate_wsgi_no_app_reassign_v1.sh"
echo "[NEXT] 2) restart service if needed: systemctl restart vsp-ui-8910.service"
echo "[NEXT] 3) run UI spec gate: bash bin/p1_ui_spec_gate_v1.sh"
