#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_runslimit50_${TS}"
echo "[BACKUP] ${JS}.bak_runslimit50_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_UI_RUNS_LIMIT_50_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

# Replace plain "/api/vsp/runs" with "/api/vsp/runs?limit=50" if not already has query
s2 = re.sub(r'(["\'])\/api\/vsp\/runs\1', r'\1/api/vsp/runs?limit=50\1', s)
# If already has limit=..., force it to 50
s2 = re.sub(r'(\/api\/vsp\/runs\?[^"\']*?)\blimit=\d+', r'\1limit=50', s2)

p.write_text(s2 + f"\n// {MARK}\n", encoding="utf-8")
print("[OK] patched runs fetch URL -> limit=50")
PY

node --check static/js/vsp_runs_tab_resolved_v1.js
echo "[OK] node --check OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
