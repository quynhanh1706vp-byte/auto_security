#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need date

SET_JS="static/js/vsp_c_settings_v1.js"
OVR_JS="static/js/vsp_c_rule_overrides_v1.js"
VIEW_JS="static/js/vsp_json_viewer_v1.js"

[ -f "$SET_JS" ] || { echo "[ERR] missing $SET_JS"; exit 2; }
[ -f "$OVR_JS" ] || { echo "[ERR] missing $OVR_JS"; exit 2; }
[ -f "$VIEW_JS" ] || echo "[WARN] missing $VIEW_JS (will rely on loader)"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$SET_JS" "$SET_JS.bak_p404_${TS}"
cp -f "$OVR_JS" "$OVR_JS.bak_p404_${TS}"
echo "[OK] backups:"
echo " - $SET_JS.bak_p404_${TS}"
echo " - $OVR_JS.bak_p404_${TS}"

# ---------- SETTINGS P404 ----------
cat > "$SET_JS" <<'JS'
/* VSP_SETTINGS_P404 - fix blank page (never hide mount), render in visible root */
(function(){
  "use strict";
  const log=(...a)=>console.log("[settings:p404]",...a);
  const warn=(...a)=>console.warn("[settings:p404]",...a);

  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs) for(const [k,v] of Object.entries(attrs)){
      if(k==="class") e.className=v;
      else if(k==="style") e.setAttribute("style",v);
      else e.setAttribute(k,v);
    }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }

  function isHidden(node){
    if(!node) return true;
    const cs=getComputedStyle(node);
    if(cs.display==="none" || cs.visibility==="hidden") return true;
    // if in hidden ancestor chain
    let p=node;
    for(let i=0;i<12 && p; i++){
      const c=getComputedStyle(p);
      if(c.display==="none" || c.visibility==="hidden") return true;
      p=p.parentElement;
    }
    return false;
  }

  function findMount(){
    const cands=[
      document.querySelector("#vsp_tab_content"),
      document.querySelector("#content"),
      document.querySelector("main"),
      document.body
    ].filter(Boolean);
    for(const m of cands){
      if(!isHidden(m)) return m;
    }
    return document.body;
  }

  // IMPORTANT: only hide legacy blocks INSIDE mount, never hide mount/ancestors
  function hideLegacyInside(mount){
    if(!mount) return;
    const needles=[
      "Gate summary (live)",
      "Settings (live links",
      "Settings (live links + tool legend)",
      "Endpoint Probes"
    ];

    const nodes=Array.from(mount.querySelectorAll("section,article,div,pre"));
    for(const n of nodes){
      const t=(n.innerText||"").trim();
      if(!t) continue;
      if(!needles.some(x=>t.includes(x))) continue;

      // hide a card-like container but DO NOT cross outside mount
      let p=n;
      for(let i=0;i<10 && p && p!==mount; i++){
        const cls=(p.className||"").toString();
        const h=(p.getBoundingClientRect? p.getBoundingClientRect().height:0) || 0;
        if(cls.includes("card")||cls.includes("panel")||cls.includes("container")||h>=160) break;
        p=p.parentElement;
      }
      const target = (p===mount)? n : p;
      target.setAttribute("data-vsp-legacy-hidden","1");
      target.style.display="none";
    }
  }

  async function ensureViewerLoaded(){
    if(window.VSP && window.VSP.jsonViewer) return true;
    return await new Promise((resolve)=>{
      const s=document.createElement("script");
      s.src="/static/js/vsp_json_viewer_v1.js?v="+Date.now();
      s.onload=()=>resolve(true);
      s.onerror=()=>resolve(false);
      document.head.appendChild(s);
    });
  }

  async function fetchWithTimeout(url, timeoutMs){
    const ms=timeoutMs||4500;
    const ctl=new AbortController();
    const t=setTimeout(()=>ctl.abort(), ms);
    const t0=performance.now();
    try{
      const r=await fetch(url,{signal:ctl.signal,cache:"no-store",credentials:"same-origin"});
      const text=await r.text();
      let data=null; try{ data=JSON.parse(text);}catch(_){}
      return {ok:r.ok,status:r.status,ms:(performance.now()-t0),text,data};
    }catch(e){
      const name=(e&&e.name)?e.name:"Error";
      return {ok:false,status:0,ms:(performance.now()-t0),text:`${name}: ${String(e)}`,data:null};
    }finally{ clearTimeout(t); }
  }

  function cssOnce(){
    if(document.getElementById("vsp_settings_css_p404")) return;
    const css=`
      html,body{ background:#0b1020; }
      .vsp-p404-wrap{ padding:16px; color:#eaeaea; }
      .vsp-p404-h1{ font-size:18px; margin:0 0 12px 0; }
      .vsp-p404-grid{ display:grid; grid-template-columns: 1.1fr .9fr; gap:12px; }
      .vsp-p404-card{ border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.18); border-radius:14px; padding:12px; }
      .vsp-p404-card h2{ font-size:13px; margin:0 0 10px 0; opacity:.9; }
      .vsp-p404-table{ width:100%; border-collapse:collapse; font-size:12px; }
      .vsp-p404-table td,.vsp-p404-table th{ border-bottom:1px solid rgba(255,255,255,.08); padding:6px; text-align:left; }
      .vsp-p404-badge{ display:inline-block; padding:2px 8px; border-radius:999px; font-size:11px; border:1px solid rgba(255,255,255,.15); }
      .ok{ background:rgba(0,255,0,.08); } .bad{ background:rgba(255,0,0,.08); } .mid{ background:rgba(255,255,0,.08); }
      @media (max-width: 1100px){ .vsp-p404-grid{ grid-template-columns:1fr; } }
    `;
    document.head.appendChild(el("style",{id:"vsp_settings_css_p404"},css));
  }

  function badgeFor(status, ok){
    const cls= ok ? "ok" : (status===0 ? "mid" : (status>=500 ? "bad":"mid"));
    const label= ok ? "OK" : (status===0 ? "TIMEOUT/ABORT":"ERR");
    return `<span class="vsp-p404-badge ${cls}">${label} ${status}</span>`;
  }

  function probeUrls(){
    return [
      "/api/vsp/runs_v3?limit=5&include_ci=1",
      "/api/vsp/dashboard_kpis_v4",
      "/api/vsp/top_findings_v2?limit=5",
      "/api/vsp/trend_v1",
      "/api/vsp/exports_v1",
      "/api/vsp/run_status_v1",
    ];
  }

  async function main(){
    cssOnce();
    const mount=findMount();
    hideLegacyInside(mount);

    // Render into BODY if mount is not body but might be styled weird; we render into a safe visible container.
    const host = document.body;
    const root=el("div",{class:"vsp-p404-wrap"});
    root.appendChild(el("div",{class:"vsp-p404-h1"},"Settings • P404 (no-blank, legacy hidden safely)"));

    const grid=el("div",{class:"vsp-p404-grid"});
    const cardL=el("div",{class:"vsp-p404-card"});
    const cardR=el("div",{class:"vsp-p404-card"});
    cardL.appendChild(el("h2",null,"Endpoint probes"));
    cardR.appendChild(el("h2",null,"Raw JSON (stable collapsible)"));

    const table=el("table",{class:"vsp-p404-table"});
    table.innerHTML=`<thead><tr><th>Endpoint</th><th>Status</th><th>Time</th></tr></thead><tbody></tbody>`;
    const tbody=table.querySelector("tbody");
    cardL.appendChild(table);

    const jsonBox=el("div");
    cardR.appendChild(jsonBox);

    grid.appendChild(cardL);
    grid.appendChild(cardR);
    root.appendChild(grid);

    host.prepend(root);

    const urls=probeUrls();
    const results=[];
    for(const u of urls){
      const r=await fetchWithTimeout(u,4500);
      results.push({url:u,...r});
      const tr=document.createElement("tr");
      tr.innerHTML=`<td><code>${u}</code></td><td>${badgeFor(r.status,r.ok)}</td><td>${Math.round(r.ms)} ms</td>`;
      tbody.appendChild(tr);
    }

    const viewerOk=await ensureViewerLoaded();
    if(viewerOk && window.VSP && window.VSP.jsonViewer){
      window.VSP.jsonViewer.render(jsonBox,{
        tab:"settings",
        ts:new Date().toISOString(),
        probes: results.map(r=>({
          url:r.url, ok:r.ok, status:r.status, ms:Math.round(r.ms),
          data: (r.data!==null ? r.data : undefined),
          text: (r.data===null ? (r.text||"").slice(0,900) : undefined)
        }))
      },{title:"Settings.probes",maxDepth:7});
    } else {
      jsonBox.innerHTML=`<pre style="white-space:pre-wrap;word-break:break-word;opacity:.9;color:#eaeaea">${results.map(x=>x.text||"").join("\n\n")}</pre>`;
    }

    log("rendered");
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
JS

# ---------- RULE OVERRIDES P404 (hide legacy by pre-content signature) ----------
cat > "$OVR_JS" <<'JS'
/* VSP_RULE_OVERRIDES_P404 - hide legacy by signature, keep P403 panel */
(function(){
  "use strict";
  const log=(...a)=>console.log("[ovr:p404]",...a);

  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs) for(const [k,v] of Object.entries(attrs)){
      if(k==="class") e.className=v;
      else if(k==="style") e.setAttribute("style",v);
      else e.setAttribute(k,v);
    }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }

  function hideLegacyStrong(){
    const sig="VSP_RULE_OVERRIDES_EDITOR_P0_V1";
    const pres=Array.from(document.querySelectorAll("pre"));
    for(const pre of pres){
      const t=(pre.innerText||"");
      if(!t.includes(sig)) continue;

      // hide a reasonable container around that <pre>
      let p=pre;
      for(let i=0;i<12 && p && p!==document.body; i++){
        const cls=(p.className||"").toString();
        const h=(p.getBoundingClientRect? p.getBoundingClientRect().height:0) || 0;
        if(cls.includes("card")||cls.includes("panel")||cls.includes("container")||h>=180) break;
        p=p.parentElement;
      }
      (p||pre).setAttribute("data-vsp-legacy-hidden","1");
      (p||pre).style.display="none";
    }
  }

  function cssOnce(){
    if(document.getElementById("vsp_ovr_css_p404")) return;
    const css=`
      html,body{ background:#0b1020; }
      .ovr-p404{ padding:16px; color:#eaeaea; }
      .ovr-h1{ font-size:18px; margin:0 0 12px 0; }
      .ovr-grid{ display:grid; grid-template-columns: 1fr 1fr; gap:12px; }
      .ovr-card{ border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.18); border-radius:14px; padding:12px; min-height:120px; }
      .ovr-card h2{ font-size:13px; margin:0 0 10px 0; opacity:.9; }
      textarea.ovr-ta{ width:100%; min-height:240px; resize:vertical; border-radius:12px; padding:10px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.25); color:#eaeaea;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size:12px; line-height:1.4; }
      .ovr-msg{ margin-top:8px; font-size:12px; opacity:.8; }
      @media (max-width: 1100px){ .ovr-grid{ grid-template-columns:1fr; } }
    `;
    document.head.appendChild(el("style",{id:"vsp_ovr_css_p404"},css));
  }

  async function ensureViewerLoaded(){
    if(window.VSP && window.VSP.jsonViewer) return true;
    return await new Promise((resolve)=>{
      const s=document.createElement("script");
      s.src="/static/js/vsp_json_viewer_v1.js?v="+Date.now();
      s.onload=()=>resolve(true);
      s.onerror=()=>resolve(false);
      document.head.appendChild(s);
    });
  }

  async function fetchJson(url){
    try{
      const r=await fetch(url,{cache:"no-store",credentials:"same-origin"});
      const text=await r.text();
      let data=null; try{ data=JSON.parse(text);}catch(_){}
      return {ok:r.ok,status:r.status,text,data};
    }catch(e){
      return {ok:false,status:0,text:String(e),data:null};
    }
  }

  async function detectEndpoint(){
    const cands=["/api/vsp/rule_overrides_v1","/api/vsp/overrides_v1","/api/vsp/rule_overrides","/api/vsp/overrides"];
    for(const u of cands){
      const r=await fetchJson(u);
      if(r.ok && r.data!==null) return u;
    }
    return cands[0];
  }

  async function main(){
    cssOnce();
    hideLegacyStrong();

    const mount=document.body;
    const root=el("div",{class:"ovr-p404"});
    root.appendChild(el("div",{class:"ovr-h1"},"Rule Overrides • P404 (legacy hidden by signature)"));

    const grid=el("div",{class:"ovr-grid"});
    const left=el("div",{class:"ovr-card"});
    const right=el("div",{class:"ovr-card"});
    left.appendChild(el("h2",null,"Live view (stable JSON)"));
    right.appendChild(el("h2",null,"Editor (read-only safe)"));

    const jsonBox=el("div"); left.appendChild(jsonBox);
    const ta=el("textarea",{class:"ovr-ta",spellcheck:"false"}); right.appendChild(ta);
    const msg=el("div",{class:"ovr-msg"},""); right.appendChild(msg);

    grid.appendChild(left); grid.appendChild(right);
    root.appendChild(grid);
    mount.prepend(root);

    const endpoint=await detectEndpoint();
    const r=await fetchJson(endpoint);
    msg.textContent=`endpoint=${endpoint} status=${r.status}`;
    ta.value=r.data ? JSON.stringify(r.data,null,2) : (r.text||"");

    const viewerOk=await ensureViewerLoaded();
    if(viewerOk && window.VSP && window.VSP.jsonViewer){
      window.VSP.jsonViewer.render(jsonBox,{endpoint,payload:(r.data||{raw:r.text})},{title:"RuleOverrides",maxDepth:8});
    } else {
      jsonBox.innerHTML=`<pre style="white-space:pre-wrap;word-break:break-word;opacity:.9;color:#eaeaea">${(r.text||"").slice(0,3000)}</pre>`;
    }

    log("rendered");
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
JS

echo "== [CHECK] node --check =="
node --check "$SET_JS"
node --check "$OVR_JS"

echo ""
echo "[OK] P404 installed."
echo "[NEXT] Hard refresh Ctrl+Shift+R:"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
