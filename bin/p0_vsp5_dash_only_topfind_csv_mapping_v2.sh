#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_topfind_csvmap_v2_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_csvmap_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import subprocess

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_DASH_ONLY_TOPFIND_CSV_MAPPING_V2"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    s += r"""

/* VSP_P0_DASH_ONLY_TOPFIND_CSV_MAPPING_V2
   - Use reports/findings_unified.csv (allowed=200)
   - Exact mapping: severity,tool,rule_id,title,file,line,message
   - Location = file:line
   - Title = title (fallback: rule_id) + (message short)
   - Capture-phase click override to avoid older hooks fighting
*/
(()=> {
  if (window.__vsp_p0_dash_only_topfind_csv_mapping_v2) return;
  window.__vsp_p0_dash_only_topfind_csv_mapping_v2 = true;

  const SEV_W = {CRITICAL:600, HIGH:500, MEDIUM:400, LOW:300, INFO:200, TRACE:100};
  const norm = (v)=> (v==null ? "" : String(v)).trim();
  const up   = (v)=> norm(v).toUpperCase();
  const clip = (t, n)=> { t=norm(t); return (t.length>n) ? (t.slice(0,n-1)+"…") : t; };

  const parseCSV = (txt)=>{
    const rows=[]; let i=0, cur="", row=[], inQ=false;
    const pushCell=()=>{ row.push(cur); cur=""; };
    const pushRow=()=>{ rows.push(row); row=[]; };
    while(i<txt.length){
      const ch=txt[i++];
      if(inQ){
        if(ch==='"'){
          if(txt[i]==='"'){ cur+='"'; i++; } else inQ=false;
        } else cur+=ch;
      } else {
        if(ch==='"') inQ=true;
        else if(ch===',') pushCell();
        else if(ch==='\n'){ pushCell(); pushRow(); }
        else if(ch==='\r'){ /* ignore */ }
        else cur+=ch;
      }
    }
    if(cur.length || row.length){ pushCell(); pushRow(); }
    return rows.filter(r=> r.some(c=> String(c||"").trim()!==""));
  };

  const getRID = async ()=>{
    const r = await fetch("/api/vsp/rid_latest_gate_root");
    const j = await r.json();
    return j && j.rid ? j.rid : "";
  };

  const findTopHost = ()=>{
    // Try to find the "Top findings" card
    const cards = Array.from(document.querySelectorAll("div,section"));
    for(const c of cards){
      const t = (c.textContent||"");
      if(t.includes("Top findings")) return c;
    }
    return document.body;
  };

  const ensureTable = ()=>{
    const host = findTopHost();
    let table = host.querySelector("table");
    if(!table){
      table = document.createElement("table");
      table.style.width="100%";
      table.style.borderCollapse="collapse";
      table.innerHTML = "<thead><tr><th>Severity</th><th>Tool</th><th>Title</th><th>Location</th></tr></thead><tbody></tbody>";
      host.appendChild(table);
    }
    return table;
  };

  const render = (items)=>{
    const table = ensureTable();
    const tbody = table.querySelector("tbody") || table.appendChild(document.createElement("tbody"));
    tbody.innerHTML = "";
    for(const it of items){
      const tr=document.createElement("tr");
      const cells=[it.severity,it.tool,it.title,it.location];
      for(const c of cells){
        const td=document.createElement("td");
        td.textContent = c || "";
        td.style.padding="8px 10px";
        td.style.borderTop="1px solid rgba(255,255,255,0.06)";
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
  };

  const loadTopCsv = async (limit=25)=>{
    const rid = await getRID();
    if(!rid) throw new Error("no rid");
    const path = "reports/findings_unified.csv";
    const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
    const resp = await fetch(url);
    if(!resp.ok) throw new Error("csv fetch failed: "+resp.status);
    const txt = await resp.text();
    const rows = parseCSV(txt);
    if(rows.length < 2) throw new Error("csv empty");

    const h = rows[0].map(x=> norm(x));
    const idx = (k)=> h.indexOf(k);

    // exact expected headers
    const iSev = idx("severity");
    const iTool= idx("tool");
    const iRid = idx("rule_id");
    const iTit = idx("title");
    const iFile= idx("file");
    const iLine= idx("line");
    const iMsg = idx("message");

    const items=[];
    for(let r=1;r<rows.length;r++){
      const row = rows[r];
      const sevRaw = (iSev>=0? row[iSev] : "");
      let sev = up(sevRaw);
      if(sev==="CRIT") sev="CRITICAL";
      if(!sev) sev="";

      const tool = norm(iTool>=0? row[iTool] : "");
      const rid2 = norm(iRid>=0? row[iRid] : "");
      const tit  = norm(iTit>=0? row[iTit] : "");
      const file = norm(iFile>=0? row[iFile] : "");
      const line = norm(iLine>=0? row[iLine] : "");
      const msg  = norm(iMsg>=0? row[iMsg] : "");

      const titleBase = tit || rid2 || "(no title)";
      const title = msg ? (titleBase + " — " + clip(msg, 140)) : titleBase;
      const loc = (file && line) ? `${file}:${line}` : (file || "");

      items.push({severity:sev, tool, title, location:loc});
    }

    items.sort((a,b)=> (SEV_W[b.severity]||0)-(SEV_W[a.severity]||0));
    render(items.slice(0, limit));
    return true;
  };

  const hook = ()=>{
    const btns = Array.from(document.querySelectorAll("button,a"));
    const b = btns.find(x=> (x.textContent||"").toLowerCase().includes("load top findings"));
    if(!b) return false;

    // CAPTURE override: stop old hooks fighting
    b.addEventListener("click", async (ev)=>{
      ev.preventDefault();
      ev.stopPropagation();
      if (ev.stopImmediatePropagation) ev.stopImmediatePropagation();

      const old = b.textContent || "Load top findings (25)";
      try{
        b.textContent = "Loading…";
        b.disabled = true;
        await loadTopCsv(25);
        b.textContent = old;
        console.log("[VSP][DASH_ONLY] topfind csv v2 loaded");
      }catch(e){
        console.warn("[VSP][DASH_ONLY] topfind csv v2 failed:", e);
        b.textContent = old;
      }finally{
        b.disabled = false;
      }
    }, true);

    console.log("[VSP][DASH_ONLY] topfind csv v2 hook bound");
    return true;
  };

  let tries=0;
  const t=setInterval(()=>{ tries++; if(hook() || tries>=12) clearInterval(t); }, 500);
})();
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", MARK)

subprocess.check_call(["node","--check","static/js/vsp_dash_only_v1.js"])
print("[OK] node --check passed")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R) then click: Load top findings (25)."
