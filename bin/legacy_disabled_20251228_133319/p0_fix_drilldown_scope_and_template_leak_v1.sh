#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

DASH="static/js/vsp_dashboard_enhance_v1.js"
RUNS="static/js/vsp_runs_tab_resolved_v1.js"
LOADER="static/js/vsp_ui_loader_route_v1.js"

[ -f "$DASH" ] || { echo "[ERR] missing $DASH"; exit 2; }
cp -f "$DASH" "$DASH.bak_scopefix_${TS}" && echo "[BACKUP] $DASH.bak_scopefix_${TS}"
[ -f "$RUNS" ] && cp -f "$RUNS" "$RUNS.bak_scopefix_${TS}" && echo "[BACKUP] $RUNS.bak_scopefix_${TS}" || true
[ -f "$LOADER" ] && cp -f "$LOADER" "$LOADER.bak_scopefix_${TS}" && echo "[BACKUP] $LOADER.bak_scopefix_${TS}" || true

echo "== (1) clean template text leak =="
python3 - <<'PY'
from pathlib import Path
import re

markers = [
  "try{if (typeof h", "DD_SAFE", "__VSP_DD_", "VSP_FIX_DRILLDOWN_CALLSITE",
  "return h(", "return h.open", "console.warn('[VSP][DD_SAFE]"
]

for p in Path("templates").rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)
    out=[]; rm=0
    for ln in s:
        if any(m in ln for m in markers):
            rm += 1
            continue
        out.append(ln)
    if rm:
        p.write_text("".join(out), encoding="utf-8")
        print("[OK] cleaned", p, "removed_lines", rm)
PY

echo "== (2) force drilldown callsites to use window.<fn> (kills local var shadowing) =="
python3 - <<'PY'
from pathlib import Path
import re

def patch(path: Path):
    if not path.exists(): return
    txt = path.read_text(encoding="utf-8", errors="ignore")

    # Replace bare identifier calls with window. calls (avoid matching obj.prop or already window.)
    pat = r"(?<![\w\.])VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
    n = len(re.findall(pat, txt))
    if n:
        txt = re.sub(pat, "window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(", txt)
    path.write_text(txt, encoding="utf-8")
    print(f"[OK] patched {path} bare_calls_fixed={n}")

patch(Path("static/js/vsp_dashboard_enhance_v1.js"))
patch(Path("static/js/vsp_runs_tab_resolved_v1.js"))
PY

node --check "$DASH" >/dev/null && echo "[OK] node --check dashboard OK"
[ -f "$RUNS" ] && node --check "$RUNS" >/dev/null && echo "[OK] node --check runs OK" || true

echo "[OK] P0 scope+leak fix done"
