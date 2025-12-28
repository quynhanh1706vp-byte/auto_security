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
cp -f "$JS" "${JS}.bak_topfind_csv_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_csv_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_DASH_ONLY_TOPFIND_USE_CSV_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    s += r"""

/* VSP_P0_DASH_ONLY_TOPFIND_USE_CSV_V1 */
(()=> {
  if (window.__vsp_p0_dash_only_topfind_use_csv_v1) return;
  window.__vsp_p0_dash_only_topfind_use_csv_v1 = true;

  const SEV_W = {CRITICAL: 600, HIGH: 500, MEDIUM: 400, LOW: 300, INFO: 200, TRACE: 100};
  const norm = (v)=> (v==null ? "" : String(v)).trim();
  const up = (v)=> norm(v).toUpperCase();

  // minimal CSV parser (handles quotes + commas)
  const parseCSV = (txt)=>{
    const rows = [];
    let i=0, cur="", row=[], inQ=false;
    const pushCell=()=>{ row.push(cur); cur=""; };
    const pushRow=()=>{ rows.push(row); row=[]; };
    while (i < txt.length) {
      const ch = txt[i++];
      if (inQ) {
        if (ch === '"') {
          if (txt[i] === '"') { cur += '"'; i++; } else { inQ = false; }
        } else cur += ch;
      } else {
        if (ch === '"') inQ = true;
        else if (ch === ',') pushCell();
        else if (ch === '\n') { pushCell(); pushRow(); }
        else if (ch === '\r') { /* ignore */ }
        else cur += ch;
      }
    }
    // last
    if (cur.length || row.length) { pushCell(); pushRow(); }
    // drop empty tail rows
    return rows.filter(r=> r.some(c=> String(c||"").trim() !== ""));
  };

  const normKey = (k)=> norm(k).toLowerCase().replace(/[^a-z0-9]+/g,"");
  const pickKey = (keys, wants)=>{
    const kmap = new Map(keys.map(k=> [normKey(k), k]));
    for (const w of wants) {
      for (const [nk, orig] of kmap.entries()){
        if (nk === w) return orig;
      }
    }
    // contains fallback
    for (const w of wants) {
      for (const [nk, orig] of kmap.entries()){
        if (nk.includes(w)) return orig;
      }
    }
    return "";
  };

  const getRID = async ()=>{
    try{
      const r = await fetch("/api/vsp/rid_latest_gate_root");
      const j = await r.json();
      return j && j.rid ? j.rid : "";
    }catch(e){ return ""; }
  };

  const findTopBlock = ()=>{
    // find by heading text if possible
    const nodes = Array.from(document.querySelectorAll("div,section"));
    for (const n of nodes){
      const t = (n.textContent || "");
      if (t.includes("Top findings")) return n;
    }
    // fallback: first table container
    return document.querySelector("table")?.parentElement || document.body;
  };

  const renderTable = (items)=>{
    const host = findTopBlock();
    let table = host.querySelector("table");
    if (!table) {
      table = document.createElement("table");
      table.style.width="100%";
      table.style.borderCollapse="collapse";
      table.innerHTML = "<thead><tr><th>Severity</th><th>Tool</th><th>Title</th><th>Location</th></tr></thead><tbody></tbody>";
      host.appendChild(table);
    }
    const tbody = table.querySelector("tbody") || table.appendChild(document.createElement("tbody"));
    tbody.innerHTML = "";
    for (const it of items){
      const tr = document.createElement("tr");
      const cells = [it.severity, it.tool, it.title, it.location];
      for (const c of cells){
        const td = document.createElement("td");
        td.textContent = c || "";
        td.style.padding="8px 10px";
        td.style.borderTop="1px solid rgba(255,255,255,0.06)";
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
  };

  const loadTop = async (limit=25)=>{
    const rid = await getRID();
    if (!rid) throw new Error("no rid");
    const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent("reports/findings_unified.csv")}`;
    const resp = await fetch(url);
    if (!resp.ok) throw new Error("csv fetch failed: "+resp.status);
    const txt = await resp.text();
    const rows = parseCSV(txt);
    if (!rows.length) throw new Error("empty csv");
    const header = rows[0];
    const keys = header;

    const kSev = pickKey(keys, ["severity","sev","level","risk","prio","priority"]);
    const kTool = pickKey(keys, ["tool","scanner","source","engine"]);
    const kTitle = pickKey(keys, ["title","rule","message","name","check","id"]);
    const kLoc  = pickKey(keys, ["location","path","file","filename","resource","uri"]);

    const idx = (k)=> k ? keys.indexOf(k) : -1;

    const iSev = idx(kSev);
    const iTool= idx(kTool);
    const iTit = idx(kTitle);
    const iLoc = idx(kLoc);

    const items = [];
    for (let r=1;r<rows.length;r++){
      const row = rows[r];
      const sevRaw = (iSev>=0? row[iSev] : "");
      const sev = up(sevRaw);
      const sevN = (sev==="CRIT"?"CRITICAL":sev);
      items.push({
        severity: sevN || "",
        tool: norm(iTool>=0? row[iTool] : ""),
        title: norm(iTit>=0? row[iTit] : ""),
        location: norm(iLoc>=0? row[iLoc] : "")
      });
    }

    // sort by severity weight desc then keep first N
    items.sort((a,b)=> (SEV_W[b.severity]||0)-(SEV_W[a.severity]||0));
    renderTable(items.slice(0, limit));
    return true;
  };

  const hookBtn = ()=>{
    const btns = Array.from(document.querySelectorAll("button,a"));
    const target = btns.find(b=> (b.textContent||"").toLowerCase().includes("load top findings"));
    if (!target) return false;

    // override click (avoid previous handlers)
    target.addEventListener("click", async (ev)=>{
      ev.preventDefault();
      ev.stopPropagation();
      try{
        const old = target.textContent;
        target.textContent = "Loading…";
        target.disabled = true;
        await loadTop(25);
        target.textContent = old || "Load top findings (25)";
      }catch(e){
        console.warn("[VSP][DASH_ONLY] topfind csv load failed:", e);
        target.textContent = "Load top findings (25)";
      }finally{
        target.disabled = false;
      }
    }, true);

    console.log("[VSP][DASH_ONLY] topfind csv hook bound");
    return true;
  };

  // bind now + retry a few times
  let tries=0;
  const t = setInterval(()=>{
    tries++;
    if (hookBtn() || tries>=10) clearInterval(t);
  }, 500);
})();
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", MARK)

import subprocess
subprocess.check_call(["node","--check","static/js/vsp_dash_only_v1.js"])
print("[OK] node --check passed")
PY

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R) then click: Load top findings (25)."
