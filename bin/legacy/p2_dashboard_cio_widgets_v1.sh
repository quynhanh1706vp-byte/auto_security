#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_dashboard_luxe_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_cio_${TS}"
echo "[BACKUP] ${JS}.bak_cio_${TS}"

python3 - "$JS" <<'PY'
import sys, textwrap
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_DASHBOARD_CIO_WIDGETS_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* VSP_P2_DASHBOARD_CIO_WIDGETS_V1 */
(function(){
  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs){ for(const k of Object.keys(attrs)) e.setAttribute(k, attrs[k]); }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }
  function esc(s){ return String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c])); }

  async function jget(url){
    const r=await fetch(url, {credentials:"same-origin"});
    const t=await r.text();
    try { return {ok:true, code:r.status, json: JSON.parse(t)}; }
    catch(e){ return {ok:false, code:r.status, text:t}; }
  }

  function postureScore(counts){
    // simple heuristic: heavier weight for higher severity
    const c=counts||{};
    const crit=+(c.CRITICAL||0), hi=+(c.HIGH||0), med=+(c.MEDIUM||0), lo=+(c.LOW||0), info=+(c.INFO||0), trace=+(c.TRACE||0);
    const total=crit+hi+med+lo+info+trace;
    if(total<=0) return {score:100, label:"Clean"};
    const penalty = crit*20 + hi*10 + med*5 + lo*2 + info*1 + trace*0.2;
    const score = Math.max(0, Math.round(100 - Math.min(100, penalty)));
    const label = score>=90?"Strong": score>=75?"Good": score>=55?"Watch": "Risk";
    return {score, label, total};
  }

  function renderTrend(points){
    // lightweight sparkline using SVG, no libs
    const w=420,h=64,pad=6;
    const pts=(points||[]).slice(-40);
    if(!pts.length) return `<div style="opacity:.8">No trend data</div>`;
    const vals=pts.map(x=>+((x.total??x.value??x.y??0)));
    const min=Math.min(...vals), max=Math.max(...vals);
    const sx=(i)=> pad + i*( (w-2*pad) / Math.max(1, vals.length-1) );
    const sy=(v)=> {
      if(max===min) return h/2;
      return pad + (h-2*pad) * (1 - (v-min)/(max-min));
    };
    const d=vals.map((v,i)=> (i? "L":"M")+sx(i).toFixed(1)+","+sy(v).toFixed(1)).join(" ");
    return `
      <svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="trend">
        <path d="${d}" fill="none" stroke="currentColor" stroke-width="2" opacity="0.9"/>
      </svg>
      <div style="font-size:12px;opacity:.8;margin-top:4px">${esc(pts[pts.length-1].label||"")}</div>
    `;
  }

  function ensureContainer(){
    const host = document.querySelector('#vsp-dashboard-main') || document.querySelector('[data-testid="vsp-dashboard-main"]') || document.body;
    let root = document.querySelector('#vsp-cio-root');
    if(root) return root;
    root = el('div', {id:'vsp-cio-root', 'data-testid':'vsp-cio-root'});
    // minimal layout; rely on existing dark css; keep inline for safety
    root.style.cssText = "margin:16px auto;max-width:1200px;padding:0 12px;";
    host.prepend(root);
    return root;
  }

  function card(title, bodyHtml){
    const c=el('div', {'data-testid':'vsp-card'});
    c.style.cssText="background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.08);border-radius:14px;padding:14px;box-shadow:0 10px 25px rgba(0,0,0,0.25)";
    const h=el('div', null, `<div style="font-size:12px;letter-spacing:.08em;opacity:.75;text-transform:uppercase">${esc(title)}</div>`);
    const b=el('div', null, bodyHtml);
    b.style.cssText="margin-top:10px";
    c.appendChild(h); c.appendChild(b);
    return c;
  }

  function row(){
    const r=el('div');
    r.style.cssText="display:grid;gap:12px;grid-template-columns:repeat(12,1fr);align-items:stretch;margin-top:12px";
    return r;
  }

  function col(span, node){
    const wrap=el('div');
    wrap.style.cssText=`grid-column: span ${span};`;
    wrap.appendChild(node);
    return wrap;
  }

  function kpiTile(label, value){
    return `
      <div style="display:flex;flex-direction:column;gap:4px">
        <div style="font-size:12px;opacity:.75">${esc(label)}</div>
        <div style="font-size:22px;font-weight:700">${esc(value)}</div>
      </div>
    `;
  }

  function topFindingsTable(items){
    const rows=(items||[]).slice(0,10).map(it=>{
      const sev=esc(it.severity||"");
      const tool=esc(it.tool||"");
      const title=esc(it.title||"");
      const file=esc(it.file||"");
      return `<tr>
        <td style="padding:8px 10px;opacity:.9">${sev}</td>
        <td style="padding:8px 10px;opacity:.85">${tool}</td>
        <td style="padding:8px 10px;max-width:520px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${title}</td>
        <td style="padding:8px 10px;opacity:.75;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:360px">${file}</td>
      </tr>`;
    }).join("");
    if(!rows) return `<div style="opacity:.8">No findings</div>`;
    return `
      <div style="overflow:auto">
        <table style="width:100%;border-collapse:collapse;font-size:13px">
          <thead>
            <tr style="text-align:left;opacity:.75">
              <th style="padding:8px 10px">Severity</th>
              <th style="padding:8px 10px">Tool</th>
              <th style="padding:8px 10px">Title</th>
              <th style="padding:8px 10px">File</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      </div>`;
  }

  async function run(){
    try{
      const root=ensureContainer();
      root.innerHTML = `<div data-testid="vsp-cio-loading" style="opacity:.8">Loading dashboard…</div>`;

      const ridRes=await jget('/api/vsp/rid_latest');
      const rid = ridRes.ok ? (ridRes.json.rid||"") : "";
      const trendRes=await jget('/api/vsp/trend_v1');
      const topRes=await jget('/api/vsp/top_findings_v1?limit=10');

      // try counts from run_gate_summary.json
      let counts=null;
      if(rid){
        const gate=await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`);
        if(gate.ok && gate.json && gate.json.by_severity) counts = gate.json.by_severity;
        else if(gate.ok && gate.json && gate.json.counts_total) counts = gate.json.counts_total;
      }

      const ps=postureScore(counts||{});
      const kpi = `
        <div style="display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap">
          ${kpiTile("Latest RID", rid || "—")}
          ${kpiTile("Posture", ps.score + " / 100 ("+ps.label+")")}
          ${kpiTile("Total", (ps.total??(topRes.ok? (topRes.json.total??0):0)) )}
        </div>
      `;

      const r1=row();
      r1.appendChild(col(7, card("Security Posture", kpi)));
      r1.appendChild(col(5, card("Trend", renderTrend(trendRes.ok ? (trendRes.json.points||[]) : []))));

      const r2=row();
      r2.appendChild(col(12, card("Top Findings", topFindingsTable(topRes.ok ? (topRes.json.items||[]) : []))));

      root.innerHTML="";
      root.appendChild(r1);
      root.appendChild(r2);
    }catch(e){
      try{
        const root=ensureContainer();
        root.innerHTML = `<div style="opacity:.8">Dashboard error: ${esc(e && e.message ? e.message : e)}</div>`;
      }catch(_){}
    }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", run);
  else run();
})();
""")

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended CIO widgets to dashboard luxe JS")
PY

node -c "$JS"
echo "[OK] node -c OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
else
  echo "[WARN] $SVC not active; restart manually if needed"
fi

echo "== verify dashboard js contains marker =="
grep -n "VSP_P2_DASHBOARD_CIO_WIDGETS_V1" -n "$JS" | head -n 3
