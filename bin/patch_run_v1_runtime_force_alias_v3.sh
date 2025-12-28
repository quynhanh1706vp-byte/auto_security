#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_force_runtime_${TS}"
echo "[BACKUP] $F.bak_runv1_force_runtime_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_FORCE_ALIAS_RUNTIME_V3 ==="
END = "# === END VSP_RUN_V1_FORCE_ALIAS_RUNTIME_V3 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# Guard: ensure vsp_run_v1_alias exists in file
if not re.search(r"(?m)^def\s+vsp_run_v1_alias\s*\(", t):
    raise SystemExit("[ERR] vsp_run_v1_alias() not found in vsp_demo_app.py")

block = f"""

{TAG}
# Commercial: force the *actual bound endpoint* of /api/vsp/run_v1 (POST) to call vsp_run_v1_alias()
try:
    _n = 0
    for _r in app.url_map.iter_rules():
        if _r.rule == "/api/vsp/run_v1" and ("POST" in (_r.methods or set())):
            if _r.endpoint in app.view_functions:
                app.view_functions[_r.endpoint] = vsp_run_v1_alias
                _n += 1
    print("[VSP_RUN_V1_FORCE_ALIAS_RUNTIME_V3] patched_rules=", _n)
except Exception as _e:
    print("[VSP_RUN_V1_FORCE_ALIAS_RUNTIME_V3][WARN]", repr(_e))
{END}
"""

t = t.rstrip() + "\n" + block + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] appended runtime force-alias block")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify POST {} to /api/vsp/run_v1 (should NOT 400) =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d '{}' | sed -n '1,120p'
