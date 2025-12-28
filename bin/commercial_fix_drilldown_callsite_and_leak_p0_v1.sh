#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

TPL="templates/vsp_dashboard_2025.html"
DASH="static/js/vsp_dashboard_enhance_v1.js"
RUNS="static/js/vsp_runs_tab_resolved_v1.js"

[ -f "$TPL" ] || echo "[WARN] missing $TPL (skip leak clean)"
[ -f "$DASH" ] || { echo "[ERR] missing $DASH"; exit 2; }

# backups
[ -f "$TPL" ] && cp -f "$TPL" "$TPL.bak_ddleak_${TS}" && echo "[BACKUP] $TPL.bak_ddleak_${TS}" || true
cp -f "$DASH" "$DASH.bak_ddcall_${TS}" && echo "[BACKUP] $DASH.bak_ddcall_${TS}"
[ -f "$RUNS" ] && cp -f "$RUNS" "$RUNS.bak_ddcall_${TS}" && echo "[BACKUP] $RUNS.bak_ddcall_${TS}" || true

python3 - <<'PY'
from pathlib import Path
import re

# (1) CLEAN template text leak lines
tpl = Path("templates/vsp_dashboard_2025.html")
if tpl.exists():
    s = tpl.read_text(encoding="utf-8", errors="ignore").splitlines(True)
    bad_markers = [
        "__VSP_DD_ART_CALL__", "__VSP_DD_SAFE", "DD_SAFE",
        "VSP_FIX_DRILLDOWN_CALLSITE", "try{if (typeof h", "return null;}"
    ]
    out=[]; rm=0
    for ln in s:
        if any(m in ln for m in bad_markers):
            rm += 1
            continue
        out.append(ln)
    tpl.write_text("".join(out), encoding="utf-8")
    print(f"[OK] template leak cleaned removed_lines={rm}")

# (2) Inject a stable callable wrapper into JS and rewrite callsites
def patch_js(path: Path):
    if not path.exists():
        return
    txt = path.read_text(encoding="utf-8", errors="ignore")
    marker = "VSP_DD_ART_CALL_V1"
    if marker not in txt:
        helper = r"""
/* VSP_DD_ART_CALL_V1: commercial stable wrapper (fn OR {open:fn}) */
(function(){
  'use strict';
  if (window.VSP_DD_ART_CALL_V1) return;
  window.VSP_DD_ART_CALL_V1 = function(){
    var h = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    var args = Array.prototype.slice.call(arguments);
    try{
      if (typeof h === 'function') return h.apply(null, args);
      if (h && typeof h.open === 'function') return h.open.apply(h, args);
    }catch(e){
      try{ console.warn('[VSP][DD_CALL_V1]', e); }catch(_){}
    }
    return null;
  };
})();
"""
        # insert after first 'use strict' if possible, else prepend
        m = re.search(r"(['\"])use strict\1\s*;?", txt)
        if m:
            i = m.end()
            txt = txt[:i] + "\n" + helper + "\n" + txt[i:]
        else:
            txt = helper + "\n" + txt
        print(f"[OK] injected helper into {path}")

    # Rewrite direct calls to wrapper (this is the real fix)
    pat = r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
    n = len(re.findall(pat, txt))
    if n:
        txt = re.sub(pat, "window.VSP_DD_ART_CALL_V1(", txt)
    path.write_text(txt, encoding="utf-8")
    print(f"[OK] patched callsites in {path} calls_rewritten={n}")

patch_js(Path("static/js/vsp_dashboard_enhance_v1.js"))
patch_js(Path("static/js/vsp_runs_tab_resolved_v1.js"))
PY

# sanity checks
node --check "$DASH" >/dev/null && echo "[OK] node --check dashboard OK"
[ -f "$RUNS" ] && node --check "$RUNS" >/dev/null && echo "[OK] node --check runs OK" || true

echo "[OK] commercial drilldown callsite + leak fix done"
