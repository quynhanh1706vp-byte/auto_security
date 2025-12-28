#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fixTopCWE_${TS}"
echo "[BACKUP] ${JS}.bak_fixTopCWE_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

before = s
# fix the exact typo: "const topCWE = = Object..."
s = s.replace("const topCWE = = Object.entries", "const topCWE = Object.entries")

# also fix possible spacing variants just in case
s = re.sub(r'const\s+topCWE\s*=\s*=\s*Object\.entries', 'const topCWE = Object.entries', s)

if s == before:
    print("[WARN] no replacement made (maybe already fixed?)")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] fixed: const topCWE double '='")

PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS" || true; exit 2; }

echo "[DONE] Ctrl+Shift+R: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5?rid=VSP_CI_20251218_114312"
grep -n "VSP_P1_DASH_MINICHARTS_PANEL_V4" "$JS" | head -n 2 || true
