#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p0_placeholder_${TS}"
echo "[BACKUP] ${JS}.bak_p0_placeholder_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_KPI_CHARTS_PLACEHOLDER_IF_EMPTY_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block=r"""
/* VSP_P0_KPI_CHARTS_PLACEHOLDER_IF_EMPTY_V1
   If dash_kpis/dash_charts return empty objects, render enterprise placeholders
   so the dashboard doesn't look "broken" under policy-degraded mode.
*/
(function(){
  function el(tag, cls, html){
    var d=document.createElement(tag);
    if (cls) d.className=cls;
    if (html!=null) d.innerHTML=html;
    return d;
  }

  function findMain(){
    return document.getElementById("vsp-dashboard-main") || document.querySelector("#vsp-dashboard-main");
  }

  function ensurePlaceholderStyles(){
    if (document.getElementById("vsp-p0-empty-style")) return;
    var st=el("style", null, `
      .vsp-empty-wrap{margin:14px 0 8px 0;padding:14px;border:1px solid rgba(255,255,255,.08);border-radius:14px;background:rgba(255,255,255,.03)}
      .vsp-empty-title{font-weight:700;font-size:14px;opacity:.9;margin-bottom:8px}
      .vsp-empty-sub{font-size:12px;opacity:.75;line-height:1.35}
      .vsp-kpi-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:10px}
      .vsp-kpi-card{padding:12px;border-radius:14px;border:1px solid rgba(255,255,255,.08);background:rgba(0,0,0,.15)}
      .vsp-kpi-k{font-size:11px;opacity:.7}
      .vsp-kpi-v{font-size:18px;font-weight:800;margin-top:4px;opacity:.85}
      .vsp-chart-ph{height:160px;border-radius:14px;border:1px dashed rgba(255,255,255,.16);display:flex;align-items:center;justify-content:center;margin-top:12px;opacity:.8}
      @media (max-width: 1100px){ .vsp-kpi-grid{grid-template-columns:repeat(2,minmax(0,1fr));} }
    `);
    st.id="vsp-p0-empty-style";
    document.head.appendChild(st);
  }

  async function fetchJson(url){
    try{
      var r=await fetch(url,{credentials:"same-origin"});
      return await r.json();
    }catch(e){ return null; }
  }

  function isEmptyObj(o){
    return o && typeof o==="object" && !Array.isArray(o) && Object.keys(o).length===0;
  }

  function render(main, via){
    ensurePlaceholderStyles();
    if (document.getElementById("vsp-p0-empty-wrap")) return;

    var wrap=el("div","vsp-empty-wrap","");
    wrap.id="vsp-p0-empty-wrap";
    wrap.appendChild(el("div","vsp-empty-title","KPI/Charts disabled by policy"));
    wrap.appendChild(el("div","vsp-empty-sub",
      "Dashboard is healthy, but KPI/Charts data is currently unavailable (degraded mode). " +
      (via?("Source: <code>"+via+"</code>."):"")
    ));

    var grid=el("div","vsp-kpi-grid","");
    var cards=[
      ["Overall","—"],
      ["Critical/High","—"],
      ["Coverage","—"],
      ["Last Run","—"]
    ];
    cards.forEach(function(x){
      var c=el("div","vsp-kpi-card","");
      c.appendChild(el("div","vsp-kpi-k",x[0]));
      c.appendChild(el("div","vsp-kpi-v",x[1]));
      grid.appendChild(c);
    });
    wrap.appendChild(grid);

    wrap.appendChild(el("div","vsp-chart-ph","No charts (policy / degraded)"));
    // put at top of main
    main.prepend(wrap);
  }

  async function init(){
    try{
      if (location.pathname !== "/vsp5") return;
      var main=findMain();
      if (!main) return;

      // retry a bit in case JS renders later
      var tries=0;
      while(!findMain() && tries<10){ await new Promise(r=>setTimeout(r,150)); tries++; }
      main=findMain(); if (!main) return;

      var k=await fetchJson("/api/vsp/dash_kpis");
      var c=await fetchJson("/api/vsp/dash_charts");
      var via=null;
      if (k && k.__via__) via=k.__via__;
      else if (c && c.__via__) via=c.__via__;

      // only render placeholders if empty objects
      if (k && isEmptyObj(k.kpis) && c && isEmptyObj(c.charts)){
        render(main, via);
      }
    }catch(e){}
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
"""
p.write_text(s + "\n\n" + textwrap.dedent(block).strip() + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check "$JS"
echo "[OK] node --check passed"

# bump cache
if [ -x "bin/p1_set_asset_v_runtime_ts_v1.sh" ]; then
  bash bin/p1_set_asset_v_runtime_ts_v1.sh || true
fi

# restart
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
fi

echo "[OK] Open /vsp5: should see KPI/Charts placeholder cards when KPI is empty."
