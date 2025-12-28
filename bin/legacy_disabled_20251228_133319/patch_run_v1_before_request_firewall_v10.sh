#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_firewall_${TS}"
echo "[BACKUP] $F.bak_runv1_firewall_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_CONTRACT_FIREWALL_V10 ==="
END = "# === END VSP_RUN_V1_CONTRACT_FIREWALL_V10 ==="

if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# Ensure imports exist (safe add; won't break)
if not re.search(r"(?m)^\s*import\s+json\s*$", t):
    t = "import json\n" + t
if not re.search(r"(?m)^\s*import\s+os\s*$", t):
    t = "import os\n" + t

# We need access to `app`. Insert block after the first occurrence of "app = Flask("
m = re.search(r"(?m)^\s*app\s*=\s*Flask\(", t)
ins_at = m.end() if m else 0

block = f"""

{TAG}
# Commercial contract firewall:
# - Make POST /api/vsp/run_v1 accept {{}} (or missing JSON) by injecting defaults
# - Do it *before* any handler/blueprint reads request.get_json()
try:
    from flask import request
except Exception:
    request = None

if request is not None:
    @app.before_request
    def __vsp_run_v1_contract_firewall_v10():
        try:
            if request.method != "POST": 
                return None
            if request.path != "/api/vsp/run_v1":
                return None

            # Read whatever client sent (silent), but we will normalize.
            try:
                data = request.get_json(silent=True)
            except Exception:
                data = None
            if not isinstance(data, dict):
                data = {{}}

            # Inject defaults only if missing required commercial fields
            # (Keep user's explicit values if provided)
            if data.get("target_type") != "path" or not data.get("target"):
                data.setdefault("mode", "local")
                data.setdefault("profile", "FULL_EXT")
                data.setdefault("target_type", "path")
                data.setdefault("target", "/home/test/Data/SECURITY-10-10-v4")

            # Also normalize env_overrides shape if present
            eo = data.get("env_overrides")
            if eo is not None and not isinstance(eo, dict):
                data["env_overrides"] = {{}}

            # Critical: force Werkzeug JSON cache so ANY downstream get_json() sees our normalized dict
            try:
                request._cached_json = (data, data)
            except Exception:
                pass

            return None
        except Exception:
            return None
{END}
"""

t = t[:ins_at] + block + t[ins_at:]
p.write_text(t, encoding="utf-8")
print("[OK] inserted run_v1 contract firewall")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"

echo "== restart service =="
systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify: POST {} to /api/vsp/run_v1 must be 200 =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" -d '{}' | sed -n '1,120p'
