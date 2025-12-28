#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p0dash_${TS}"
echo "[BACKUP] ${JS}.bak_p0dash_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_DASHBOARD_CLEANUP_TOOLLANE_AUDIT_V1"
if MARK in s:
    print("[OK] marker exists; skip")
    raise SystemExit(0)

addon = r'''
/* ===================== VSP_P0_DASHBOARD_CLEANUP_TOOLLANE_AUDIT_V1 ===================== */
(()=> {
  if (window.__vsp_p0_dash_cleanup_toollane_audit_v1) return;
  window.__vsp_p0_dash_cleanup_toollane_audit_v1 = true;

  const TOOLS = ["Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","Bandit","CodeQL"];

  const onVsp5 = () => (location.pathname === "/vsp5" || document.querySelector("meta[name='vsp-page'][content='vsp5']"));
  if (!onVsp5()) return;

  const safeText = (x)=> (x==null?"":String(x));
  const $(q,el=document){ return el.querySelector(q); }
  const $all(q,el=document){ return Array.from(el.querySelectorAll(q)); }

  // ---- (1) Collapse legacy/duplicate sections (heuristic; zero template edits)
  function collapseLegacy(){
    try{
      const roots = [];
      const main = $("#vsp5_root") || $("#app") || $("main") || document.body;
      roots.push(main);

      // Hide obvious legacy blocks by headings/text
      const legacyHints = [/dashboard\s+live/i, /legacy/i, /old\s+dashboard/i, /gate\s*story/i];
      const blocks = $all("section,div").filter(el=>{
        const t = (el.innerText||"").slice(0,300);
        if (t.length < 40) return false;
        return legacyHints.some(rx=>rx.test(t));
      });

      // Keep first “main” dashboard, collapse the rest
      let kept = 0;
      blocks.forEach(el=>{
        // do not hide if it contains KPI cards / the first big dashboard area
        const t = (el.innerText||"").slice(0,120);
        if (kept === 0 && /dashboard/i.test(t)) { kept++; return; }
        el.style.display = "none";
        el.setAttribute("data-vsp-collapsed-legacy","1");
      });

      // If page is very long, also hide everything below the first large dashboard container
      const big = $all("section,div").find(el=> (el.querySelectorAll("canvas,svg,table").length>=1) && (el.innerText||"").includes("Overall"));
      if (big){
        const after = [];
        let seen=false;
        for (const child of Array.from(document.body.children)){
          if (child===big) { seen=true; continue; }
          if (seen) after.push(child);
        }
        // hide only clearly duplicated dashboard parts
        after.forEach(el=>{
          if ((el.innerText||"").match(/Top Findings|Tool Lane|Evidence|Audit/i)){
            el.style.display="none";
            el.setAttribute("data-vsp-collapsed-legacy","1");
          }
        });
      }
    }catch(e){ /* no throw */ }
  }

  // ---- helpers: fetch JSON from run_file_allow
  async function fetchRunJson(rid, path){
    const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
    const r = await fetch(url, {cache:"no-store"});
    if (!r.ok) throw new Error(`${path} http=${r.status}`);
    const ct = (r.headers.get("content-type")||"").toLowerCase();
    if (ct.includes("application/json")) return await r.json();
    const txt = await r.text();
    try{ return JSON.parse(txt); }catch{ return {__raw:txt}; }
  }

  async function latestRid(){
    const r = await fetch("/api/vsp/latest_rid", {cache:"no-store"});
    if (!r.ok) throw new Error("latest_rid failed");
    const j = await r.json();
    return j.rid;
  }

  function toolStatusFromGateSummary(gs){
    // prefer: gs.by_tool[tool].status + degraded flags; fallback heuristics
    const out = {};
    const by = (gs && (gs.by_tool || gs.byTool)) || {};
    TOOLS.forEach(t=>{
      const k = Object.keys(by).find(x=>x.toLowerCase()===t.toLowerCase()) || null;
      const it = k ? by[k] : null;
      const degraded = !!(it && (it.degraded || it.timeout || it.is_degraded));
      const missing  = !(it && (it.present || it.ok || it.has_output || it.has_artifact)) && !it;
      let st = "MISSING";
      if (degraded) st = "DEGRADED";
      else if (!missing) st = "OK";
      out[t]=st;
    });
    return out;
  }

  function mountLane(){
    const host = $("#vsp_tool_lane") || $("[data-vsp-tool-lane]") || $("#vsp_dashboard_body") || $("main") || document.body;
    let box = $("#vsp_p0_tool_lane_box");
    if (!box){
      box = document.createElement("div");
      box.id="vsp_p0_tool_lane_box";
      box.style.cssText="margin:12px 0;padding:12px;border:1px solid rgba(255,255,255,.08);border-radius:14px;background:rgba(255,255,255,.02)";
      box.innerHTML = `<div style="display:flex;justify-content:space-between;align-items:center;gap:10px">
        <div style="font-weight:700">Tool Lane (8 tools)</div>
        <div id="vsp_p0_tool_lane_meta" style="opacity:.75;font-size:12px"></div>
      </div>
      <div id="vsp_p0_tool_lane_grid" style="margin-top:10px;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px"></div>`;
      host.prepend(box);
    }
    return box;
  }

  function renderLane(statusMap){
    const grid = $("#vsp_p0_tool_lane_grid");
    if (!grid) return;
    grid.innerHTML = "";
    TOOLS.forEach(t=>{
      const st = statusMap[t] || "UNKNOWN";
      const chip = document.createElement("div");
      chip.style.cssText="padding:10px;border-radius:12px;border:1px solid rgba(255,255,255,.08);background:rgba(0,0,0,.18)";
      chip.innerHTML = `<div style="font-weight:650">${t}</div><div style="margin-top:4px;font-size:12px;opacity:.85">${st}</div>`;
      grid.appendChild(chip);
    });
  }

  function mountAudit(){
    const host = $("#vsp_audit_ready") || $("[data-vsp-audit]") || $("#vsp_dashboard_body") || $("main") || document.body;
    let box = $("#vsp_p0_audit_box");
    if (!box){
      box = document.createElement("div");
      box.id="vsp_p0_audit_box";
      box.style.cssText="margin:12px 0;padding:12px;border:1px solid rgba(255,255,255,.08);border-radius:14px;background:rgba(255,255,255,.02)";
      box.innerHTML = `<div style="font-weight:700">Evidence & Audit Readiness</div>
        <div id="vsp_p0_audit_line" style="margin-top:8px;opacity:.85"></div>
        <div id="vsp_p0_audit_missing" style="margin-top:6px;font-size:12px;opacity:.8"></div>`;
      host.appendChild(box);
    }
    return box;
  }

  function setAudit(ok, missing, rid){
    const line = $("#vsp_p0_audit_line");
    const miss = $("#vsp_p0_audit_missing");
    if (!line || !miss) return;
    if (ok){
      line.innerHTML = `AUDIT READY • <a href="/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent("run_evidence_index.json")}" target="_blank" rel="noreferrer">run_evidence_index.json</a> • <a href="/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent("run_manifest.json")}" target="_blank" rel="noreferrer">run_manifest.json</a>`;
      miss.textContent = "";
    }else{
      line.textContent = "MISSING EVIDENCE";
      miss.textContent = `missing: [${missing.join(", ")}]`;
    }
  }

  async function main(){
    collapseLegacy();

    const rid = await latestRid();
    const gs = await fetchRunJson(rid, "run_gate_summary.json");
    const stMap = toolStatusFromGateSummary(gs);
    mountLane();
    renderLane(stMap);
    const meta = $("#vsp_p0_tool_lane_meta");
    if (meta) meta.textContent = `RID=${rid}`;

    // audit: require manifest + evidence_index readable
    const missing = [];
    try{ await fetchRunJson(rid, "run_manifest.json"); }catch{ missing.push("run_manifest.json"); }
    try{ await fetchRunJson(rid, "run_evidence_index.json"); }catch{ missing.push("run_evidence_index.json"); }
    mountAudit();
    setAudit(missing.length===0, missing, rid);
  }

  main().catch(()=>{ /* do not spam console */ });
})();
 /* ===================== /VSP_P0_DASHBOARD_CLEANUP_TOOLLANE_AUDIT_V1 ===================== */
'''
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended addon")
PY

node --check static/js/vsp_bundle_commercial_v2.js
systemctl restart "$SVC"
echo "[DONE] reload /vsp5"
