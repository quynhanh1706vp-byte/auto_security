#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_dedupe_runapi_bp_all_${TS}"
echo "[BACKUP] $F.bak_dedupe_runapi_bp_all_${TS}"

python3 - << 'PY'
import re
from pathlib import Path
p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

pat = re.compile(r"(?m)^(?P<indent>[ \t]*)app\.register_blueprint\((?P<args>bp_vsp_run_api_v1[^)]*)\)\s*$")
def repl(m):
    ind = m.group("indent")
    args = m.group("args").strip()
    return (
        f"{ind}bp_name = getattr(bp_vsp_run_api_v1, 'name', 'vsp_run_api_v1')\n"
        f"{ind}if bp_name in getattr(app, 'blueprints', {{}}):\n"
        f"{ind}    print(f\"[VSP_RUN_API] skip blueprint already registered: {{bp_name}}\")\n"
        f"{ind}else:\n"
        f"{ind}    app.register_blueprint({args})\n"
        f"{ind}    print(\"[VSP_RUN_API] OK registered: /api/vsp/run_v1 + /api/vsp/run_status_v1/<REQ_ID>\")"
    )

new_txt, n = pat.subn(repl, txt)
if n == 0:
    raise SystemExit("[ERR] cannot find any app.register_blueprint(bp_vsp_run_api_v1...) lines to patch")
p.write_text(new_txt, encoding="utf-8")
print(f"[OK] patched {n} register_blueprint(bp_vsp_run_api_v1...) call(s)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
