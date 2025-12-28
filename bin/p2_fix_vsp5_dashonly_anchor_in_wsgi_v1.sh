#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_vsp5_anchor_${TS}"
echo "[BACKUP] ${F}.bak_vsp5_anchor_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")
orig = s

# We know current dash-only HTML has: <div id="vsp5_root"></div>
needle = '<div id="vsp5_root"></div>'
if needle not in s:
    print("[ERR] cannot find vsp5_root marker in wsgi file (dash-only shell may differ)")
    sys.exit(2)

# If already injected, do nothing
if 'id="vsp-dashboard-main"' in s and 'vsp5_root' in s:
    print("[OK] anchor appears already present in source; skip")
    sys.exit(0)

replacement = (
    '  <div id="vsp-dashboard-main"></div>\n\n'
    '  <div id="vsp5_root"></div>'
)

# Replace only the first occurrence (dash-only shell should have one)
s2 = s.replace(needle, replacement, 1)

if s2 == s:
    print("[ERR] replace made no changes")
    sys.exit(2)

p.write_text(s2)
print("[OK] patched: injected #vsp-dashboard-main into /vsp5 dash-only shell")
PY

echo "== restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
fi

echo "== verify live html =="
curl -sS "$BASE/vsp5" | grep -n 'id="vsp-dashboard-main"' | head -n 3 || { echo "[ERR] anchor still missing on live /vsp5"; exit 2; }

echo "[DONE] Now hard refresh browser: Ctrl+Shift+R"
