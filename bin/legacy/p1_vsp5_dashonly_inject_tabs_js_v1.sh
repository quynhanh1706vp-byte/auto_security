#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 && SYS_OK=1 || SYS_OK=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_DASHONLY_INJECT_TABS_JS_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_vsp5tabs_${TS}"
echo "[BACKUP] ${W}.bak_vsp5tabs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_VSP5_DASHONLY_INJECT_TABS_JS_V1"

if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

# We will inject into the first occurrence of a vsp5 "dash-only html" builder.
# Look for a function that returns a big HTML string containing '<div id="vsp5_root"></div>' and '</head>'.
# Then insert script tags before </head>.

needle_root = r'<div id="vsp5_root"></div>'
if "vsp_tabs4_autorid_v1.js" in s and "/vsp5" in s:
    pass

def inject_into_html_block(text: str) -> tuple[str,int]:
    # Find a likely vsp5 html generator region
    # We'll search a window around 'vsp5_root' and inject before </head> inside the same triple-quoted HTML.
    idx = text.find(needle_root)
    if idx < 0:
        return text, 0

    # Search backward a bit to find start of HTML string and forward for </head>
    start = max(0, idx - 8000)
    end = min(len(text), idx + 8000)
    chunk = text[start:end]

    if "vsp_tabs4_autorid_v1.js" in chunk:
        return text, 0

    # Prefer to insert before </head> inside chunk
    m = re.search(r'</head>', chunk, flags=re.I)
    if not m:
        return text, 0

    ins = (
        f"\n    <!-- {mark} -->\n"
        f"    <script src=\"/static/js/vsp_tabs4_autorid_v1.js?v={{asset_v}}\"></script>\n"
        f"    <script src=\"/static/js/vsp_topbar_commercial_v1.js?v={{asset_v}}\"></script>\n"
    )

    chunk2 = chunk[:m.start()] + ins + chunk[m.start():]
    new_text = text[:start] + chunk2 + text[end:]
    return new_text, 1

# In WSGI gateway, asset_v is usually a Python variable in scope when building HTML.
# Many existing blocks already format strings with {asset_v}. If not present, this still compiles and will show literally,
# but we expect asset_v exists in the dash-only html block (your build already uses asset versioning elsewhere).
s2, n = inject_into_html_block(s)
if n == 0:
    print("[WARN] could not find vsp5_root-based HTML block to inject. Will try fallback by function name patterns.")

    # Fallback: inject near function definitions commonly used
    for fn in ("def _vsp5_dash_only_html", "def _html_vsp5"):
        pos = s.find(fn)
        if pos < 0:
            continue
        win = s[pos:pos+12000]
        if "vsp_tabs4_autorid_v1.js" in win:
            print("[OK] tabs already present near", fn)
            raise SystemExit(0)
        m = re.search(r'</head>', win, flags=re.I)
        if not m:
            continue
        ins = (
            f"\n    <!-- {mark} -->\n"
            f"    <script src=\"/static/js/vsp_tabs4_autorid_v1.js?v={{asset_v}}\"></script>\n"
            f"    <script src=\"/static/js/vsp_topbar_commercial_v1.js?v={{asset_v}}\"></script>\n"
        )
        win2 = win[:m.start()] + ins + win[m.start():]
        s2 = s[:pos] + win2 + s[pos+12000:]
        n = 1
        break

if n == 0:
    raise SystemExit("[ERR] injection failed: could not locate /vsp5 dash-only html block")

p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

if [ "$SYS_OK" = "1" ]; then
  systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
fi

echo "[DONE] /vsp5 dash-only HTML now includes tabs+topbar JS."
