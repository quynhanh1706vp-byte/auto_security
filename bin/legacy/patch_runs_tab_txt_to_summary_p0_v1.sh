#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_txt2sum_${TS}"
echo "[BACKUP] ${F}.bak_txt2sum_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP5_TXT_BTN_MAP_TO_SUMMARY_P0_V1"
if MARK in s:
    print("[SKIP] already:", MARK); raise SystemExit(0)

# Replace the Open TXT link target (reports/SUMMARY.txt) to run_gate_summary.json
s2 = s.replace("reports/SUMMARY.txt", "reports/run_gate_summary.json")

# add marker at top
s2 = f"/* {MARK} */\n" + s2
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

command -v node >/dev/null 2>&1 && node --check "$F" && echo "[OK] node --check OK" || true
sudo systemctl restart vsp-ui-8910.service || true
