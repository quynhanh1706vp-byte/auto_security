#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

TPL_DIR="templates"
ROUTER="static/js/vsp_tabs_hash_router_v1.js"
DASH="static/js/vsp_dashboard_enhance_v1.js"
RUNS="static/js/vsp_runs_tab_resolved_v1.js"

[ -d "$TPL_DIR" ] || { echo "[ERR] missing templates/"; exit 2; }
[ -f "$ROUTER" ] || { echo "[ERR] missing $ROUTER"; exit 3; }
[ -f "$DASH" ] || { echo "[ERR] missing $DASH"; exit 4; }

cp -f "$ROUTER" "$ROUTER.bak_dd_final_${TS}" && echo "[BACKUP] $ROUTER.bak_dd_final_${TS}"
cp -f "$DASH"   "$DASH.bak_dd_final_${TS}"   && echo "[BACKUP] $DASH.bak_dd_final_${TS}"
[ -f "$RUNS" ] && cp -f "$RUNS" "$RUNS.bak_dd_final_${TS}" && echo "[BACKUP] $RUNS.bak_dd_final_${TS}" || true

# backup any template files that contain the leaked marker
grep -RIl "VSP_FIX_DRILLDOWN_CALLSITE_P0_V5" "$TPL_DIR" 2>/dev/null | while read -r f; do
  cp -f "$f" "$f.bak_dd_textleak_${TS}"
  echo "[BACKUP] $f.bak_dd_textleak_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

# (A) Remove leaked text from templates (anything containing the marker line)
tpl_dir = Path("templates")
hit = 0
for p in tpl_dir.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="ignore")
    if "VSP_FIX_DRILLDOWN_CALLSITE_P0_V5" not in s:
        continue
    # remove full lines containing the marker (often the whole injected code is 1 long line)
    lines = s.splitlines(True)
    out = []
    removed = 0
    for ln in lines:
        if "VSP_FIX_DRILLDOWN_CALLSITE_P0_V5" in ln:
            removed += 1
            continue
        out.append(ln)
    p.write_text("".join(out), encoding="utf-8")
    hit += 1
    print(f"[OK] cleaned textleak in {p} removed_lines={removed}")
print(f"[OK] templates cleaned files={hit}")

# (B) Ensure global safe-call exists in router (loaded early)
router = Path("static/js/vsp_tabs_hash_router_v1.js")
rs = router.read_text(encoding="utf-8", errors="ignore")
if "__VSP_DD_SAFE_CALL__" not in rs:
    addon = r"""
/* __VSP_DD_SAFE_CALL__ (P0 final): call handler as function OR {open: fn} */
(function(){
  'use strict';
  if (window.__VSP_DD_SAFE_CALL__) return;
  window.__VSP_DD_SAFE_CALL__ = function(handler){
    try{
      var args = Array.prototype.slice.call(arguments, 1);
      if (typeof handler === 'function') return handler.apply(null, args);
      if (handler && typeof handler.open === 'function') return handler.open.apply(handler, args);
    }catch(e){
      try{ console.warn('[VSP][DD_SAFE_CALL]', e); }catch(_){}
    }
    return null;
  };
})();
"""
    m = re.search(r"(['\"])use strict\1\s*;?", rs)
    if m:
        i = m.end()
        rs = rs[:i] + "\n" + addon + "\n" + rs[i:]
    else:
        rs = addon + "\n" + rs
    router.write_text(rs, encoding="utf-8")
    print("[OK] injected __VSP_DD_SAFE_CALL__ into router")
else:
    print("[OK] __VSP_DD_SAFE_CALL__ already present in router")

# (C) Patch callsites to use safe-call (no more TypeError)
def patch_callsites(path: Path):
    s = path.read_text(encoding="utf-8", errors="ignore")

    # also harden: if handler is object, wrap into callable once
    if "__VSP_DD_HANDLER_WRAP_P0_FINAL" not in s:
        wrap = r"""
/* __VSP_DD_HANDLER_WRAP_P0_FINAL: normalize VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 to callable */
(function(){
  'use strict';
  try{
    var h = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    if (h && typeof h !== 'function'){
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        return (window.__VSP_DD_SAFE_CALL__ || function(x){
          try{
            var a=[].slice.call(arguments,1);
            if (typeof x==='function') return x.apply(null,a);
            if (x && typeof x.open==='function') return x.open.apply(x,a);
          }catch(_){}
          return null;
        }).apply(null, [h].concat([].slice.call(arguments)));
      };
      try{ console.log('[VSP][P0] drilldown handler wrapped (obj->fn)'); }catch(_){}
    }
  }catch(e){}
})();
"""
        # insert near top
        ins = s.find("\n")
        s = s[:ins+1] + wrap + "\n" + s[ins+1:]

    pat = r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
    rep = "window.__VSP_DD_SAFE_CALL__(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, "
    n = len(re.findall(pat, s))
    if n:
        s = re.sub(pat, rep, s)
    path.write_text(s, encoding="utf-8")
    print(f"[OK] patched {path} calls_rewritten={n}")

patch_callsites(Path("static/js/vsp_dashboard_enhance_v1.js"))
runs = Path("static/js/vsp_runs_tab_resolved_v1.js")
if runs.exists():
    patch_callsites(runs)
else:
    print("[OK] runs tab js missing; skip")
PY

# optional syntax check
if command -v node >/dev/null 2>&1; then
  node --check "$ROUTER" >/dev/null && echo "[OK] node --check router OK"
  node --check "$DASH" >/dev/null && echo "[OK] node --check dashboard OK"
  [ -f "$RUNS" ] && node --check "$RUNS" >/dev/null && echo "[OK] node --check runs OK" || true
fi

echo "[OK] patch done"
