#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_drill_art_${TS}" && echo "[BACKUP] $F.bak_drill_art_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2"
if MARK in s:
    print("[SKIP] already patched v2")
    raise SystemExit(0)

# We patch by appending a small override layer that:
# - wraps render() to re-order artifacts and add "Quick Open" buttons.
block = r'''
/* VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2: pin important artifacts + quick-open buttons */
(function(){
  'use strict';
  if(!window.VSP_DASH_DRILLDOWN || typeof window.VSP_DASH_DRILLDOWN.render !== "function"){
    console.warn("[DRILL_ART_V2] VSP_DASH_DRILLDOWN missing; skip");
    return;
  }

  const PIN = [
    "kics/kics.log",
    "codeql/codeql.log",
    "trivy/trivy.json.err",
    "findings_effective.json",
    "findings_unified.json",
  ];

  function _pinSort(items){
    const byName = new Map((items||[]).map(x=>[x.name, x]));
    const out = [];
    for(const name of PIN){
      if(byName.has(name)) out.push(byName.get(name));
      else out.push({name, url:null, size:null, missing:true});
    }
    // append rest (non-duplicates)
    for(const it of (items||[])){
      if(!PIN.includes(it.name)) out.push(it);
    }
    return out;
  }

  function _qBtn(name, url){
    const disabled = !url;
    return `<a class="vsp-dd-btn" style="text-decoration:none;display:inline-flex;align-items:center;gap:6px;${disabled?'opacity:.55;pointer-events:none;':''}"
      href="${url?String(url).replace(/"/g,'&quot;'):'#'}" target="_blank" rel="noopener">
      Open <b style="color:#e2e8f0">${name}</b>
    </a>`;
  }

  // Monkey patch: wrap the existing render to decorate artifacts area after it renders
  const _origRender = window.VSP_DASH_DRILLDOWN.render;
  window.VSP_DASH_DRILLDOWN.render = async function(){
    await _origRender();

    try{
      const body = document.getElementById("vsp-dd-body");
      if(!body) return;

      // Fetch artifacts again to pin + show quick actions (cheap)
      const title = document.getElementById("vsp-dd-title");
      const rid = (title && title.textContent && title.textContent.includes("•")) ? title.textContent.split("•").pop().trim() : null;
      if(!rid) return;

      const r = await fetch(`/api/vsp/run_artifacts_index_v1/${encodeURIComponent(rid)}`, {headers:{'Accept':'application/json'}});
      const j = await r.json();
      const items = _pinSort((j && j.items) ? j.items : []);

      const quick = items.slice(0,5).map(it=>{
        const nm = it.name.split("/").pop();
        return _qBtn(nm, it.url);
      }).join("");

      // Inject a top "Quick open" strip
      let q = document.getElementById("vsp-dd-quickopen");
      if(!q){
        q = document.createElement("div");
        q.id = "vsp-dd-quickopen";
        q.className="vsp-dd-card";
        q.innerHTML = `<div style="font-weight:800;color:#e2e8f0;margin-bottom:8px;">Quick open</div>
          <div style="display:flex;gap:8px;flex-wrap:wrap;">${quick}</div>`;
        body.prepend(q);
      } else {
        q.querySelector("div[style*='display:flex']")?.innerHTML = quick;
      }

      // Replace the artifacts section in Overview card (best-effort)
      const cards = body.querySelectorAll(".vsp-dd-card");
      let overview = null;
      for(const c of cards){
        if((c.textContent||"").includes("Overview")){ overview = c; break; }
      }
      if(overview){
        const links = items.slice(0,10).map(it=>{
          const nm = it.name;
          if(it.url) return `<a class="vsp-dd-link" href="${it.url}" target="_blank" rel="noopener">${nm}</a>`;
          return `<span class="vsp-dd-muted">${nm} (missing)</span>`;
        }).join(" ");
        // find "Artifacts:" label
        const html = overview.innerHTML;
        const rep = `<div class="vsp-dd-muted">Artifacts:</div><div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:6px;">${links || '<span class="vsp-dd-muted">empty</span>'}</div>`;
        overview.innerHTML = html.replace(/<div class="vsp-dd-muted">Artifacts:[\s\S]*?<\/div>\s*<\/div>\s*<\/div>/m, rep + "</div></div>")
                                .replace(/<div class="vsp-dd-muted">Artifacts:[\s\S]*?<\/div>/m, rep);
      }
    }catch(e){
      console.warn("[DRILL_ART_V2] err", e);
    }
  };

  console.log("[DRILL_ART_V2] installed");
})();
'''

p.write_text(s.rstrip()+"\n\n"+MARK+"\n"+block+"\n", encoding="utf-8")
print("[OK] appended artifacts drilldown v2")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_dashboard_drilldown_artifacts_p1_v2"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
