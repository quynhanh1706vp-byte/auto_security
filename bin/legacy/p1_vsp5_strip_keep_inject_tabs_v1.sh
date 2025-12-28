#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_STRIP_KEEP_INJECT_TABS_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_vsp5_strip_inject_${TS}"
echo "[BACKUP] ${W}.bak_vsp5_strip_inject_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_VSP5_STRIP_KEEP_INJECT_TABS_V1"

if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

# Find the exact block "if path == "/vsp5" ... html2 = re.sub(...)" and inject right after html2 computed.
pat = r'(html2\s*=\s*_re\.sub\(r"\\(<script\[\^>\]\*>\\\)\\(\\.\\*\\?\\)\\(<\\/script>\\\)"\s*,\s*_kill_script\s*,\s*html\s*,\s*flags=_re\.S\|_re\.I\)\s*\n)'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find vsp5 strip re.sub block to patch")

inject = (
    f"{m.group(1)}"
    f"                    # {mark}: ensure tabs/topbar scripts remain after strip\n"
    f"                    try:\n"
    f"                        av = int(__import__('time').time())\n"
    f"                        if 'vsp_tabs4_autorid_v1.js' not in html2:\n"
    f"                            html2 = html2.replace('</head>',\n"
    f"                                f'\\n<script src=\"/static/js/vsp_tabs4_autorid_v1.js?v={{av}}\"></script>\\n'</head>', 1)\n"
    f"                        if 'vsp_topbar_commercial_v1.js' not in html2:\n"
    f"                            html2 = html2.replace('</head>',\n"
    f"                                f'\\n<script src=\"/static/js/vsp_topbar_commercial_v1.js?v={{av}}\"></script>\\n'</head>', 1)\n"
    f"                    except Exception:\n"
    f"                        pass\n"
)

# Replace only once
s2 = s[:m.start(1)] + inject + s[m.end(1):]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] /vsp5 strip now re-injects tabs/topbar scripts if missing."
