#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="static/css/security_resilient.css"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_nodebug_${TS}"
echo "[BACKUP] ${F}.bak_nodebug_${TS}"

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

# Replace the debug banner content string with empty OR comment it out safely
s = s.replace('content: "SB DEBUG THEME ACTIVE";', 'content: ""; /* debug banner disabled */')

p.write_text(s, encoding="utf-8")
print("[OK] patched, changed=", s!=orig)
PY

echo "== verify line (should be empty content) =="
grep -n 'SB DEBUG THEME ACTIVE' -n "$F" || echo "[OK] no DEBUG banner string"
