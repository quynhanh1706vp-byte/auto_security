#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_crashfix_${TS}" && echo "[BACKUP] $F.bak_crashfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# 0) ensure we can re-run safely
if "VSP_RID_STATE_CRASHFIX_V3" in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

# 1) Inject safe declaration after 'use strict'
inject = r'''
// VSP_RID_STATE_CRASHFIX_V3: safe globals + no $1 + robust pickLatest fallback
var VSP_RID_PICKLATEST_OVERRIDE_V1 = (typeof window !== "undefined" && window.VSP_RID_PICKLATEST_OVERRIDE_V1) ? window.VSP_RID_PICKLATEST_OVERRIDE_V1 : null;

function vspNormRidV3(x){
  if(!x) return "";
  try{
    let s = String(x).trim();
    s = s.replace(/^RID:\s*/i, "");
    s = s.replace(/^RUN_/i, "");
    return s.trim();
  }catch(e){ return ""; }
}
'''
if "'use strict'" in s:
    s = re.sub(r"('use strict'\s*;)", r"\1\n"+inject, s, count=1)
else:
    s = inject + "\n" + s

# 2) Fix any accidental JS usage of bare $1 (ReferenceError)
# Replace bare $1 tokens with "$1" ONLY if present; but we prefer removing group usage entirely.
# Best-effort: if you see ...replace(..., $1) → ...replace(..., "$1")
s = re.sub(r'(\breplace\s*\([^)]*,\s*)\$1(\s*\))', r'\1"$1"\2', s)

# 3) Guard direct reference of VSP_RID_PICKLATEST_OVERRIDE_V1 in conditions
# if (VSP_RID_PICKLATEST_OVERRIDE_V1) → if (typeof VSP_RID_PICKLATEST_OVERRIDE_V1!=="undefined" && VSP_RID_PICKLATEST_OVERRIDE_V1)
s = re.sub(r'\bif\s*\(\s*VSP_RID_PICKLATEST_OVERRIDE_V1\s*\)', 'if (typeof VSP_RID_PICKLATEST_OVERRIDE_V1!=="undefined" && VSP_RID_PICKLATEST_OVERRIDE_V1)', s)

# 4) Append robust fallback pickLatest implementation that won't crash even if older code fails
addon = r'''
(function(){
  'use strict';
  async function pickLatestSafe(){
    try{
      // if override exists, trust it but normalize
      if (typeof VSP_RID_PICKLATEST_OVERRIDE_V1!=="undefined" && VSP_RID_PICKLATEST_OVERRIDE_V1){
        const rid = vspNormRidV3(VSP_RID_PICKLATEST_OVERRIDE_V1);
        if(rid) return rid;
      }
    }catch(e){}

    // Always prefer backend FS fallback endpoint (you already have it)
    try{
      const r = await fetch("/api/vsp/latest_rid_v1", {cache:"no-store"});
      const j = await r.json();
      const rid = vspNormRidV3(j && (j.run_id || j.rid || j.id));
      if(rid) return rid;
    }catch(e){}

    // last resort: localStorage
    try{
      const rid = vspNormRidV3(localStorage.getItem("vsp_rid_selected_v2") || localStorage.getItem("vsp_rid_selected") || "");
      if(rid) return rid;
    }catch(e){}

    return "";
  }

  async function ensureRidSafe(){
    const rid = await pickLatestSafe();
    if(!rid){
      console.warn("[VSP_RID_STATE_V3] no rid resolved");
      return;
    }
    try{ localStorage.setItem("vsp_rid_selected_v2", rid); }catch(e){}
    // update any obvious labels if present
    try{
      const el = document.querySelector("[data-vsp-rid-label]") || document.getElementById("vsp-rid-label");
      if(el) el.textContent = rid;
    }catch(e){}
    console.info("[VSP_RID_STATE_V3] resolved rid=", rid);
  }

  // run after DOM ready
  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", ensureRidSafe);
  else ensureRidSafe();
})();
'''
s = s.rstrip() + "\n\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched rid_state crashfix v3")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_rid_state_crashfix_v3"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
