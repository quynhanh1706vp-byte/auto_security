#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

pick_loader() {
  # 1) common patterns
  local f
  f="$(find static/js -maxdepth 1 -type f \( \
      -name 'vsp_ui_loader_route*.js' -o \
      -name 'vsp_ui_loader*.js' -o \
      -name '*loader*route*.js' \
    \) | head -n1 || true)"
  if [ -n "${f:-}" ]; then echo "$f"; return 0; fi

  # 2) extract from template (first referenced loader-ish js)
  f="$(grep -RhoE '/static/js/[^"]*(loader|route)[^"]*\.js' templates 2>/dev/null \
      | head -n1 | sed 's#^/##' || true)"
  if [ -n "${f:-}" ] && [ -f "$f" ]; then echo "$f"; return 0; fi

  # 3) fallback: global shims/router (usually loaded early)
  for f in static/js/vsp_ui_global_shims_commercial_p0_v1.js \
           static/js/vsp_tabs_hash_router_v1.js \
           static/js/vsp_rid_state_v1.js; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done

  return 1
}

LOADER="$(pick_loader || true)"
if [ -z "${LOADER:-}" ]; then
  echo "[ERR] cannot locate a loader JS to inject safe-call"
  echo "      Try: ls -la static/js | head -n 80"
  exit 2
fi
echo "[OK] picked LOADER=$LOADER"

# targets to patch callsites (only if exist)
TARGETS=()
[ -f static/js/vsp_dashboard_enhance_v1.js ] && TARGETS+=(static/js/vsp_dashboard_enhance_v1.js)
[ -f static/js/vsp_runs_tab_resolved_v1.js ] && TARGETS+=(static/js/vsp_runs_tab_resolved_v1.js)

# backups
cp -f "$LOADER" "$LOADER.bak_dd_safe_${TS}" && echo "[BACKUP] $LOADER.bak_dd_safe_${TS}"
for f in "${TARGETS[@]}"; do
  cp -f "$f" "$f.bak_dd_safe_${TS}" && echo "[BACKUP] $f.bak_dd_safe_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re, os

loader = Path(os.environ["LOADER"])
s = loader.read_text(encoding="utf-8", errors="ignore")

if "__VSP_DD_SAFE_CALL__" not in s:
    addon = r"""
/* __VSP_DD_SAFE_CALL__ (P0): call handler as fn OR {open: fn} */
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
    m = re.search(r"(['\"])use strict\1\s*;?", s)
    if m:
        i = m.end()
        s = s[:i] + "\n" + addon + "\n" + s[i:]
    else:
        s = addon + "\n" + s
    loader.write_text(s, encoding="utf-8")
    print("[OK] injected safe-call into", loader)
else:
    print("[OK] safe-call already present in", loader)

def patch_callsites(p: Path):
    if not p.exists(): return
    txt = p.read_text(encoding="utf-8", errors="ignore")
    pat = r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
    rep = "window.__VSP_DD_SAFE_CALL__(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2, "
    n = len(re.findall(pat, txt))
    if n:
        txt = re.sub(pat, rep, txt)
        p.write_text(txt, encoding="utf-8")
    print(f"[OK] patched {p} calls={n}")

patch_callsites(Path("static/js/vsp_dashboard_enhance_v1.js"))
patch_callsites(Path("static/js/vsp_runs_tab_resolved_v1.js"))
PY
echo "[OK] patched"

# syntax check if node exists
command -v node >/dev/null 2>&1 && node --check "$LOADER" >/dev/null && echo "[OK] node --check loader OK" || true
for f in "${TARGETS[@]}"; do
  command -v node >/dev/null 2>&1 && node --check "$f" >/dev/null && echo "[OK] node --check $f OK" || true
done

echo "[OK] done"
