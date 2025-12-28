#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_crashfix_v3b_${TS}" && echo "[BACKUP] $F.bak_crashfix_v3b_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_RID_STATE_CRASHFIX_V3B" in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

inject = """
// VSP_RID_STATE_CRASHFIX_V3B: safe globals + no $1 + robust pickLatest fallback
var VSP_RID_PICKLATEST_OVERRIDE_V1 = (typeof window !== "undefined" && window.VSP_RID_PICKLATEST_OVERRIDE_V1) ? window.VSP_RID_PICKLATEST_OVERRIDE_V1 : null;

function vspNormRidV3b(x){
  if(!x) return "";
  try{
    let t = String(x).trim();
    t = t.replace(/^RID:\\s*/i, "");
    t = t.replace(/^RUN_/i, "");
    return t.trim();
  }catch(e){ return ""; }
}
"""

# 1) inject after first occurrence of 'use strict';
needle = "'use strict';"
idx = s.find(needle)
if idx >= 0:
    insert_at = idx + len(needle)
    s = s[:insert_at] + "\n" + inject + "\n" + s[insert_at:]
else:
    # fallback: inject at top
    s = inject + "\n" + s

# 2) fix accidental bare $1 tokens (very safe best-effort)
# common bug: replace(..., $1) -> replace(..., "$1")
s = s.replace(", $1)", ', "$1")')
s = s.replace(", $1 )", ', "$1" )')
s = s.replace(", $1,", ', "$1",')

# 3) guard direct "if (VSP_RID_PICKLATEST_OVERRIDE_V1)" patterns
s = s.replace("if (VSP_RID_PICKLATEST_OVERRIDE_V1)", 'if (typeof VSP_RID_PICKLATEST_OVERRIDE_V1!=="undefined" && VSP_RID_PICKLATEST_OVERRIDE_V1)')

addon = """
(function(){
  'use strict';
  async function pickLatestSafe(){
    try{
      if (typeof VSP_RID_PICKLATEST_OVERRIDE_V1!=="undefined" && VSP_RID_PICKLATEST_OVERRIDE_V1){
        const rid = vspNormRidV3b(VSP_RID_PICKLATEST_OVERRIDE_V1);
        if(rid) return rid;
      }
    }catch(e){}

    try{
      const r = await fetch("/api/vsp/latest_rid_v1", {cache:"no-store"});
      const j = await r.json();
      const rid = vspNormRidV3b(j && (j.run_id || j.rid || j.id));
      if(rid) return rid;
    }catch(e){}

    try{
      const rid = vspNormRidV3b(localStorage.getItem("vsp_rid_selected_v2") || localStorage.getItem("vsp_rid_selected") || "");
      if(rid) return rid;
    }catch(e){}

    return "";
  }

  async function ensureRidSafe(){
    const rid = await pickLatestSafe();
    if(!rid){
      console.warn("[VSP_RID_STATE_V3B] no rid resolved");
      return;
    }
    try{ localStorage.setItem("vsp_rid_selected_v2", rid); }catch(e){}
    console.info("[VSP_RID_STATE_V3B] resolved rid=", rid);
  }

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", ensureRidSafe);
  else ensureRidSafe();
})();
"""

s = s.rstrip() + "\n\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched rid_state crashfix v3b")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_rid_state_crashfix_v3b"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
