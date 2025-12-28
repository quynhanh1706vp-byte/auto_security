#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_export_row_${TS}" && echo "[BACKUP] $F.bak_export_row_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_RUNS_PERROW_EXPORT_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

# 1) Inject helper functions (open export + set rid + update label + event)
helper = r'''
/* VSP_RUNS_PERROW_EXPORT_V1: per-row export + rid live update */
(function(){
  'use strict';

  function __vspExportUrl(rid, fmt){
    const base = (window.VSP_RUN_EXPORT_BASE || "/api/vsp/run_export_v3");
    return `${base}/${encodeURIComponent(rid)}?fmt=${encodeURIComponent(fmt)}`;
  }

  function __vspOpenExport(rid, fmt){
    if(!rid) return;
    const url = __vspExportUrl(rid, fmt);
    window.open(url, "_blank", "noopener");
  }

  function __vspSetRidLive(rid){
    if(!rid) return;

    // prefer shared rid-state if present
    try{
      if(window.VSP_RID && typeof window.VSP_RID.set === "function"){
        window.VSP_RID.set(rid);
      } else {
        // fallback: set multiple keys (avoid breaking older code)
        try{ localStorage.setItem("vsp_selected_rid", rid); }catch(e){}
        try{ localStorage.setItem("vsp_selected_rid_v2", rid); }catch(e){}
        try{ localStorage.setItem("vsp_current_rid", rid); }catch(e){}
        try{ localStorage.setItem("VSP_RID", rid); }catch(e){}
        try{ localStorage.setItem("vsp_rid", rid); }catch(e){}
        try{
          window.dispatchEvent(new CustomEvent("vsp:rid_changed", { detail:{ rid } }));
        }catch(e){}
      }
    }catch(e){
      console.warn("[VSP_SET_RID_LIVE] err", e);
    }

    // update common labels if exist
    const ids = ["vsp-current-rid","vsp-rid-label","vsp-runs-current-rid"];
    ids.forEach(id=>{
      const el = document.getElementById(id);
      if(el) el.textContent = rid;
    });

    // update any export buttons bound by data attr
    document.querySelectorAll("[data-vsp-export-rid]").forEach(btn=>{
      btn.setAttribute("data-vsp-export-rid", rid);
    });
  }

  // global delegation for per-row export buttons (works even if table re-rendered)
  document.addEventListener("click", function(ev){
    const a = ev.target && ev.target.closest && ev.target.closest("[data-vsp-export-fmt][data-vsp-export-rid]");
    if(!a) return;
    ev.preventDefault();
    const rid = a.getAttribute("data-vsp-export-rid");
    const fmt = a.getAttribute("data-vsp-export-fmt");
    __vspOpenExport(rid, fmt);
  }, true);

  // expose for internal use
  window.__vspOpenExport = __vspOpenExport;
  window.__vspSetRidLive = __vspSetRidLive;
})();
'''

s = helper + "\n" + s

# 2) Add per-row export buttons near "Use RID" button HTML
# Replace the exact tail 'Use RID</button>'; with a small actions group.
s = s.replace(
  '">Use RID</button>\';',
  '">Use RID</button>\' +\n' +
  '           \' <a href="#" data-vsp-export-rid="\'+rid+\'" data-vsp-export-fmt="html" ' +
  'style="margin-left:8px; padding:7px 10px; border-radius:10px; font-size:12px; ' +
  'border:1px solid rgba(148,163,184,.25); color:#cbd5e1; text-decoration:none;">HTML</a>\' +\n' +
  '           \' <a href="#" data-vsp-export-rid="\'+rid+\'" data-vsp-export-fmt="zip" ' +
  'style="margin-left:6px; padding:7px 10px; border-radius:10px; font-size:12px; ' +
  'border:1px solid rgba(148,163,184,.25); color:#cbd5e1; text-decoration:none;">ZIP</a>\' +\n' +
  '           \' <a href="#" data-vsp-export-rid="\'+rid+\'" data-vsp-export-fmt="pdf" ' +
  'style="margin-left:6px; padding:7px 10px; border-radius:10px; font-size:12px; ' +
  'border:1px solid rgba(148,163,184,.25); color:#cbd5e1; text-decoration:none;">PDF</a>\';'
)

# 3) Strengthen Use RID handler: call __vspSetRidLive(rid)
# Find handler marker and inject call after it extracts rid
if "VSP_USE_RID_HANDLER_V1" in s and "__vspSetRidLive" not in s:
  # locate the first occurrence of "const rid =" inside handler and insert after
  s = re.sub(r"(const\s+rid\s*=\s*[^;]+;)",
             r"\1\n      try{ if(window.__vspSetRidLive) window.__vspSetRidLive(rid); }catch(e){}",
             s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null && echo "[OK] node --check OK"

echo "[DONE] patch_runs_export_per_row_and_rid_live_v1"
echo "Next: hard refresh browser (Ctrl+Shift+R). No backend restart needed for JS-only change."
