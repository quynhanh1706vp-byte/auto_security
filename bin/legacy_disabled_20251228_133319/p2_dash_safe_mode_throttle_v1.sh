#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node; need grep; need head

TS="$(date +%Y%m%d_%H%M%S)"

files=(
  "static/js/vsp_bundle_tabs5_v1.js"
  "static/js/vsp_tabs4_autorid_v1.js"
  "static/js/vsp_dashboard_luxe_v1.js"
  "static/js/vsp_dashboard_consistency_patch_v1.js"
  "static/js/vsp_rid_switch_refresh_all_v1.js"
  "static/js/vsp_rid_persist_patch_v1.js"
  "static/js/vsp_topbar_commercial_v1.js"
)

echo "== [0] Backup target JS =="
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "[WARN] missing $f (skip)"; continue; }
  cp -f "$f" "${f}.bak_safe_${TS}"
  echo "[BACKUP] ${f}.bak_safe_${TS}"
done

echo "== [1] Inject SAFE helper into bundle (idempotent) =="
B="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

python3 - <<'PY'
from pathlib import Path
import re, os, time

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="/* VSP_SAFE_INTERVAL_V1 */"
if MARK in s:
    print("[OK] helper already present")
else:
    helper = r'''
/* VSP_SAFE_INTERVAL_V1 */
(function(){
  try{
    // default: live OFF, only ON if /vsp5?live=1
    if (typeof window.__VSP_SAFE_LIVE === "undefined") {
      var sp = new URLSearchParams(location.search||"");
      window.__VSP_SAFE_LIVE = (sp.get("live")==="1");
    }
    window.__vspSafeInterval = window.__vspSafeInterval || function(fn, ms){
      var safeMs = Math.max(parseInt(ms||0,10) || 0, 2000);
      return setInterval(function(){
        try{
          if (document.hidden) return;
          if (window.__VSP_SAFE_LIVE === false) return;
          fn && fn();
        }catch(e){
          console.warn("[VSP_SAFE_INTERVAL]", e);
        }
      }, safeMs);
    };
    window.__vspSafeTimeout = window.__vspSafeTimeout || function(fn, ms){
      var safeMs = Math.max(parseInt(ms||0,10) || 0, 200);
      return setTimeout(function(){
        try{
          if (window.__VSP_SAFE_LIVE === false && safeMs < 800) return;
          fn && fn();
        }catch(e){
          console.warn("[VSP_SAFE_TIMEOUT]", e);
        }
      }, safeMs);
    };
  }catch(e){
    console.warn("[VSP_SAFE_INIT]", e);
  }
})();
'''
    p.write_text(s + "\n" + MARK + "\n" + helper + "\n", encoding="utf-8")
    print("[OK] injected helper")
PY

echo "== [2] Replace setInterval -> __vspSafeInterval in loaded JS (idempotent) =="
python3 - <<'PY'
from pathlib import Path
import re

targets = [
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_dashboard_consistency_patch_v1.js",
  "static/js/vsp_rid_switch_refresh_all_v1.js",
  "static/js/vsp_rid_persist_patch_v1.js",
  "static/js/vsp_topbar_commercial_v1.js",
  "static/js/vsp_tabs4_autorid_v1.js",
  "static/js/vsp_bundle_tabs5_v1.js",
]

for f in targets:
    p=Path(f)
    if not p.exists():
        print("[SKIP] missing", f)
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    if "window.__vspSafeInterval" not in s and "VSP_SAFE_INTERVAL_V1" not in s:
        # helper is in bundle, so ok
        pass

    s2=s
    # avoid double replace
    s2=re.sub(r'(?<!__vspSafe)setInterval\s*\(', 'window.__vspSafeInterval(', s2)
    # (optional) throttle aggressive setTimeout loops
    s2=re.sub(r'(?<!__vspSafe)setTimeout\s*\(', 'window.__vspSafeTimeout(', s2)

    if s2 != s:
        p.write_text(s2, encoding="utf-8")
        print("[OK] patched", f)
    else:
        print("[OK] unchanged", f)
PY

echo "== [3] Quick parse check (node) =="
node - <<'NODE'
const fs=require("fs");
const files=[
  "static/js/vsp_bundle_tabs5_v1.js",
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_dashboard_consistency_patch_v1.js",
  "static/js/vsp_rid_switch_refresh_all_v1.js",
  "static/js/vsp_rid_persist_patch_v1.js",
  "static/js/vsp_topbar_commercial_v1.js",
  "static/js/vsp_tabs4_autorid_v1.js",
];
let bad=0;
for(const f of files){
  if(!fs.existsSync(f)) continue;
  const s=fs.readFileSync(f,"utf8");
  try{ new Function(s); }
  catch(e){ bad++; console.error("[BAD]", f, e.message); }
}
if(bad) process.exit(2);
console.log("[OK] all JS parse OK");
NODE

echo "== [4] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo
echo "[DONE] Open /vsp5 (default live OFF) then /vsp5?live=1 if you want live updates."
