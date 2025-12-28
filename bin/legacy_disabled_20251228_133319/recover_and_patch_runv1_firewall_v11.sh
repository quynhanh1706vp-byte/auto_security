#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [0] stop service =="
systemctl --user stop vsp-ui-8910.service 2>/dev/null || true
sleep 1

echo "== [1] pick latest compiling backup =="
best=""
for f in $(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true); do
  if python3 -m py_compile "$f" >/dev/null 2>&1; then
    best="$f"; break
  fi
done

if [ -n "$best" ]; then
  echo "[OK] restore from: $best"
  cp -f "$best" vsp_demo_app.py
else
  echo "[WARN] no compiling backup found; will try to fix current file"
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f vsp_demo_app.py "vsp_demo_app.py.bak_firewall_v11_${TS}"
echo "[BACKUP] vsp_demo_app.py.bak_firewall_v11_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Remove broken V10 blocks if any (safe cleanup)
t = re.sub(r"(?ms)\n?\s*# === VSP_RUN_V1_CONTRACT_FIREWALL_V10 ===.*?# === END VSP_RUN_V1_CONTRACT_FIREWALL_V10 ===\s*\n?", "\n", t)

TAG = "# === VSP_RUN_V1_CONTRACT_FIREWALL_V11 ==="
END = "# === END VSP_RUN_V1_CONTRACT_FIREWALL_V11 ==="
if TAG in t:
    print("[OK] already has V11")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

# Ensure imports exist (minimal, safe)
if not re.search(r"(?m)^\s*import\s+json\s*$", t):
    t = "import json\n" + t
if not re.search(r"(?m)^\s*import\s+os\s*$", t):
    t = "import os\n" + t

# Find the first "app = Flask(" statement and insert AFTER the statement closes (paren-balanced)
m = re.search(r"(?m)^\s*app\s*=\s*Flask\s*\(", t)
if not m:
    raise SystemExit("[ERR] cannot find app = Flask( ... ) to anchor patch")

start = m.start()

# Walk forward tracking parentheses depth from the first '(' after 'Flask'
i = m.end() - 1  # points at '('
depth = 0
seen = False
n = len(t)
while i < n:
    ch = t[i]
    if ch == "(":
        depth += 1
        seen = True
    elif ch == ")":
        depth -= 1
        if seen and depth == 0:
            # insert after end-of-line of the closing paren
            nl = t.find("\n", i)
            if nl == -1:
                ins_at = n
            else:
                ins_at = nl + 1
            break
    i += 1
else:
    raise SystemExit("[ERR] failed to find closing ')' of app = Flask(...)")

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
    def __vsp_run_v1_contract_firewall_v11():
        try:
            if request.method != "POST":
                return None
            if request.path != "/api/vsp/run_v1":
                return None

            try:
                data = request.get_json(silent=True)
            except Exception:
                data = None
            if not isinstance(data, dict):
                data = {{}}

            # Defaults (commercial)
            if data.get("target_type") != "path" or not data.get("target"):
                data.setdefault("mode", "local")
                data.setdefault("profile", "FULL_EXT")
                data.setdefault("target_type", "path")
                data.setdefault("target", "/home/test/Data/SECURITY-10-10-v4")

            eo = data.get("env_overrides")
            if eo is not None and not isinstance(eo, dict):
                data["env_overrides"] = {{}}

            # Force Werkzeug/Flask JSON cache (avoid tuple schema issues)
            try:
                request._cached_json = {{False: data, True: data}}
            except Exception:
                pass
            return None
        except Exception:
            return None
{END}
"""

t = t[:ins_at] + block + t[ins_at:]
p.write_text(t, encoding="utf-8")
print("[OK] inserted V11 firewall after app = Flask(...) statement")
PY

echo "== [2] py_compile =="
python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"

echo "== [3] start service =="
systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== [4] verify POST {} to /api/vsp/run_v1 =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" -d '{}' | sed -n '1,160p'
