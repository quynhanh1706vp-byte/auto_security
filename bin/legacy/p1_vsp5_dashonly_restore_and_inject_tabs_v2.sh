#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_DASHONLY_RESTORE_INJECT_TABS_V2"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_before_restore_${TS}"
echo "[BACKUP] ${W}.bak_before_restore_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re, sys

W = Path("wsgi_vsp_ui_gateway.py")
mark = "VSP_P1_VSP5_DASHONLY_RESTORE_INJECT_TABS_V2"

def compiles(path: Path) -> bool:
    try:
        py_compile.compile(str(path), doraise=True)
        return True
    except Exception:
        return False

# 1) If current file does NOT compile => restore best backup
if not compiles(W):
    baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
    good = None
    for b in baks:
        if compiles(b):
            good = b
            break
    if not good:
        print("[ERR] no compiling backup found for restore.")
        sys.exit(3)
    W.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[RESTORE] restored from:", good.name)
else:
    print("[OK] current wsgi compiles; no restore needed")

s = W.read_text(encoding="utf-8", errors="replace")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

# 2) Locate function _vsp5_dash_only_html
m = re.search(r'^(\s*)def\s+_vsp5_dash_only_html\s*\(\s*\)\s*:\s*$', s, flags=re.M)
if not m:
    print("[ERR] cannot find def _vsp5_dash_only_html()")
    sys.exit(4)

def_indent = m.group(1)
body_indent = def_indent + "    "
fn_start = m.end()

# find end of function (next def at same or less indent)
m2 = re.search(r'^\s*def\s+\w+\s*\(', s[fn_start:], flags=re.M)
fn_end = fn_start + (m2.start() if m2 else 4000)
fn = s[fn_start:fn_end]

# 3) Ensure time/asset_v lines exist with correct indentation (ONLY inside function)
if "asset_v = int(time.time())" not in fn:
    inject_lines = (
        f"\n{body_indent}# {mark}\n"
        f"{body_indent}import time\n"
        f"{body_indent}asset_v = int(time.time())  # numeric cache-buster for /vsp5\n"
    )
    # insert right after function header line
    s = s[:fn_start] + inject_lines + s[fn_start:]
    fn_start += len(inject_lines)
    fn_end += len(inject_lines)
    fn = s[fn_start:fn_end]
    print("[OK] inserted asset_v block")

# 4) Inject tabs/topbar script tags into the HTML returned by this function
# We'll inject just before </head> inside the function window.
# Use {asset_v} because this dash-only html builder commonly formats with .format(...) or f-string already.
if "vsp_tabs4_autorid_v1.js" in fn:
    print("[OK] tabs js already present in _vsp5_dash_only_html()")
else:
    ins = (
        f"\n    <!-- {mark} -->\n"
        f"    <script src=\"/static/js/vsp_tabs4_autorid_v1.js?v={{asset_v}}\"></script>\n"
        f"    <script src=\"/static/js/vsp_topbar_commercial_v1.js?v={{asset_v}}\"></script>\n"
    )
    # only patch within fn window
    head_pos = re.search(r'</head>', fn, flags=re.I)
    if not head_pos:
        print("[ERR] cannot find </head> inside _vsp5_dash_only_html() html block")
        sys.exit(5)
    fn2 = fn[:head_pos.start()] + ins + fn[head_pos.start():]
    s = s[:fn_start] + fn2 + s[fn_end:]
    print("[OK] injected tabs/topbar scripts into vsp5 dash-only HTML")

# 5) Final compile check
W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"

echo "[DONE] Restore+inject complete."
