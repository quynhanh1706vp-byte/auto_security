#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_RESTORE_STRIP_INJECT_TABS_SAFE_V2"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_before_rescue_${TS}"
echo "[BACKUP] ${W}.bak_before_rescue_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re, sys

W = Path("wsgi_vsp_ui_gateway.py")
mark = "VSP_P1_VSP5_RESTORE_STRIP_INJECT_TABS_SAFE_V2"

def compiles(path: Path) -> bool:
    try:
        py_compile.compile(str(path), doraise=True)
        return True
    except Exception:
        return False

# 1) Restore if broken
if not compiles(W):
    baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    good = None
    for b in baks:
        if compiles(b):
            good = b
            break
    if not good:
        print("[ERR] no compiling backup found to restore.")
        sys.exit(3)
    W.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[RESTORE] restored from:", good.name)
else:
    print("[OK] current file compiles; no restore needed")

s = W.read_text(encoding="utf-8", errors="replace")
if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

# 2) Patch in the /vsp5 strip block
hdr = "# B) Strip injected inline dash scripts on /vsp5 HTML (outermost)"
i0 = s.find(hdr)
if i0 < 0:
    print("[ERR] cannot find vsp5 strip block header")
    sys.exit(4)

anchor = 'html2 = _re.sub(r"(<script[^>]*>)(.*?)(</script>)", _kill_script, html, flags=_re.S|_re.I)'
i1 = s.find(anchor, i0)
if i1 < 0:
    i1 = s.find("html2 = _re.sub(", i0)
    if i1 < 0:
        print("[ERR] cannot find html2 = _re.sub in vsp5 strip block")
        sys.exit(5)

# determine indent of the anchor line
line_start = s.rfind("\n", 0, i1) + 1
indent = ""
while line_start + len(indent) < len(s) and s[line_start + len(indent)] in (" ", "\t"):
    indent += s[line_start + len(indent)]

line_end = s.find("\n", i1)
if line_end < 0:
    line_end = len(s)

inject_lines = [
    f"{indent}# {mark}: ensure tabs/topbar scripts exist after strip (robust inject)",
    f"{indent}try:",
    f"{indent}    import time as _time",
    f"{indent}    av = int(_time.time())",
    f"{indent}    ins = ('\\n<script src=\"/static/js/vsp_tabs4_autorid_v1.js?v=%d\"></script>' % av) + "
    f"('\\n<script src=\"/static/js/vsp_topbar_commercial_v1.js?v=%d\"></script>\\n' % av)",
    f"{indent}    low = html2.lower()",
    f"{indent}    if ('vsp_tabs4_autorid_v1.js' not in low) or ('vsp_topbar_commercial_v1.js' not in low):",
    f"{indent}        # prefer inject before </body>, else </head>, else append",
    f"{indent}        if '</body>' in low:",
    f"{indent}            html2 = _re.sub(r'</body>', ins + '</body>', html2, count=1, flags=_re.I)",
    f"{indent}        elif '</head>' in low:",
    f"{indent}            html2 = _re.sub(r'</head>', ins + '</head>', html2, count=1, flags=_re.I)",
    f"{indent}        else:",
    f"{indent}            html2 = html2 + ins",
    f"{indent}except Exception:",
    f"{indent}    pass",
]

inject = "\n" + "\n".join(inject_lines) + "\n"

s2 = s[:line_end] + inject + s[line_end:]

W.write_text(s2, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY
systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] rescue+strip-inject applied."
