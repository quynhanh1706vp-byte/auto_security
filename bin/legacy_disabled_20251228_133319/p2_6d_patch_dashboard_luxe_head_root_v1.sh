#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v node >/dev/null 2>&1 || { echo "[WARN] node not found -> skip node --check"; }

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p2_6d_${TS}"
echo "[BACKUP] ${JS}.bak_p2_6d_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")
orig = s

MARK = "VSP_P2_6D_LUXE_HEAD_ROOT_FIX_V1"
if MARK not in s:
    s = "/* " + MARK + " */\n" + s

# 1) Convert HEAD to GET in many common forms
# fetch(..., {method:'HEAD'})
s = re.sub(r'(\bmethod\s*:\s*)([\'"])HEAD\2', r'\1"GET"', s)
# new Request(url, {method:'HEAD'})
s = re.sub(r'(\bmethod\s*:\s*)([\'"])HEAD\2', r'\1"GET"', s)
# xhr.open('HEAD', url, ...)
s = re.sub(r'(\.open\s*\(\s*)([\'"])HEAD\2', r'\1"GET"', s)
# any literal "HEAD" used as method var
s = re.sub(r'([\'"])HEAD\1', lambda m: '"GET"' if m.group(0) in ("'HEAD'","\"HEAD\"") else m.group(0), s)

# 2) Root fallback for #vsp-dashboard-main patterns
s = s.replace("document.querySelector('#vsp-dashboard-main')",
              "(document.querySelector('#vsp-dashboard-main') || (window.__VSP_DASH_ROOT?window.__VSP_DASH_ROOT():document.body))")
s = s.replace('document.querySelector("#vsp-dashboard-main")',
              '(document.querySelector("#vsp-dashboard-main") || (window.__VSP_DASH_ROOT?window.__VSP_DASH_ROOT():document.body))')

s = re.sub(r'(\b(?:const|let|var)\s+root\s*=\s*)document\.querySelector\((["\'])#vsp-dashboard-main\2\)',
           r'\1(window.__VSP_DASH_ROOT?window.__VSP_DASH_ROOT():document.body)', s)

# 3) If there is a log complaining about missing #vsp-dashboard-main, soften it (optional)
s = re.sub(r'(không thấy\s*#vsp-dashboard-main)', r'(missing #vsp-dashboard-main; fallback root)', s)

if s == orig:
    print("[WARN] no textual changes detected (already fixed or patterns not found)")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched vsp_dashboard_luxe_v1.js")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS"
  echo "[OK] node --check: $JS"
fi

echo
echo "[NEXT] Ctrl+Shift+R /vsp5 and check console:"
echo "  - HEAD spam should stop"
echo "  - missing #vsp-dashboard-main should not block"
