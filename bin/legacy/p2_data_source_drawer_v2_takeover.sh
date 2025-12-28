#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_data_source_lazy_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dsdrawer_v2_${TS}"
echo "[BACKUP] ${JS}.bak_dsdrawer_v2_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_DATA_SOURCE_DRAWER_V2"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=r'''
/* VSP_P2_DATA_SOURCE_DRAWER_V2 */
(function(){
  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs){ for(const k of Object.keys(attrs)) e.setAttribute(k, attrs[k]); }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }
  async function jget(url){
    const r=await fetch(url, {credentials:"same-origin"});
    const ct=(r.headers.get("content-type")||"").toLowerCase();
    if(!ct.includes("json")) throw new Error("non-json");
    return await r.json();
  }
  async function ensureRid(){
    const qp=new URLSearchParams(location.search);
    let rid=qp.get("rid");
    if(rid) return rid;
    const j=await jget("/api/vsp/rid_latest");
    if(j && j.rid){
      qp.set("rid", j.rid);
      history.replaceState({}, "", location.pathname + "?" + qp.toString());
      return j.rid;
    }
    return "";
  }
  function rawUrl(rid, path, download){
    const u=new URL("/api/vsp/run_file_raw_v4", location.origin);
    u.searchParams.set("rid", rid);
    u.searchParams.set("path", path);
    if(download) u.searchParams.set("download","1");
    return u.toString();
  }
  async function loadFindings(rid, limit){
    const u=new URL("/api/vsp/run_file_allow", location.origin);
    u.searchParams.set("rid", rid);
    u.searchParams.set("path","findings_unified.json");
    u.searchParams.set("limit", String(limit||300));
    return await jget(u.toString());
  }
  function normStr(x){ return (x===null||x===undefined) ? "" : String(x); }
  function pick(it, keys){
    for(const k of keys){ if(it && it[k]!==undefined && it[k]!==null && String(it[k]).trim()!=="") return it[k]; }
    return "";
  }
  function sevClass(sev){
    sev=(sev||"").toUpperCase();
    if(sev==="CRITICAL") return "sev-critical";
    if(sev==="HIGH") return "sev-high";
    if(sev==="MEDIUM") return "sev-medium";
    if(sev==="LOW") return "sev-low";
    if(sev==="INFO") return "sev-info";
    return "sev-trace";
  }
  function applyFilter(all, q){
    q=(q||"").trim().toLowerCase();
    if(!q) return all;
    return (all||[]).filter(it=>{
      const blob=[
        pick(it,["tool","source","scanner"]),
        pick(it,["severity","level"]),
        pick(it,["title","name","message"]),
        pick(it,["file","path","location"]),
        pick(it,["rule","check_id","id"]),
        pick(it,["cwe","cwe_id"]),
      ].map(normStr).join(" ").toLowerCase();
      return blob.includes(q);
    });
  }

  function ensureStyles(){
    if(document.getElementById("vsp-ds-drawer-style")) return;
    const css=el("style",{id:"vsp-ds-drawer-style"},`
      .vsp-ds-toolbar{display:flex;gap:10px;align-items:center;padding:10px 12px;border:1px solid rgba(255,255,255,.08);border-radius:14px;margin:12px 0;background:rgba(255,255,255,.03)}
      .vsp-ds-toolbar input{flex:1;min-width:220px;padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:rgba(0,0,0,.25);color:inherit}
      .vsp-ds-toolbar button{padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.06);color:inherit;cursor:pointer}
      .vsp-ds-wrap{position:relative}
      .vsp-ds-table{width:100%;border-collapse:separate;border-spacing:0 8px}
      .vsp-ds-table td,.vsp-ds-table th{padding:10px 12px}
      .vsp-ds-table tbody tr{background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08)}
      .vsp-ds-table tbody tr:hover{background:rgba(255,255,255,.06)}
      .sev-pill{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.12);font-weight:600;font-size:12px}
      .sev-critical{background:rgba(255,0,0,.15)} .sev-high{background:rgba(255,120,0,.14)} .sev-medium{background:rgba(255,200,0,.12)}
      .sev-low{background:rgba(0,180,255,.12)} .sev-info{background:rgba(0,255,180,.10)} .sev-trace{background:rgba(255,255,255,.06)}
      .vsp-ds-drawer{position:fixed;top:0;right:0;height:100vh;width:min(520px,95vw);transform:translateX(110%);transition:transform .18s ease;
        background:rgba(15,15,18,.96);border-left:1px solid rgba(255,255,255,.10);z-index:9999;padding:14px 14px 18px;overflow:auto}
      .vsp-ds-drawer.open{transform:translateX(0)}
      .vsp-ds-drawer .hdr{display:flex;justify-content:space-between;gap:10px;align-items:flex-start}
      .vsp-ds-drawer .btnx{padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.06);cursor:pointer}
      .vsp-ds-drawer .actions{display:flex;flex-wrap:wrap;gap:8px;margin:10px 0 12px}
      .vsp-ds-drawer pre{white-space:pre-wrap;word-break:break-word;background:rgba(0,0,0,.25);padding:10px;border-radius:12px;border:1px solid rgba(255,255,255,.08)}
      .vsp-ds-backdrop{position:fixed;inset:0;background:rgba(0,0,0,.35);z-index:9998;display:none}
      .vsp-ds-backdrop.show{display:block}
    `);
    document.head.appendChild(css);
  }

  function buildDrawer(){
    ensureStyles();
    let bd=document.querySelector('[data-testid="vsp-ds-backdrop"]');
    let dr=document.querySelector('[data-testid="vsp-ds-drawer"]');
    if(!bd){ bd=el("div",{"data-testid":"vsp-ds-backdrop",class:"vsp-ds-backdrop"}); document.body.appendChild(bd); }
    if(!dr){ dr=el("div",{"data-testid":"vsp-ds-drawer",class:"vsp-ds-drawer"}); document.body.appendChild(dr); }
    function close(){ dr.classList.remove("open"); bd.classList.remove("show"); }
    bd.onclick=close;
    return {bd, dr, close};
  }

  async function copyText(t){
    try{ await navigator.clipboard.writeText(t); return true; }catch(e){ return false; }
  }

  document.addEventListener("DOMContentLoaded", async ()=>{
    if(!location.pathname.includes("data_source")) return;

    const root=document.querySelector('[data-testid="vsp-datasource-main"]') || document.body;

    // TAKE OVER: remove older v1 nodes if any
    root.querySelectorAll('[data-testid="vsp-ds-toolbar"],[data-testid="vsp-ds-host"]').forEach(x=>x.remove());

    const rid=await ensureRid();
    const wrap=el("div", {class:"vsp-ds-wrap"});
    const bar=el("div", {"data-testid":"vsp-ds-toolbar", class:"vsp-ds-toolbar"});
    const stat=el("div", {"data-testid":"vsp-ds-stat"}, rid?("RID: "+rid):"RID: (none)");
    const q=el("input", {type:"search", placeholder:"Search findings…", "data-testid":"vsp-ds-search"});
    const btnLoad=el("button", {"data-testid":"vsp-ds-load"}, "Load");
    const btnOpen=el("button", {"data-testid":"vsp-ds-open-raw"}, "Open raw findings_unified.json");
    const btnDl=el("button", {"data-testid":"vsp-ds-dl-raw"}, "Download raw findings_unified.json");
    bar.appendChild(stat); bar.appendChild(q); bar.appendChild(btnLoad); bar.appendChild(btnOpen); bar.appendChild(btnDl);

    const host=el("div", {"data-testid":"vsp-ds-host", class:"vsp-ds-host"});
    wrap.appendChild(host);
    root.prepend(wrap);
    root.prepend(bar);

    const {bd, dr, close}=buildDrawer();

    let allRows=[];
    function render(rows){
      host.innerHTML="";
      const table=el("table",{class:"vsp-ds-table","data-testid":"vsp-ds-table"});
      const thead=el("thead",null,"<tr><th>Tool</th><th>Sev</th><th>Title</th><th>File</th></tr>");
      const tbody=el("tbody");
      (rows||[]).forEach((it, idx)=>{
        const tr=el("tr",{"data-idx":String(idx)});
        tr.style.cursor="pointer";
        const tool=pick(it,["tool","source","scanner"]);
        const sev=pick(it,["severity","level"]);
        const title=pick(it,["title","name","message"]);
        const file=pick(it,["file","path","location"]);
        tr.appendChild(el("td",null,normStr(tool)));
        tr.appendChild(el("td",null,`<span class="sev-pill ${sevClass(sev)}">${normStr(sev)}</span>`));
        tr.appendChild(el("td",null,normStr(title)));
        tr.appendChild(el("td",null,normStr(file)));
        tr.onclick=async ()=>{
          const r=await ensureRid();
          if(!r) return alert("RID missing");

          const title2=pick(it,["title","name","message"]) || "(no title)";
          const tool2=pick(it,["tool","source","scanner"]);
          const sev2=pick(it,["severity","level"]);
          const file2=pick(it,["file","path","location"]);
          const rule2=pick(it,["rule","check_id","id"]);
          const cwe2=pick(it,["cwe","cwe_id"]);

          const jsonPretty=JSON.stringify(it, null, 2);

          dr.innerHTML="";
          const hdr=el("div",{class:"hdr"},
            `<div>
               <div style="font-size:14px;opacity:.9">${normStr(tool2)} • <span class="sev-pill ${sevClass(sev2)}">${normStr(sev2)}</span></div>
               <div style="font-size:16px;font-weight:700;margin-top:6px">${title2}</div>
               <div style="opacity:.8;margin-top:6px">${normStr(file2)}</div>
               <div style="opacity:.75;margin-top:6px">Rule: ${normStr(rule2)} • CWE: ${normStr(cwe2)}</div>
             </div>`
          );
          const btnX=el("button",{class:"btnx","data-testid":"vsp-ds-drawer-close"},"Close");
          btnX.onclick=close;
          hdr.appendChild(btnX);

          const actions=el("div",{class:"actions"});
          const bCopy=el("button",{"data-testid":"vsp-ds-copy-json",class:"btnx"},"Copy JSON");
          const bOpen=el("button",{"data-testid":"vsp-ds-open-raw-file",class:"btnx"},"Open raw findings_unified.json");
          const bDl=el("button",{"data-testid":"vsp-ds-dl-raw-file",class:"btnx"},"Download raw findings_unified.json");
          const bCopyPath=el("button",{"data-testid":"vsp-ds-copy-path",class:"btnx"},"Copy file path");
          actions.appendChild(bCopy); actions.appendChild(bOpen); actions.appendChild(bDl); actions.appendChild(bCopyPath);

          bCopy.onclick=async ()=>{
            const ok=await copyText(jsonPretty);
            if(!ok) alert("Copy failed (clipboard blocked)");
          };
          bOpen.onclick=()=>window.open(rawUrl(r,"findings_unified.json",false),"_blank","noopener");
          bDl.onclick=()=>window.open(rawUrl(r,"findings_unified.json",true),"_blank","noopener");
          bCopyPath.onclick=async ()=>{
            const ok=await copyText(normStr(file2));
            if(!ok) alert("Copy failed (clipboard blocked)");
          };

          dr.appendChild(hdr);
          dr.appendChild(actions);
          dr.appendChild(el("pre",{"data-testid":"vsp-ds-json-pre"}, jsonPretty));
          bd.classList.add("show");
          dr.classList.add("open");
        };
        tbody.appendChild(tr);
      });
      table.appendChild(thead); table.appendChild(tbody);
      host.appendChild(table);
    }

    function refresh(){
      const rows=applyFilter(allRows, q.value);
      render(rows);
    }

    btnOpen.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      window.open(rawUrl(r,"findings_unified.json",false),"_blank","noopener");
    };
    btnDl.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      window.open(rawUrl(r,"findings_unified.json",true),"_blank","noopener");
    };
    btnLoad.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      host.textContent="Loading…";
      try{
        const j=await loadFindings(r, 300);
        const arr=(j && (j.findings||j.items||j.data)) || [];
        allRows=Array.isArray(arr)?arr:[];
        refresh();
      }catch(e){
        host.textContent="Load failed";
      }
    };
    q.addEventListener("input", refresh);

  });
})();
'''
p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended drawer v2 takeover")
PY

node -c "$JS"
echo "[OK] node -c OK"
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== verify marker =="
grep -n "VSP_P2_DATA_SOURCE_DRAWER_V2" -n "$JS" | head -n 3 || true
