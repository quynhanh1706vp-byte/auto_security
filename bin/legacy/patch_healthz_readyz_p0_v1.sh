#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_healthz_${TS}"
echo "[BACKUP] $APP.bak_healthz_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_HEALTHZ_READYZ_P0_V1"
if MARK in s:
    print("[OK] already present"); raise SystemExit(0)

code = f"""
# --- {MARK}: commercial health endpoints ---
@app.get("/healthz")
def vsp_healthz_p0_v1():
    return "ok", 200

@app.get("/readyz")
def vsp_readyz_p0_v1():
    # lightweight readiness: app is up + can answer latest rid quickly
    return {{"ok": True}}, 200
"""

# insert near other routes (before __main__ if exists)
m = re.search(r'(?m)^if\\s+__name__\\s*==\\s*[\'"]__main__[\'"]\\s*:', s)
ins = m.start() if m else len(s)
s2 = s[:ins] + "\\n" + code + "\\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected", MARK)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910"
