#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_truefix_${TS}"
echo "[BACKUP] ${F}.bak_truefix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP5_RUNS_TRUEFIX_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# (A) Fix Python literals leaking into JS
# Safe enough for our case: these tokens should not appear inside strings in this file.
s2 = re.sub(r'\bTrue\b', 'true', s)
s2 = re.sub(r'\bFalse\b', 'false', s2)
s2 = re.sub(r'\bNone\b', 'null', s2)

# (B) If code probes existence with HEAD and backend doesn't like it, downgrade to GET
s2 = re.sub(r"(method\s*:\s*['\"])HEAD(['\"])", r"\1GET\2", s2)

# Marker
s2 += "\n\n/* "+MARK+" */\n"
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 3; }
echo "[NEXT] restart UI + Ctrl+F5 /vsp5"
