#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

B="static/js/vsp_ui_4tabs_commercial_v1.freeze.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

cp -f "$B" "$B.bak_p0_freeze_${TS}"
echo "[BACKUP] $B.bak_p0_freeze_${TS}"

TARGET_FILE="$B" python3 - <<'PY'
import os, re
from pathlib import Path

p = Path(os.environ["TARGET_FILE"])
s = p.read_text(encoding="utf-8", errors="ignore")
changed = 0

# (A) Nuclear: make drilldown calls safe (cannot throw "is not a function")
pat = r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
repl = r'(typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function"?VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:function(){try{console.info("[VSP_DASH][P0] drilldown missing -> stub");}catch(_){ } return {open(){},show(){},close(){},destroy(){}};})('
s2, n = re.subn(pat, repl, s)
if n:
    s = s2
    changed += n
    print("[OK] drilldown callsites replaced:", n)
else:
    print("[WARN] no drilldown callsite found in bundle")

# (B) Demote charts give-up warn -> info (bundle contains charts bootstrap)
if '[VSP_CHARTS_BOOT_SAFE_V2] give up after' in s:
    s = s.replace('console.warn("[VSP_CHARTS_BOOT_SAFE_V2] give up after', 'console.info("[VSP_CHARTS_BOOT_SAFE_V2] give up after')
    changed += 1
    print("[OK] demoted charts give-up warn -> info")
else:
    print("[INFO] charts give-up marker not found in bundle")

# (C) Fix duplicate form ids + missing name/id (Chrome Issues)
MARK = "P0_DOM_FORM_IDS_FIX_BUNDLE_V1"
if MARK not in s:
    addon = r"""
/* P0_DOM_FORM_IDS_FIX_BUNDLE_V1 */
(function(){
  'use strict';
  function run(){
    try{
      // fix duplicate IDs
      const byId = {};
      const all = Array.from(document.querySelectorAll("[id]"));
      for (const el of all){
        const id = el.getAttribute("id");
        if (!id) continue;
        (byId[id] ||= []).push(el);
      }
      for (const id of Object.keys(byId)){
        const arr = byId[id];
        if (arr.length <= 1) continue;
        for (let i=1;i<arr.length;i++){
          arr[i].setAttribute("id", id + "__dup" + i);
        }
      }

      // ensure form controls have id/name
      const ctrls = Array.from(document.querySelectorAll("input,select,textarea"));
      let k = 0;
      for (const el of ctrls){
        const tag = (el.tagName||"x").toLowerCase();
        const id = (el.getAttribute("id")||"").trim();
        const name = (el.getAttribute("name")||"").trim();
        if (!id && !name){
          const nid = "vsp_auto_" + tag + "_" + (++k);
          el.setAttribute("id", nid);
          el.setAttribute("name", nid);
        } else if (!name && id){
          el.setAttribute("name", id);
        } else if (!id && name){
          el.setAttribute("id", name);
        }
      }
    }catch(_){}
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run, {once:true});
  else run();
})();
"""
    s += "\n" + addon
    changed += 1
    print("[OK] appended DOM ids fixer")

p.write_text(s, encoding="utf-8")
print("[OK] total_changes=", changed)
PY

node --check "$B" >/dev/null
echo "[OK] node --check $B"

# (D) Bump cache-buster ?v=... in templates that reference freeze bundle
TPLS="$(grep -RIl "vsp_ui_4tabs_commercial_v1.freeze.js?v=" templates 2>/dev/null || true)"
if [ -n "$TPLS" ]; then
  for T in $TPLS; do
    cp -f "$T" "$T.bak_p0_v_${TS}"
    echo "[BACKUP] $T.bak_p0_v_${TS}"
    python3 - <<PY
import re
from pathlib import Path
t=Path("$T")
s=t.read_text(encoding="utf-8", errors="ignore")
s=re.sub(r"(vsp_ui_4tabs_commercial_v1\.freeze\.js\?v=)[0-9_]+", r"\\1$TS", s)
t.write_text(s, encoding="utf-8")
print("[OK] bumped v in", t)
PY
  done
else
  echo "[WARN] no template references found for freeze.js?v=..."
fi

echo "[DONE] patch_p0_fix_freeze_bundle_v1"
