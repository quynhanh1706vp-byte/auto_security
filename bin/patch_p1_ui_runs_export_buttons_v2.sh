#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_exportui_v2_${TS}"
echo "[BACKUP] ${F}.bak_exportui_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# remove v1 block if present (keep file clean)
s = re.sub(r"/\*\s*VSP_P1_EXPORT_BUTTONS_UI_V1\s*\*/.*?\}\)\(\);\s*", "", s, flags=re.S)

MARK="VSP_P1_EXPORT_BUTTONS_UI_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
/* VSP_P1_EXPORT_BUTTONS_UI_V2 */
(function(){
  function toast(msg, ok){
    try{
      let box=document.getElementById("vsp_toast_box");
      if(!box){
        box=document.createElement("div");
        box.id="vsp_toast_box";
        box.style.position="fixed";
        box.style.right="16px";
        box.style.bottom="16px";
        box.style.zIndex="99999";
        box.style.maxWidth="560px";
        document.body.appendChild(box);
      }
      const item=document.createElement("div");
      item.textContent=msg;
      item.style.marginTop="8px";
      item.style.padding="10px 12px";
      item.style.borderRadius="10px";
      item.style.fontSize="13px";
      item.style.boxShadow="0 8px 28px rgba(0,0,0,.35)";
      item.style.border="1px solid rgba(255,255,255,.10)";
      item.style.background= ok ? "rgba(40,160,90,.18)" : "rgba(190,60,60,.18)";
      item.style.color="#e9eef6";
      item.style.backdropFilter="blur(6px)";
      box.appendChild(item);
      setTimeout(()=>{ try{ item.remove(); }catch(e){} }, 3800);
    }catch(e){}
  }

  function extractRid(txt){
    txt=(txt||"").toString();
    const m = txt.match(/[A-Za-z0-9][A-Za-z0-9:_-]*_RUN_[A-Za-z0-9:_-]+/);
    if(m) return m[0];
    const m2 = txt.match(/RUN_[A-Za-z0-9:_-]+/);
    return m2 ? m2[0] : null;
  }

  function mkBtn(label, href){
    const a=document.createElement("a");
    a.href=href; a.textContent=label;
    a.target="_blank"; a.rel="noopener";
    a.style.display="inline-block";
    a.style.padding="3px 8px";
    a.style.marginLeft="6px";
    a.style.borderRadius="10px";
    a.style.fontSize="12px";
    a.style.border="1px solid rgba(255,255,255,.12)";
    a.style.textDecoration="none";
    a.style.color="#dfe7f3";
    a.style.background="rgba(255,255,255,.06)";
    a.addEventListener("click", ()=>toast("Export: "+label, true));
    return a;
  }

  async function doSha(rid){
    const url="/api/vsp/sha256?rid="+encodeURIComponent(rid)+"&name="+encodeURIComponent("reports/run_gate_summary.json");
    try{
      const r=await fetch(url, {cache:"no-store"});
      const j=await r.json();
      if(!j || !j.ok) throw new Error("sha failed");
      toast("SHA256 run_gate_summary.json: " + j.sha256, true);
      try{ await navigator.clipboard.writeText(j.sha256); }catch(e){}
    }catch(e){
      toast("SHA verify failed for "+rid, false);
    }
  }

  function buildWrap(rid){
    const wrap=document.createElement("span");
    wrap.setAttribute("data-vsp-exp","1");
    wrap.style.whiteSpace="nowrap";
    wrap.style.marginLeft="8px";
    wrap.appendChild(mkBtn("TGZ", "/api/vsp/export_tgz?rid="+encodeURIComponent(rid)+"&scope=reports"));
    wrap.appendChild(mkBtn("CSV", "/api/vsp/export_csv?rid="+encodeURIComponent(rid)));
    const sha=document.createElement("a");
    sha.href="#"; sha.textContent="SHA";
    sha.style.display="inline-block";
    sha.style.padding="3px 8px";
    sha.style.marginLeft="6px";
    sha.style.borderRadius="10px";
    sha.style.fontSize="12px";
    sha.style.border="1px solid rgba(255,255,255,.12)";
    sha.style.textDecoration="none";
    sha.style.color="#dfe7f3";
    sha.style.background="rgba(255,255,255,.06)";
    sha.addEventListener("click",(ev)=>{ ev.preventDefault(); doSha(rid); });
    wrap.appendChild(sha);
    return wrap;
  }

  function attachToRow(tr){
    if(!tr || tr.querySelector('[data-vsp-exp="1"]')) return;
    const rid = extractRid(tr.innerText || tr.textContent || "");
    if(!rid) return;
    const tds = tr.querySelectorAll ? tr.querySelectorAll("td") : null;
    const cell = (tds && tds.length) ? tds[tds.length-1] : tr;
    cell.appendChild(buildWrap(rid));
  }

  function attachToCard(el){
    if(!el || el.querySelector && el.querySelector('[data-vsp-exp="1"]')) return;
    const rid = extractRid(el.innerText || el.textContent || "");
    if(!rid) return;
    // stick to the end of the block
    const wrap = buildWrap(rid);
    wrap.style.display="inline-block";
    wrap.style.marginTop="6px";
    el.appendChild(wrap);
  }

  function scan(){
    // table rows
    document.querySelectorAll("tr").forEach(attachToRow);

    // card-like: any element that likely represents a run item (heuristic)
    document.querySelectorAll("div, li").forEach(el=>{
      // avoid scanning huge containers
      if(el.children && el.children.length > 40) return;
      const txt = (el.innerText || el.textContent || "");
      if(!txt) return;
      if(txt.includes("RUN_") || txt.includes("_RUN_")){
        attachToCard(el);
      }
    });
  }

  const obs=new MutationObserver(()=>scan());
  obs.observe(document.documentElement, {subtree:true, childList:true});

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>{ scan(); setTimeout(scan,400); setTimeout(scan,1200); });
  }else{
    scan(); setTimeout(scan,400); setTimeout(scan,1200);
  }
})();
'''.lstrip("\n")

s = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null 2>&1 && echo "[OK] node --check OK"
echo "[NEXT] restart UI + Ctrl+F5 on /vsp5"
