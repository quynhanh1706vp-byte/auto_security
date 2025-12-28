#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_STRIP_INJECT_TABS_V1C_ROBUST"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_vsp5_strip_robust_${TS}"
echo "[BACKUP] ${W}.bak_vsp5_strip_robust_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_VSP5_STRIP_INJECT_TABS_V1C_ROBUST"

if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

# Find the vsp5 strip block
block_hdr = "# B) Strip injected inline dash scripts on /vsp5 HTML (outermost)"
i0 = s.find(block_hdr)
if i0 < 0:
    raise SystemExit("[ERR] cannot find vsp5 strip block header")

# Replace the previous injected block (V1B) if present, then insert robust block once.
# We'll insert right after the line: html2 = _re.sub(... _kill_script ...)
anchor = 'html2 = _re.sub(r"(<script[^>]*>)(.*?)(</script>)", _kill_script, html, flags=_re.S|_re.I)'
i1 = s.find(anchor, i0)
if i1 < 0:
    i1 = s.find("html2 = _re.sub(", i0)
    if i1 < 0:
        raise SystemExit("[ERR] cannot find html2 = _re.sub in vsp5 strip block")

line_end = s.find("\n", i1)
if line_end < 0:
    line_end = len(s)

# Determine indent of anchor line
line_start = s.rfind("\n", 0, i1) + 1
indent = ""
while line_start + len(indent) < len(s) and s[line_start + len(indent)] in (" ", "\t"):
    indent += s[line_start + len(indent)]

inject = (
    "\n"
    f"{indent}# {mark}: ensure tabs/topbar scripts exist after strip (case-insensitive, fallback append)\n"
    f"{indent}try:\n"
    f"{indent}    import time as _time\n"
    f"{indent}    av = int(_time.time())\n"
    f"{indent}    ins = (f'\\n<script src=\"/static/js/vsp_tabs4_autorid_v1.js?v={av}\"></script>'\n"
    f"{indent}           f'\\n<script src=\"/static/js/vsp_topbar_commercial_v1.js?v={av}\"></script>\\n')\n"
    f"{indent}    low = html2.lower()\n"
    f"{indent}    if ('vsp_tabs4_autorid_v1.js' not in low) or ('vsp_topbar_commercial_v1.js' not in low):\n"
    f"{indent}        if '</head>' in low:\n"
    f"{indent}            # inject before closing head, regardless of case\n"
    f"{indent}            html2 = _re.sub(r'</head>', ins + '</head>', html2, count=1, flags=_re.I)\n"
    f"{indent}        else:\n"
    f"{indent}            # no head tag: append to end\n"
    f"{indent}            html2 = html2 + ins\n"
    f"{indent}except Exception:\n"
    f"{indent}    pass\n"
)

s2 = s[:line_end] + inject + s[line_end:]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] /vsp5 strip robust inject applied."
