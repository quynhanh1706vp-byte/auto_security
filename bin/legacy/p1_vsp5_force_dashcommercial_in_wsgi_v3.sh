#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

WSGI="wsgi_vsp_ui_gateway.py"
GATE="static/js/vsp_dashboard_gate_story_v1.js"
DASH="static/js/vsp_dashboard_commercial_v1.js"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
[ -f "$GATE" ] || { echo "[ERR] missing $GATE"; exit 2; }
[ -f "$DASH" ] || { echo "[ERR] missing $DASH (you already created it earlier)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_vsp5_inject_dash_${TS}"
cp -f "$GATE" "${GATE}.bak_vsp5_disable_${TS}"
echo "[BACKUP] ${WSGI}.bak_vsp5_inject_dash_${TS}"
echo "[BACKUP] ${GATE}.bak_vsp5_disable_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

wsgi = Path("wsgi_vsp_ui_gateway.py")
s = wsgi.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_VSP5_INJECT_DASHCOMMERCIAL_V3"
if marker in s or "vsp_dashboard_commercial_v1.js" in s:
    print("[OK] WSGI already contains dashcommercial or marker; skip inject")
else:
    # find all gate_story script tags in WSGI strings
    pat = re.compile(r'(<script\s+src="/static/js/vsp_dashboard_gate_story_v1\.js\?v=([0-9]+)"\s*></script>)')
    matches = list(pat.finditer(s))
    if not matches:
        raise SystemExit("[ERR] cannot find gate_story script tag in WSGI (pattern mismatch)")

    # choose best match likely belonging to /vsp5 by proximity window containing 'vsp5' or '/vsp5'
    pick = None
    for m in matches:
        lo = max(0, m.start()-2500)
        hi = min(len(s), m.end()+2500)
        win = s[lo:hi].lower()
        if "/vsp5" in win or "vsp5" in win:
            pick = m
            break
    if pick is None:
        pick = matches[0]
        print("[WARN] no nearby '/vsp5' found; injecting after first occurrence")

    tag, ver = pick.group(1), pick.group(2)
    inject = (
        tag
        + f'\n<script defer src="/static/js/vsp_dashboard_commercial_v1.js?v={ver}"></script>\n'
        + f'<!-- {marker} -->'
    )

    s2 = s[:pick.start()] + inject + s[pick.end():]
    wsgi.write_text(s2, encoding="utf-8")
    print(f"[OK] injected dashcommercial into WSGI (ver={ver}) at pos={pick.start()}")

# Now patch GateStory JS: disable on /vsp5 immediately (so it won’t render at all)
gate = Path("static/js/vsp_dashboard_gate_story_v1.js")
gs = gate.read_text(encoding="utf-8", errors="replace")

gmarker = "VSP_P1_DISABLE_GATE_STORY_ON_VSP5_V3"
if gmarker in gs:
    print("[OK] GateStory already disabled on /vsp5; skip")
else:
    guard = f'''
/* {gmarker} */
try{{
  const p = (location && location.pathname) ? location.pathname : "";
  if (p === "/vsp5"){{
    console.log("[GateStoryV1] disabled on /vsp5 (DashCommercialV1 owns dashboard).");
    return;
  }}
}}catch(e){{}}
'''
    # inject inside first IIFE
    m = re.search(r'\(\s*\(\s*\)\s*=>\s*\{', gs)
    if m:
        idx = m.end()
        gs2 = gs[:idx] + "\n" + guard + "\n" + gs[idx:]
        gate.write_text(gs2, encoding="utf-8")
        print("[OK] injected disable-guard into GateStory (arrow IIFE)")
    else:
        m = re.search(r'\(\s*function\s*\(\s*\)\s*\{', gs, flags=re.I)
        if not m:
            raise SystemExit("[ERR] cannot find IIFE opener in GateStory JS")
        idx = m.end()
        gs2 = gs[:idx] + "\n" + guard + "\n" + gs[idx:]
        gate.write_text(gs2, encoding="utf-8")
        print("[OK] injected disable-guard into GateStory (function IIFE)")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo
echo "[DONE] V3 applied."
echo "Next: restart UI then HARD refresh /vsp5."
echo "Verify:"
echo '  curl -fsS http://127.0.0.1:8910/vsp5 | grep -nE "vsp_dashboard_(gate_story|commercial)_v1\.js" || true'
