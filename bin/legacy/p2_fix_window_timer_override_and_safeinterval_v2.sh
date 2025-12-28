#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node; need grep; need head; need curl

F1="static/js/vsp_tabs4_autorid_v1.js"
F2="static/js/vsp_bundle_tabs5_v1.js"

[ -f "$F1" ] || { echo "[ERR] missing $F1"; exit 2; }
[ -f "$F2" ] || { echo "[ERR] missing $F2"; exit 2; }

echo "== [0] Backup =="
cp -f "$F1" "${F1}.bak_fix_timer_${TS}"
cp -f "$F2" "${F2}.bak_fix_timer_${TS}"
echo "[BACKUP] ${F1}.bak_fix_timer_${TS}"
echo "[BACKUP] ${F2}.bak_fix_timer_${TS}"

echo "== [1] Patch tabs4_autorid: snapshot native timers + REMOVE any setInterval/setTimeout override blocks =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_tabs4_autorid_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# (A) Insert native timer snapshot early (idempotent)
marker = "VSP_NATIVE_TIMER_SNAPSHOT_V1"
if marker not in s:
    inject = r"""/* VSP_NATIVE_TIMER_SNAPSHOT_V1 */
(function(){
  try{
    if(!window.__vspNativeSetInterval) window.__vspNativeSetInterval = window.setInterval.bind(window);
    if(!window.__vspNativeClearInterval) window.__vspNativeClearInterval = window.clearInterval.bind(window);
    if(!window.__vspNativeSetTimeout) window.__vspNativeSetTimeout = window.setTimeout.bind(window);
    if(!window.__vspNativeClearTimeout) window.__vspNativeClearTimeout = window.clearTimeout.bind(window);
  }catch(e){}
})();
"""
    # place after "use strict" if present, else at top
    m = re.search(r'(?m)^\s*[\'"]use strict[\'"]\s*;\s*', s)
    if m:
        pos = m.end()
        s = s[:pos] + "\n" + inject + "\n" + s[pos:]
    else:
        s = inject + "\n" + s

# (B) Remove any overrides like: window.setInterval = function(...) { ... }
# These caused _window errors and global breakage.
def strip_assign(text, name):
    # remove "window.<name> = function(...) { ... }" blocks (non-greedy, across lines)
    pat = re.compile(rf'(?s)\bwindow\.{re.escape(name)}\s*=\s*function\s*\([^)]*\)\s*\{{.*?\}}\s*;?', re.M)
    return pat.sub(f'/* VSP_STRIPPED_{name.upper()}_OVERRIDE_V2 */', text)

s2 = s
s2 = strip_assign(s2, "setInterval")
s2 = strip_assign(s2, "setTimeout")

# Also strip patterns that reference _window in timer wrappers (safe)
s2 = re.sub(r'(?m)^\s*var\s+_window\s*=.*$', '/* VSP_STRIPPED__WINDOW_ALIAS_V2 */', s2)

p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY

echo "== [2] Patch bundle: define SAFE_INTERVAL V2 (no recursion, uses native snapshot) =="
python3 - <<'PY'
from pathlib import Path
import time

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Append V2 override at end (idempotent)
tag = "VSP_SAFE_INTERVAL_V2"
if tag not in s:
    block = r"""
/* VSP_SAFE_INTERVAL_V2 */
(function(){
  try{
    var nativeSI = (window.__vspNativeSetInterval) ? window.__vspNativeSetInterval : window.setInterval.bind(window);
    // commercial-safe clamp: >=800ms, <=30000ms
    window.__vspSafeInterval = function(fn, ms){
      var v = Number(ms);
      if(!isFinite(v)) v = 0;
      if(v < 800) v = 800;
      if(v > 30000) v = 30000;
      return nativeSI(fn, v);
    };
  }catch(e){}
})();
"""
    s = s.rstrip() + "\n" + block + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended", tag, "to", p)
else:
    print("[OK] already has", tag)
PY

echo "== [3] Parse check (node) =="
node - <<'NODE'
const fs=require("fs");
const files=[
  "static/js/vsp_tabs4_autorid_v1.js",
  "static/js/vsp_bundle_tabs5_v1.js",
];
let bad=0;
for(const f of files){
  try{ new Function(fs.readFileSync(f,"utf8")); }
  catch(e){ bad++; console.error("[BAD]", f, e.message); }
}
process.exit(bad?2:0);
NODE
echo "[OK] parse ok"

echo "== [4] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [5] Quick verify markers =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS --max-time 3 "$BASE/static/js/vsp_tabs4_autorid_v1.js" | grep -n "VSP_NATIVE_TIMER_SNAPSHOT_V1" | head || true
curl -fsS --max-time 3 "$BASE/static/js/vsp_bundle_tabs5_v1.js" | grep -n "VSP_SAFE_INTERVAL_V2" | head || true
echo "[DONE] Ctrl+Shift+R on /vsp5 and check Console: must NOT have '_window is not defined'."
