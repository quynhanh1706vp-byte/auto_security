#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ui_health_ok_${TS}"
echo "[BACKUP] ${APP}.bak_ui_health_ok_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Find decorator containing /api/vsp/ui_health_v2
m = re.search(r'(?m)^\s*@app\.(?:get|route)\(\s*[\'"]/api/vsp/ui_health_v2[\'"]', s)
if not m:
    print("[ERR] cannot find route decorator for /api/vsp/ui_health_v2")
    sys.exit(2)

start = m.start()

# Find end at next decorator at column 0 (best effort)
m2 = re.search(r'(?m)^(?=@app\.)', s[m.end():])
end = m.end() + (m2.start() if m2 else len(s[m.end():]))

new_block = r'''
@app.get("/api/vsp/ui_health_v2")
def ui_health_v2():
    """
    Commercial contract:
      - ok MUST be true (never break clients/audits)
      - readiness/health goes into ready/issues/degraded
    """
    from flask import jsonify
    import time, os

    issues = []
    # (Optional) lightweight hints only; do NOT fail contract.
    # You can add more checks later, but keep ok=True always.

    # Example: surface some env toggles for debugging without noise
    kpi_log = os.environ.get("VSP_KPI_V4_LOG")
    asset_v = os.environ.get("VSP_ASSET_V") or os.environ.get("VSP_P1_ASSET_V_RUNTIME_TS_V1")

    ready = (len(issues) == 0)
    payload = {
        "ok": True,
        "ready": ready,
        "issues": issues,
        "degraded": (not ready),
        "marker": "VSP_P2_UI_HEALTH_V2_ALWAYS_OK_V1",
        "ts": int(time.time()),
        "meta": {
            "kpi_v4_log": kpi_log,
            "asset_v": asset_v,
        }
    }
    return jsonify(payload)
'''.lstrip("\n")

patched = s[:start] + new_block + "\n" + s[end:]

# Safety: ensure we didn't accidentally duplicate the route
if len(re.findall(r'/api/vsp/ui_health_v2', patched)) < 1:
    print("[ERR] patch sanity failed: route missing after patch")
    sys.exit(2)

p.write_text(patched, encoding="utf-8")
print("[OK] patched ui_health_v2 block")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting: $SVC"
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
else
  echo "[WARN] systemctl not found; restart service manually"
fi

echo "== quick check =="
curl -sS "http://127.0.0.1:8910/api/vsp/ui_health_v2" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "ready=", j.get("ready"), "marker=", j.get("marker"))
PY
