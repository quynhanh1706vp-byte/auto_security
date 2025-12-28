#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_runs_kpi_compact_v3.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_runsdrawer_${TS}"
echo "[BACKUP] ${JS}.bak_runsdrawer_${TS}"

python3 - "$JS" <<'PY'
import sys, textwrap
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_RUNS_DRILLDOWN_DRAWER_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* VSP_P2_RUNS_DRILLDOWN_DRAWER_V1 */
(function(){
  function esc(s){ return String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c])); }
  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs){ for(const k of Object.keys(attrs)) e.setAttribute(k, attrs[k]); }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }
  async function jget(url){
    const r=await fetch(url, {credentials:"same-origin"});
    const t=await r.text();
    try { return {ok:true, json: JSON.parse(t)}; } catch(e){ return {ok:false, text:t, code:r.status}; }
  }
  function isRuns(){ return String(location.pathname||"").includes("/runs"); }

  function ensureDrawer(){
    let d=document.querySelector('[data-testid="runs-drawer"]');
    if(d) return d;

    d=el('div', {'data-testid':'runs-drawer'});
    d.style.cssText=[
      "position:fixed","top:0","right:0","height:100vh","width:min(520px, 96vw)",
      "background:rgba(15,18,24,0.96)","backdrop-filter:blur(10px)",
      "border-left:1px solid rgba(255,255,255,0.10)",
      "box-shadow:-20px 0 40px rgba(0,0,0,0.45)",
      "transform:translateX(110%)","transition:transform 160ms ease",
      "z-index:9999","display:flex","flex-direction:column"
    ].join(";");

    const header=el('div', {'data-testid':'runs-drawer-header'});
    header.style.cssText="padding:14px 14px 10px 14px;border-bottom:1px solid rgba(255,255,255,0.10);display:flex;justify-content:space-between;align-items:flex-start;gap:10px";
    header.innerHTML = `
      <div>
        <div style="font-size:12px;opacity:.75;letter-spacing:.08em;text-transform:uppercase">Run detail</div>
        <div data-testid="runs-drawer-rid" style="margin-top:6px;font-size:16px;font-weight:800">—</div>
        <div data-testid="runs-drawer-ts" style="margin-top:3px;font-size:12px;opacity:.75">—</div>
      </div>
      <button data-testid="runs-drawer-close" style="padding:8px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit;cursor:pointer">Close</button>
    `;

    const actions=el('div', {'data-testid':'runs-drawer-actions'});
    actions.style.cssText="padding:10px 14px;display:flex;gap:10px;flex-wrap:wrap;border-bottom:1px solid rgba(255,255,255,0.10)";
    actions.innerHTML = `
      <a data-testid="runs-open-dashboard" href="#" target="_blank" rel="noopener"
         style="display:inline-flex;align-items:center;gap:8px;padding:8px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);text-decoration:none;color:inherit;font-size:13px">Open Dashboard</a>
      <a data-testid="runs-open-files" href="#" target="_blank" rel="noopener"
         style="display:inline-flex;align-items:center;gap:8px;padding:8px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);text-decoration:none;color:inherit;font-size:13px">Findings JSON</a>
      <a data-testid="runs-open-gate" href="#" target="_blank" rel="noopener"
         style="display:inline-flex;align-items:center;gap:8px;padding:8px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);text-decoration:none;color:inherit;font-size:13px">Gate Summary</a>
    `;

    const body=el('div', {'data-testid':'runs-drawer-body'});
    body.style.cssText="padding:12px 14px;overflow:auto;flex:1";
    body.innerHTML = `<div style="opacity:.8">Select a run to view details.</div>`;

    d.appendChild(header);
    d.appendChild(actions);
    d.appendChild(body);
    document.body.appendChild(d);

    // close handlers
    header.querySelector('[data-testid="runs-drawer-close"]').onclick=()=>hideDrawer();
    document.addEventListener("keydown", (e)=>{ if(e.key==="Escape") hideDrawer(); });

    return d;
  }

  function showDrawer(){ const d=ensureDrawer(); d.style.transform="translateX(0)"; }
  function hideDrawer(){ const d=document.querySelector('[data-testid="runs-drawer"]'); if(d) d.style.transform="translateX(110%)"; }

  function sevBadgeRow(counts){
    const order=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const c=counts||{};
    const pills=order.map(k=>{
      const v=+(c[k]||0);
      return `<div style="padding:10px 12px;border-radius:14px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.03)">
        <div style="font-size:11px;opacity:.75;letter-spacing:.06em">${k}</div>
        <div style="font-size:20px;font-weight:800;margin-top:4px">${v}</div>
      </div>`;
    }).join("");
    return `<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px">${pills}</div>`;
  }

  async function loadRunDetail(rid, tsText){
    const d=ensureDrawer();
    d.querySelector('[data-testid="runs-drawer-rid"]').textContent=rid||"—";
    d.querySelector('[data-testid="runs-drawer-ts"]').textContent=tsText||"—";

    // action links
    d.querySelector('[data-testid="runs-open-dashboard"]').href = "/vsp5?rid="+encodeURIComponent(rid);
    // Try both findings paths; we’ll set to first that exists
    d.querySelector('[data-testid="runs-open-files"]').href = "#";
    d.querySelector('[data-testid="runs-open-gate"]').href = "#";

    const body=d.querySelector('[data-testid="runs-drawer-body"]');
    body.innerHTML = `<div style="opacity:.8">Loading…</div>`;
    showDrawer();

    // Helper to check file exists via run_file_allow
    async function rf(path){
      return await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}&limit=1`);
    }

    // Gate summary
    let gatePath="run_gate_summary.json";
    let gate=await rf(gatePath);
    if(!(gate.ok && gate.json && gate.json.ok)){
      gatePath="reports/run_gate_summary.json";
      gate=await rf(gatePath);
    }

    // Findings json
    let findPath="findings_unified.json";
    let fj=await rf(findPath);
    if(!(fj.ok && fj.json && fj.json.ok)){
      findPath="reports/findings_unified.json";
      fj=await rf(findPath);
    }

    // set action hrefs to the API endpoint (downloadable JSON)
    if(gate.ok && gate.json && gate.json.ok){
      d.querySelector('[data-testid="runs-open-gate"]').href =
        `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(gatePath)}&limit=2000`;
    } else {
      d.querySelector('[data-testid="runs-open-gate"]').style.opacity="0.45";
    }
    if(fj.ok && fj.json && fj.json.ok){
      d.querySelector('[data-testid="runs-open-files"]').href =
        `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(findPath)}&limit=2000`;
    } else {
      d.querySelector('[data-testid="runs-open-files"]').style.opacity="0.45";
    }

    // Render counts from gate if present
    let counts = null;
    if(gate.ok && gate.json){
      // gate.json could be file wrapper or already gate summary depending on backend
      const g = gate.json;
      counts = g.by_severity || g.counts_total || g.counts || null;
    }

    body.innerHTML = `
      <div style="font-size:12px;opacity:.75;letter-spacing:.08em;text-transform:uppercase;margin-bottom:10px">Severity</div>
      ${sevBadgeRow(counts)}
      <div style="height:12px"></div>
      <div style="font-size:12px;opacity:.75;letter-spacing:.08em;text-transform:uppercase;margin-bottom:8px">Links</div>
      <div style="display:grid;gap:8px">
        <div style="padding:10px 12px;border-radius:14px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.03)">
          <div style="opacity:.8">Gate path</div>
          <div style="font-family:ui-monospace, SFMono-Regular, Menlo, monospace; font-size:12px; opacity:.85; margin-top:6px">${esc(gatePath)}</div>
        </div>
        <div style="padding:10px 12px;border-radius:14px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.03)">
          <div style="opacity:.8">Findings path</div>
          <div style="font-family:ui-monospace, SFMono-Regular, Menlo, monospace; font-size:12px; opacity:.85; margin-top:6px">${esc(findPath)}</div>
        </div>
      </div>
      <div style="height:10px"></div>
      <div style="opacity:.7;font-size:12px">Tip: Use “Open Dashboard” to inspect this RID on /vsp5.</div>
    `;
  }

  function hookTableClicks(){
    // Our injected table uses data-testid="runs-table-host" and row data-rid
    const host=document.querySelector('[data-testid="runs-table-host"]');
    if(!host) return;
    host.querySelectorAll("tbody tr[data-rid]").forEach(tr=>{
      if(tr.getAttribute("data-runs-hooked")==="1") return;
      tr.setAttribute("data-runs-hooked","1");
      const rid=tr.getAttribute("data-rid")||"";
      const tds=tr.querySelectorAll("td");
      const tsText = (tds && tds.length>1) ? (tds[1].textContent||"") : "";
      tr.addEventListener("dblclick", (e)=>{ e.preventDefault(); loadRunDetail(rid, tsText).catch(()=>{}); });
      // single click: if user clicks while holding Alt, open drawer (avoid changing your copy-to-clipboard behavior)
      tr.addEventListener("click", (e)=>{
        if(e.altKey){
          e.preventDefault();
          loadRunDetail(rid, tsText).catch(()=>{});
        }
      });
    });
  }

  function boot(){
    if(!isRuns()) return;
    ensureDrawer();
    // watch DOM changes because table is re-rendered by filterbar refresh
    const obs=new MutationObserver(()=>hookTableClicks());
    obs.observe(document.body, {subtree:true, childList:true});
    hookTableClicks();
  }

  if(isRuns()){
    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  }
})();
""")

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended runs drilldown drawer v1")
PY

node -c "$JS"
echo "[OK] node -c OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

grep -n "VSP_P2_RUNS_DRILLDOWN_DRAWER_V1" -n "$JS" | head -n 3
