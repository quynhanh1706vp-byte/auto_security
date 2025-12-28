#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
SVC="vsp-ui-8910.service"
PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$PYF" "${PYF}.bak_alias_${TS}"
echo "[BACKUP] ${PYF}.bak_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_ALIAS_RID_LATEST_GATE_ROOT_GATE_ROOT_V1"
if MARK in s:
    print("[OK] marker exists, skip")
    raise SystemExit(0)

# ensure redirect import
if "redirect" not in s:
    # try to add redirect into existing flask import line
    s2 = re.sub(r'from\s+flask\s+import\s+([^\n]+)',
                lambda m: m.group(0) if "redirect" in m.group(1) else f"from flask import {m.group(1).rstrip()}, redirect",
                s, count=1)
    s = s2

# add route near other /api/vsp routes (append at end safely)
alias = f"""

# ===================== {MARK} =====================
try:
    @app.get("/api/vsp/rid_latest_gate_root_gate_root")
    def vsp_alias_rid_latest_gate_root_gate_root():
        # Fetch() will follow redirect and still get JSON.
        return redirect("/api/vsp/rid_latest_gate_root", code=302)
except Exception:
    pass
# ===================== /{MARK} =====================
"""
s += alias
p.write_text(s, encoding="utf-8")
print("[OK] patched vsp_demo_app.py alias route")
PY

python3 -m py_compile "$PYF"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] alias ready"
