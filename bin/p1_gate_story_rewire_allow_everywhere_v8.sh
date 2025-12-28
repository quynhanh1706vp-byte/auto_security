#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_rewire_allow_v8_${TS}"
echo "[BACKUP] ${JS}.bak_rewire_allow_v8_${TS}"

python3 - "$JS" <<'PY'
import sys, re
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_GATE_STORY_REWIRE_ALLOW_EVERYWHERE_V8"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

repls = {}

def sub(pat, rep, flags=0):
    global s
    s2, n = re.subn(pat, rep, s, flags=flags)
    if n:
        repls[pat] = n
    s = s2

# 1) legacy path -> new
sub(r'reports/run_gate\.json', 'run_gate.json')
sub(r'reports/run_gate_summary\.json', 'run_gate_summary.json')

# 2) endpoint -> allow endpoint (only the run_file path, not /api/vsp/runs)
sub(r'(/api/vsp/)run_file\b', r'\1run_file_allow')

# 3) param name
sub(r'([?&])run_id=', r'\1rid=')

# 4) Sometimes code builds url pieces with "run_file" without /api prefix
#    Avoid over-replacing; only common patterns:
sub(r'["\']run_file["\']', '"run_file_allow"')

s += "\n/* %s */\nconsole.log('[GateStoryV1] V8 rewire allow everywhere applied');\n" % marker
p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
print("[OK] replacements:", repls)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 2; }
echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R). Expect: no more 'reports/run_gate.json' reason; Overall/tool badges update."
