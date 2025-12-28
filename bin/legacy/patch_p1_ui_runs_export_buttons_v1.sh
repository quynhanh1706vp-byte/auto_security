#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_exportui_${TS}"
echo "[BACKUP] ${F}.bak_exportui_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_EXPORT_BUTTONS_UI_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
/* VSP_P1_EXPORT_BUTTONS_UI_V1 */
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
        box.style.maxWidth="520px";
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
      setTimeout(()=>{ try{ item.remove(); }catch(e){} }, 3500);
    }catch(e){}
  }

  function extractRid(txt){
    txt = (txt||"").toString();
    // match both "RUN_xxx" and "xxx_RUN_yyy"
    const m = txt.match(/[A-Za-z0-9][A-Za-z0-9:_-]*_RUN_[A-Za-z0-9:_-]+/);
    if (m) return m[0];
    const m2 = txt.match(/RUN_[A-Za-z0-9:_-]+/);
    return m2 ? m2[0] : null;
  }

  function ridFromRow(tr){
    if(!tr) return null;
    // dataset hints
    if(tr.dataset){
      if(tr.dataset.rid) return tr.dataset.rid;
      if(tr.dataset.runId) return tr.dataset.runId;
      if(tr.dataset.runid) return tr.dataset.runid;
    }
    const txt = (tr.innerText || tr.textContent || "");
    return extractRid(txt);
  }

  function mkBtn(label, href){
    const a=document.createElement("a");
    a.href=href;
    a.textContent=label;
    a.target="_blank";
    a.rel="noopener";
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
      const msg = "SHA256 run_gate_summary.json: " + j.sha256;
      toast(msg, true);
      try{ await navigator.clipboard.writeText(j.sha256); toast("Copied SHA to clipboard", true);}catch(e){}
    }catch(e){
      toast("SHA verify failed for "+rid, false);
    }
  }

  function attachOne(tr){
    if(!tr || tr.querySelector('[data-vsp-exp="1"]')) return;
    const rid = ridFromRow(tr);
    if(!rid) return;

    const wrap=document.createElement("span");
    wrap.setAttribute("data-vsp-exp","1");
    wrap.style.whiteSpace="nowrap";
    wrap.style.marginLeft="6px";

    const tgz="/api/vsp/export_tgz?rid="+encodeURIComponent(rid)+"&scope=reports";
    const csv="/api/vsp/export_csv?rid="+encodeURIComponent(rid);

    wrap.appendChild(mkBtn("TGZ", tgz));
    wrap.appendChild(mkBtn("CSV", csv));

    const sha=document.createElement("a");
    sha.href="#";
    sha.textContent="SHA";
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

    // put into last cell
    const tds = tr.querySelectorAll("td");
    const cell = (tds && tds.length) ? tds[tds.length-1] : tr;
    cell.appendChild(wrap);
  }

  function scan(){
    const trs = document.querySelectorAll("tr");
    trs.forEach(attachOne);
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

if command -v node >/dev/null 2>&1; then
  node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 3; }
fi

echo "[NEXT] restart UI + Ctrl+F5 on /vsp5"
