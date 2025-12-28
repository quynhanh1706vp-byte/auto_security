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
  # skip by filename (ultra safe)
  if echo "$bn" | grep -qiE "runv1|firewall|hard|force|wrapper|delegate|anyform|cachedjson|envov|envfix"; then
    continue
  fi

  # skip by content (ignore-case)
  if grep -qiE \
    "VSP_RUN_V1_HARD_OVERRIDE|VSP_RUN_V1_FORCE_ALIAS|CONTRACT_WRAPPER|RUNV1_CONTRACT|before_request.*run_v1|_rules_by_endpoint|url_map\._rules_by_endpoint|VSP_RUN_V1_FIREWALL|VSP_RUN_V1_WRAPSAFE" \
    "$b" 2>/dev/null; then
    continue
  fi

  best="$b"
  break
done

if [ -n "$best" ]; then
  echo "[OK] restore from: $best"
  cp -f "$best" "$F"
else
  echo "[WARN] no clean backup found. We'll try to heal current file by removing known blocks."
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_commercial_v13_${TS}"
echo "[BACKUP] $F.bak_runv1_commercial_v13_${TS}"

echo "== [2] apply commercial firewall V13 (insert right after app = Flask(...)) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# remove old run_v1 surgery blocks (best-effort, so we don't keep broken hacks)
t = re.sub(r"(?ms)\n?\s*# === VSP_RUN_V1_.*?===.*?# === END VSP_RUN_V1_.*?===\s*\n?", "\n", t)
t = re.sub(r"(?ms)\n?\s*# === VSP_RUNV1_.*?===.*?# === END VSP_RUNV1_.*?===\s*\n?", "\n", t)

TAG = "# === VSP_RUN_V1_COMMERCIAL_FIREWALL_V13 ==="
END = "# === END VSP_RUN_V1_COMMERCIAL_FIREWALL_V13 ==="
if TAG in t:
    print("[OK] firewall V13 already present")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

# ensure imports exist (top-level safe)
if not re.search(r"(?m)^\s*import\s+os\s*$", t):
    t = "import os\n" + t
if not re.search(r"(?m)^\s*import\s+json\s*$", t):
    t = "import json\n" + t

# find app = Flask( ... ) line
m = re.search(r"(?m)^(?P<ind>\s*)app\s*=\s*Flask\([^\n]*\)\s*$", t)
if not m:
    raise SystemExit("[ERR] cannot find line: app = Flask(...)")

ind = m.group("ind")
insert_at = m.end()

block = f"""
{TAG}
# Commercial contract:
# - POST /api/vsp/run_v1 accepts {{}} (or empty body)
# - Auto-fill defaults so downstream run_v1 won't 400
# - Do NOT touch url_map internals (no _rules_by_endpoint hacks)
try:
{ind}    from flask import request
{ind}    @app.before_request
{ind}    def _vsp_run_v1_firewall_v13():
{ind}        if request.path != "/api/vsp/run_v1" or request.method != "POST":
{ind}            return None
{ind}        data = request.get_json(silent=True)
{ind}        if data is None:
{ind}            data = {{}}
{ind}        if not isinstance(data, dict):
{ind}            data = {{}}
{ind}        data.setdefault("mode", "local")
{ind}        data.setdefault("profile", "FULL_EXT")
{ind}        data.setdefault("target_type", "path")
{ind}        data.setdefault("target", "/home/test/Data/SECURITY-10-10-v4")
{ind}        # Fix Flask cached json to make downstream request.get_json() see patched payload
{ind}        try:
{ind}            request._cached_json = {{False: data, True: data}}
{ind}        except Exception:
{ind}            pass
{ind}        return None
except Exception as e:
{ind}    print("[VSP_RUN_V1_COMMERCIAL_FIREWALL_V13] skipped:", repr(e))
{END}
"""

t = t[:insert_at] + "\n" + block + "\n" + t[insert_at:]
p.write_text(t, encoding="utf-8")
print("[OK] inserted firewall V13")
PY

echo "== [3] py_compile =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [4] restart service =="
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user restart "$UNIT"
sleep 1

echo "== [5] verify run_v1 with empty payload (must NOT 400; should be ok:true) =="
curl -sS http://127.0.0.1:8910/healthz; echo
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" -H "Content-Type: application/json" -d '{}' | sed -n '1,180p'
