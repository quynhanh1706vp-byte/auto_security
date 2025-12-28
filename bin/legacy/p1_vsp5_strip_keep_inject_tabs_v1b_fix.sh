#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_STRIP_KEEP_INJECT_TABS_V1B_FIX"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_vsp5_strip_inject_${TS}"
echo "[BACKUP] ${W}.bak_vsp5_strip_inject_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_VSP5_STRIP_KEEP_INJECT_TABS_V1B_FIX"

if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

anchor_block = "# B) Strip injected inline dash scripts on /vsp5 HTML (outermost)"
i0 = s.find(anchor_block)
if i0 < 0:
    raise SystemExit("[ERR] cannot find vsp5 strip block header")

# find the specific html2 = _re.sub(...) line within this block
anchor_line = 'html2 = _re.sub(r"(<script[^>]*>)(.*?)(</script>)", _kill_script, html, flags=_re.S|_re.I)'
i1 = s.find(anchor_line, i0)
if i1 < 0:
    # fallback: find first "html2 = _re.sub(" after block header
    i1 = s.find("html2 = _re.sub(", i0)
    if i1 < 0:
        raise SystemExit("[ERR] cannot find html2 = _re.sub(...) inside vsp5 strip block")

# compute indentation of that line
line_start = s.rfind("\n", 0, i1) + 1
indent = ""
while line_start + len(indent) < len(s) and s[line_start + len(indent)] in (" ", "\t"):
    indent += s[line_start + len(indent)]

# insert after end of the line
line_end = s.find("\n", i1)
if line_end < 0:
    line_end = len(s)

inject = (
    "\n"
    f"{indent}# {mark}: re-inject tabs/topbar scripts if missing after strip\n"
    f"{indent}try:\n"
    f"{indent}    import time as _time\n"
    f"{indent}    av = int(_time.time())\n"
    f"{indent}    if 'vsp_tabs4_autorid_v1.js' not in html2 and '</head>' in html2:\n"
    f"{indent}        html2 = html2.replace('</head>', '\\n<script src=\"/static/js/vsp_tabs4_autorid_v1.js?v=%d\"></script>\\n</head>' % av, 1)\n"
    f"{indent}    if 'vsp_topbar_commercial_v1.js' not in html2 and '</head>' in html2:\n"
    f"{indent}        html2 = html2.replace('</head>', '\\n<script src=\"/static/js/vsp_topbar_commercial_v1.js?v=%d\"></script>\\n</head>' % av, 1)\n"
    f"{indent}except Exception:\n"
    f"{indent}    pass\n"
)

s2 = s[:line_end] + inject + s[line_end:]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] /vsp5 strip now re-injects tabs/topbar scripts if missing."
