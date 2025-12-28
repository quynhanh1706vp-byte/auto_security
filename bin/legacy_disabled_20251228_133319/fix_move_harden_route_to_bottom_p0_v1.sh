#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_move_harden_${TS}"
echo "[BACKUP] $F.bak_move_harden_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Find the harden endpoint block by its decorator URL, grab decorator + def + indented body
pat = r'(?ms)^@app\.get\(\s*["\']/api/vsp/dashboard_commercial_v2_harden["\']\s*\)\s*\n^def\s+[a-zA-Z_]\w*\s*\(\s*\)\s*:\s*\n(?:^[ \t].*\n)*'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find harden route decorator for /api/vsp/dashboard_commercial_v2_harden")

block = m.group(0).rstrip() + "\n\n"
s2 = s[:m.start()] + s[m.end():]

# Ensure we don't leave duplicate later (remove any other duplicate occurrences)
s2 = re.sub(pat, "", s2)

# Append to end (safe: app should be defined by then if module can load)
s2 = s2.rstrip() + "\n\n# --- moved to bottom: dashboard_commercial_v2_harden ---\n" + block

p.write_text(s2, encoding="utf-8")
print("[OK] moved /api/vsp/dashboard_commercial_v2_harden route to bottom")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] restart 8910 then verify:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
echo "  curl -sS http://127.0.0.1:8910/api/vsp/dashboard_commercial_v2_harden | jq . -C"
