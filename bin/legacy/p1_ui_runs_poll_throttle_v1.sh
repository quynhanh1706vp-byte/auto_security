#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_pollthrottle_${TS}"
echo "[BACKUP] ${JS}.bak_pollthrottle_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_UI_RUNS_POLL_THROTTLE_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

# Add global inflight guard once
if "window.__VSP_RUNS_INFLIGHT" not in s:
    s = f"// {MARK}\nwindow.__VSP_RUNS_INFLIGHT=false;\nwindow.__VSP_RUNS_LAST_FETCH=0;\n" + s

# Throttle any fetch to /api/vsp/runs?limit=50 (or /api/vsp/runs) by wrapping expression
def wrap_fetch(m):
    inner = m.group(0)  # fetch(...)
    return (
        "(window.__VSP_RUNS_INFLIGHT ? Promise.resolve(null) : "
        "(window.__VSP_RUNS_INFLIGHT=true, "
        f"{inner}.finally(()=>{{window.__VSP_RUNS_INFLIGHT=false;}})"
        "))"
    )

# Wrap fetch(...) where inside contains /api/vsp/runs
s = re.sub(r'fetch\([^)]*\/api\/vsp\/runs[^)]*\)', wrap_fetch, s)

# Make setInterval slower if it uses < 15000ms
def bump_interval(m):
    ms = int(m.group(1))
    if ms < 15000:
        return m.group(0).replace(m.group(1), "15000")
    return m.group(0)

s = re.sub(r'setInterval\(\s*[^,]+,\s*(\d+)\s*\)', bump_interval, s)

p.write_text(s + f"\n// {MARK}\n", encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check static/js/vsp_runs_tab_resolved_v1.js
echo "[OK] node --check OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
