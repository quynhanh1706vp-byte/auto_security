#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_MINIMAL_HTML_INJECT_TABS_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_vsp5_min_inj_${TS}"
echo "[BACKUP] ${W}.bak_vsp5_min_inj_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_VSP5_MINIMAL_HTML_INJECT_TABS_V1"
if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

# Locate a chunk that clearly matches the minimal /vsp5 HTML (title + css)
# We patch the first matching HTML literal.
title_idx = s.find("<title>VSP5</title>")
if title_idx < 0:
    raise SystemExit("[ERR] cannot find <title>VSP5</title> in wsgi")

win_start = max(0, title_idx - 4000)
win_end   = min(len(s), title_idx + 12000)
win = s[win_start:win_end]

if "vsp_tabs4_autorid_v1.js" in win and "vsp_topbar_commercial_v1.js" in win:
    print("[OK] minimal vsp5 html already contains tabs/topbar scripts")
    raise SystemExit(0)

# Ensure this window is indeed dash-only minimal shell
if "vsp_dash_only_v1.css" not in win:
    print("[WARN] title found but css not in same window; still attempting injection near </body>")

# Inject before </body> (case-insensitive). If missing </body>, inject before </html>, else append.
ins = (
    f"\n    <!-- {mark} -->\n"
    f"    <script src=\"/static/js/vsp_tabs4_autorid_v1.js?v={{asset_v}}\"></script>\n"
    f"    <script src=\"/static/js/vsp_topbar_commercial_v1.js?v={{asset_v}}\"></script>\n"
)

# Try replace </body>
m = re.search(r"</body>", win, flags=re.I)
if m:
    win2 = win[:m.start()] + ins + win[m.start():]
else:
    m2 = re.search(r"</html>", win, flags=re.I)
    if m2:
        win2 = win[:m2.start()] + ins + win[m2.start():]
    else:
        win2 = win + ins

# Add marker comment for audit + avoid re-patching
win2 = f"<!-- {mark} -->\n" + win2

s2 = s[:win_start] + win2 + s[win_end:]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] injected tabs/topbar into minimal /vsp5 HTML."
