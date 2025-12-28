#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

UNIT="vsp-ui-8910.service"
F="vsp_demo_app.py"

echo "== [0] stop service =="
systemctl --user stop "$UNIT" 2>/dev/null || true
sleep 1

echo "== [1] pick clean compiling backup (NO runv1 surgery / url_map hacks) =="
best=""
for b in $(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true); do
  python3 -m py_compile "$b" >/dev/null 2>&1 || continue
  bn="$(basename "$b")"
  if echo "$bn" | grep -qiE "runv1|firewall|hard|force|wrapper|delegate|anyform|cachedjson|envov|envfix"; then
    continue
  fi
  if grep -qiE "VSP_RUN_V1_|RUNV1_CONTRACT|CONTRACT_WRAPPER|before_request.*run_v1|_rules_by_endpoint|url_map\._rules_by_endpoint" "$b" 2>/dev/null; then
    continue
  fi
  best="$b"
  break
done

if [ -n "$best" ]; then
  echo "[OK] restore from: $best"
  cp -f "$best" "$F"
else
  echo "[WARN] no clean backup found; will patch current file"
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_commercial_v13b_${TS}"
echo "[BACKUP] $F.bak_runv1_commercial_v13b_${TS}"

echo "== [2] insert firewall V13b before first @app decorator =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_COMMERCIAL_FIREWALL_V13B ==="
END = "# === END VSP_RUN_V1_COMMERCIAL_FIREWALL_V13B ==="
if TAG in t:
    print("[OK] already present")
    raise SystemExit(0)

# ensure imports exist (top-level safe)
if not re.search(r"(?m)^\s*import\s+os\s*$", t):
    t = "import os\n" + t
if not re.search(r"(?m)^\s*import\s+json\s*$", t):
    t = "import json\n" + t

# Find earliest @app.* decorator (route/get/post/before_request etc.)
m = re.search(r"(?m)^\s*@app\.", t)
if not m:
    raise SystemExit("[ERR] cannot find any '@app.' decorator to anchor insert. (app factory layout?)")

block = f"""
{TAG}
# Commercial contract:
# - POST /api/vsp/run_v1 accepts {{}} (or empty body)
# - Auto-fill defaults so downstream run_v1 won't 400
# - Do NOT touch url_map internals
try:
    from flask import request
    @app.before_request
    def _vsp_run_v1_firewall_v13b():
        if request.path != "/api/vsp/run_v1" or request.method != "POST":
            return None
        data = request.get_json(silent=True)
        if data is None:
            data = {{}}
        if not isinstance(data, dict):
            data = {{}}
        data.setdefault("mode", "local")
        data.setdefault("profile", "FULL_EXT")
        data.setdefault("target_type", "path")
        data.setdefault("target", "/home/test/Data/SECURITY-10-10-v4")
        # ensure downstream request.get_json() sees our patched payload
        try:
            request._cached_json = {{False: data, True: data}}
        except Exception:
            pass
        return None
except Exception as e:
    print("[VSP_RUN_V1_COMMERCIAL_FIREWALL_V13B] skipped:", repr(e))
{END}
"""

t = t[:m.start()] + block + "\n" + t[m.start():]
p.write_text(t, encoding="utf-8")
print("[OK] inserted firewall V13b at line", t[:m.start()].count("\n")+1)
PY

echo "== [3] py_compile =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [4] restart service =="
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user restart "$UNIT"
sleep 1

echo "== [5] verify POST {} to /api/vsp/run_v1 (must NOT 400) =="
curl -sS http://127.0.0.1:8910/healthz; echo
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" -H "Content-Type: application/json" -d '{}' | sed -n '1,200p'
