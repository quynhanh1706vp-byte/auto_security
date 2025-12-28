#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need date; need ls; need head

TS="$(date +%Y%m%d_%H%M%S)"

# pick the REAL settings js used by UI
SET_JS=""
if [ -f static/js/vsp_c_settings_v1.js ]; then
  SET_JS="static/js/vsp_c_settings_v1.js"
elif [ -f static/js/settings_render.js ]; then
  SET_JS="static/js/settings_render.js"
else
  SET_JS="$(ls -1 static/js/*settings*.js 2>/dev/null | head -n1 || true)"
fi

OVR_JS=""
if [ -f static/js/vsp_c_rule_overrides_v1.js ]; then
  OVR_JS="static/js/vsp_c_rule_overrides_v1.js"
else
  OVR_JS="$(ls -1 static/js/*rule*over*.js 2>/dev/null | head -n1 || true)"
fi

VIEW_JS="static/js/vsp_json_viewer_v1.js"

[ -n "$SET_JS" ] || { echo "[ERR] cannot find settings js"; exit 2; }
[ -n "$OVR_JS" ] || { echo "[ERR] cannot find rule_overrides js"; exit 2; }

cp -f "$SET_JS" "$SET_JS.bak_p403_${TS}"
cp -f "$OVR_JS" "$OVR_JS.bak_p403_${TS}"
[ -f "$VIEW_JS" ] && cp -f "$VIEW_JS" "$VIEW_JS.bak_p403_${TS}" || true

echo "[OK] using:"
echo "  settings = $SET_JS"
echo "  overrides= $OVR_JS"
echo "  viewer   = $VIEW_JS"
echo "[OK] backups:"
echo "  - $SET_JS.bak_p403_${TS}"
echo "  - $OVR_JS.bak_p403_${TS}"
[ -f "$VIEW_JS.bak_p403_${TS}" ] && echo "  - $VIEW_JS.bak_p403_${TS}" || true

# keep viewer as-is if already present; but ensure file exists (some templates may not include it)
if [ ! -f "$VIEW_JS" ]; then
cat > "$VIEW_JS" <<'JS'
/* VSP_JSON_VIEWER_V1 (P401) - stable JSON panels */
(function(){
  "use strict";
  const NS = (window.VSP = window.VSP || {});
  if (NS.jsonViewer && NS.jsonViewer.__ver) return;

  function esc(s){
    return String(s)
      .replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;")
      .replaceAll('"',"&quot;").replaceAll("'","&#39;");
  }
  function el(tag, attrs, html){
    const e = document.createElement(tag);
    if (attrs) for (const [k,v] of Object.entries(attrs)) {
      if (k === "class") e.className = v;
      else if (k === "style") e.setAttribute("style", v);
      else e.setAttribute(k, v);
    }
    if (html !== undefined) e.innerHTML = html;
    return e;
  }
  function injectCssOnce(){
    if (document.getElementById("vsp_json_viewer_css_v1")) return;
    const css = `
      .vsp-jsonv-wrap{ border:1px solid rgba(255,255,255,.10); border-radius:12px; padding:10px; background:rgba(0,0,0,.20); }
      .vsp-jsonv-toolbar{ display:flex; gap:8px; align-items:center; margin:0 0 8px 0; flex-wrap:wrap; }
      .vsp-jsonv-btn{ cursor:pointer; border:1px solid rgba(255,255,255,.15); background:rgba(255,255,255,.06); color:#eaeaea; padding:6px 10px; border-radius:10px; font-size:12px; }
      .vsp-jsonv-btn:hover{ background:rgba(255,255,255,.10); }
      .vsp-jsonv-note{ opacity:.75; font-size:12px; }
      .vsp-jsonv-tree{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size:12px; line-height:1.45; }
      .vsp-jsonv-tree details{ margin:2px 0; padding-left:10px; border-left:1px dashed rgba(255,255,255,.10); }
      .vsp-jsonv-tree summary{ cursor:pointer; list-style:none; user-select:none; }
      .vsp-jsonv-tree summary::-webkit-details-marker{ display:none; }
      .vsp-jsonv-k{ color:#9ad; } .vsp-jsonv-t{ opacity:.7; }
      .vsp-jsonv-null{ color:#f99; } .vsp-jsonv-bool{ color:#9f9; }
      .vsp-jsonv-num{ color:#fd9; } .vsp-jsonv-str{ color:#9df; }
      .vsp-jsonv-small{ opacity:.75; font-size:11px; }
    `;
    document.head.appendChild(el("style",{id:"vsp_json_viewer_css_v1"},css));
  }
  function renderValue(key, value, depth, maxDepth){
    const k = (key === null ? "" : `<span class="vsp-jsonv-k">${esc(key)}</span>: `);
    if (value === null) return el("div",null,`${k}<span class="vsp-jsonv-null">null</span>`);
    if (typeof value === "boolean") return el("div",null,`${k}<span class="vsp-jsonv-bool">${value}</span>`);
    if (typeof value === "number") return el("div",null,`${k}<span class="vsp-jsonv-num">${value}</span>`);
    if (typeof value === "string") return el("div",null,`${k}<span class="vsp-jsonv-str">"${esc(value)}"</span>`);
    if (typeof value !== "object") return el("div",null,`${k}${esc(String(value))}`);

    const isArr = Array.isArray(value);
    const len = isArr ? value.length : Object.keys(value).length;
    const typeTag = isArr ? `array(${len})` : `object(${len})`;
    const d = el("details");
    if (depth === 0) d.open = true;
    d.appendChild(el("summary",null,`${k}<span class="vsp-jsonv-t">${typeTag}</span> <span class="vsp-jsonv-small">(depth ${depth})</span>`));
    if (depth >= maxDepth) { d.appendChild(el("div",{class:"vsp-jsonv-small"},`… truncated maxDepth=${maxDepth}`)); return d; }
    const container = el("div");
    if (isArr) for (let i=0;i<value.length;i++) container.appendChild(renderValue(String(i), value[i], depth+1, maxDepth));
    else {
      const keys = Object.keys(value); keys.sort();
      for (const kk of keys) container.appendChild(renderValue(kk, value[kk], depth+1, maxDepth));
    }
    d.appendChild(container);
    return d;
  }
  function setAllDetailsOpen(root, open){ root.querySelectorAll("details").forEach(d=>d.open=!!open); }

  function render(targetEl, data, opts){
    injectCssOnce();
    const maxDepth = Math.max(1, Math.min(10, (opts && opts.maxDepth) ? opts.maxDepth : 6));
    const title = (opts && opts.title) ? String(opts.title) : "JSON";
    const wrap = el("div",{class:"vsp-jsonv-wrap"});
    const tb = el("div",{class:"vsp-jsonv-toolbar"});
    const bOpen = el("button",{class:"vsp-jsonv-btn",type:"button"},"Expand all");
    const bClose = el("button",{class:"vsp-jsonv-btn",type:"button"},"Collapse all");
    const note = el("span",{class:"vsp-jsonv-note"},`${title} • stable collapsible • maxDepth=${maxDepth}`);
    tb.appendChild(bOpen); tb.appendChild(bClose); tb.appendChild(note);

    const tree = el("div",{class:"vsp-jsonv-tree"});
    tree.appendChild(renderValue(null, data, 0, maxDepth));
    bOpen.addEventListener("click", ()=>setAllDetailsOpen(tree,true));
    bClose.addEventListener("click", ()=>setAllDetailsOpen(tree,false));

    wrap.appendChild(tb); wrap.appendChild(tree);
    targetEl.innerHTML=""; targetEl.appendChild(wrap);
  }
  NS.jsonViewer = { __ver:"V1_P401", render };
})();
JS
fi

# P403 Settings (replace the REAL settings JS)
cat > "$SET_JS" <<'JS'
/* VSP_SETTINGS_P403 - replace legacy settings, avoid AbortError, hide legacy blocks */
(function(){
  "use strict";
  const log = (...a)=>console.log("[settings:p403]", ...a);
  const warn = (...a)=>console.warn("[settings:p403]", ...a);

  function el(tag, attrs, html){
    const e = document.createElement(tag);
    if (attrs) for (const [k,v] of Object.entries(attrs)) {
      if (k === "class") e.className = v;
      else if (k === "style") e.setAttribute("style", v);
      else e.setAttribute(k, v);
    }
    if (html !== undefined) e.innerHTML = html;
    return e;
  }

  // stronger legacy hide: hide any big block that contains certain headings/phrases
  function hideLegacy(){
    const needles = [
      "Gate summary (live)",
      "Settings (live links",
      "Settings (live links + tool legend)",
      "Endpoint Probes",
      "Tools (8):",
      "Exports:",
      "VSP Commercial Data (LIVE)"
    ];
    const body = document.body;
    if (!body) return;

    const candidates = Array.from(body.querySelectorAll("section,article,div,main"));
    for (const n of candidates){
      const t = (n.innerText || "").trim();
      if (!t) continue;
      if (!needles.some(x => t.includes(x))) continue;

      // climb to a "card-like" container
      let p = n;
      for (let i=0;i<14 && p && p !== body; i++){
        const cls = (p.className || "").toString();
        const h = (p.getBoundingClientRect && p.getBoundingClientRect().height) ? p.getBoundingClientRect().height : 0;
        if (cls.includes("card") || cls.includes("panel") || cls.includes("container") || h >= 160) break;
        p = p.parentElement;
      }
      (p || n).setAttribute("data-vsp-legacy-hidden","1");
      (p || n).style.display="none";
    }
  }

  function findMount(){
    return document.querySelector("#vsp_tab_content")
      || document.querySelector("#content")
      || document.querySelector("main")
      || document.body;
  }

  async function ensureViewerLoaded(){
    if (window.VSP && window.VSP.jsonViewer) return true;
    return await new Promise((resolve)=>{
      const s = document.createElement("script");
      s.src = "/static/js/vsp_json_viewer_v1.js?v=" + Date.now();
      s.onload = ()=>resolve(true);
      s.onerror = ()=>resolve(false);
      document.head.appendChild(s);
    });
  }

  async function fetchWithTimeout(url, timeoutMs){
    const ms = timeoutMs || 4500;
    const ctl = new AbortController();
    const t = setTimeout(()=>ctl.abort(), ms);
    const t0 = performance.now();
    try{
      const r = await fetch(url, { signal: ctl.signal, cache:"no-store", credentials:"same-origin" });
      const text = await r.text();
      let data = null;
      try{ data = JSON.parse(text); }catch(_){}
      return { ok:r.ok, status:r.status, ms:(performance.now()-t0), text, data };
    }catch(e){
      // IMPORTANT: never throw AbortError to console; return a synthetic result instead
      const name = (e && e.name) ? e.name : "Error";
      return { ok:false, status:0, ms:(performance.now()-t0), text:`${name}: ${String(e)}`, data:null };
    }finally{
      clearTimeout(t);
    }
  }

  function cssOnce(){
    if (document.getElementById("vsp_settings_css_p403")) return;
    const css = `
      .vsp-p403-wrap{ padding:16px; }
      .vsp-p403-h1{ font-size:18px; margin:0 0 12px 0; }
      .vsp-p403-grid{ display:grid; grid-template-columns: 1.1fr .9fr; gap:12px; }
      .vsp-p403-card{ border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.18); border-radius:14px; padding:12px; }
      .vsp-p403-card h2{ font-size:13px; margin:0 0 10px 0; opacity:.9; }
      .vsp-p403-table{ width:100%; border-collapse:collapse; font-size:12px; }
      .vsp-p403-table td,.vsp-p403-table th{ border-bottom:1px solid rgba(255,255,255,.08); padding:6px 6px; text-align:left; }
      .vsp-p403-badge{ display:inline-block; padding:2px 8px; border-radius:999px; font-size:11px; border:1px solid rgba(255,255,255,.15); }
      .ok{ background:rgba(0,255,0,.08); }
      .bad{ background:rgba(255,0,0,.08); }
      .mid{ background:rgba(255,255,0,.08); }
      .muted{ opacity:.75; }
      @media (max-width: 1100px){ .vsp-p403-grid{ grid-template-columns:1fr; } }
    `;
    document.head.appendChild(el("style",{id:"vsp_settings_css_p403"},css));
  }

  function badgeFor(status, ok){
    const cls = ok ? "ok" : (status===0 ? "mid" : (status>=500 ? "bad" : "mid"));
    const label = ok ? "OK" : (status===0 ? "TIMEOUT/ABORT" : "ERR");
    return `<span class="vsp-p403-badge ${cls}">${label} ${status}</span>`;
  }

  function candidateProbeUrls(){
    const env = (window.VSP_SETTINGS_PROBES || "").trim();
    if (env) return env.split(",").map(s=>s.trim()).filter(Boolean);
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
    hideLegacy();      // hide legacy UI first
    cssOnce();

    const mount = findMount();
    if (!mount) return;

    const root = el("div",{class:"vsp-p403-wrap"});
    root.appendChild(el("div",{class:"vsp-p403-h1"}, "Settings • P403 (legacy replaced + AbortError safe)"));

    const grid = el("div",{class:"vsp-p403-grid"});
    const cardProbes = el("div",{class:"vsp-p403-card"});
    const cardJson   = el("div",{class:"vsp-p403-card"});

    cardProbes.appendChild(el("h2",null,"Endpoint probes"));
    const table = el("table",{class:"vsp-p403-table"});
    table.innerHTML = `<thead><tr><th>Endpoint</th><th>Status</th><th>Time</th></tr></thead><tbody></tbody>`;
    const tbody = table.querySelector("tbody");
    cardProbes.appendChild(table);
    cardProbes.appendChild(el("div",{class:"muted",style:"margin-top:8px;font-size:12px;"},
      "Hard refresh Ctrl+Shift+R. No more AbortError spam."
    ));

    cardJson.appendChild(el("h2",null,"Raw JSON (stable collapsible)"));
    const jsonBox = el("div");
    cardJson.appendChild(jsonBox);

    grid.appendChild(cardProbes);
    grid.appendChild(cardJson);
    root.appendChild(grid);

    mount.prepend(root);

    const urls = candidateProbeUrls();
    const results = [];
    for (const u of urls){
      const r = await fetchWithTimeout(u, 4500);
      results.push({ url:u, ...r });
      const tr = document.createElement("tr");
      tr.innerHTML =
        `<td><code>${u}</code></td>
         <td>${badgeFor(r.status, r.ok)}</td>
         <td>${Math.round(r.ms)} ms</td>`;
      tbody.appendChild(tr);
    }

    const viewerOk = await ensureViewerLoaded();
    if (viewerOk && window.VSP && window.VSP.jsonViewer){
      window.VSP.jsonViewer.render(jsonBox, {
        tab:"settings",
        ts: new Date().toISOString(),
        path: location.pathname,
        probes: results.map(r=>({
          url:r.url, ok:r.ok, status:r.status, ms:Math.round(r.ms),
          data: (r.data !== null ? r.data : undefined),
          text: (r.data === null ? (r.text||"").slice(0, 1000) : undefined),
        }))
      }, { title:"Settings.probes", maxDepth: 7 });
    } else {
      jsonBox.innerHTML = `<pre style="white-space:pre-wrap;word-break:break-word;opacity:.9">${results.map(x=>x.text||"").join("\n\n")}</pre>`;
    }

    log("rendered");
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
JS

# P403 Rule overrides: only harden legacy hide (keep your P402 behavior)
cat > "$OVR_JS" <<'JS'
/* VSP_RULE_OVERRIDES_P403 - harden legacy hide */
(function(){
  "use strict";
  const log = (...a)=>console.log("[ovr:p403]", ...a);

  function el(tag, attrs, html){
    const e = document.createElement(tag);
    if (attrs) for (const [k,v] of Object.entries(attrs)) {
      if (k === "class") e.className = v;
      else if (k === "style") e.setAttribute("style", v);
      else e.setAttribute(k, v);
    }
    if (html !== undefined) e.innerHTML = html;
    return e;
  }

  function hideLegacy(){
    const needles = [
      "Rule Overrides (live from",
      "VSP_RULE_OVERRIDES_EDITOR_P0_V1",
      "/api/vsp/rule_overrides",
      "Open JSON",
      "Open  JSON"
    ];
    const body = document.body;
    if (!body) return;
    const candidates = Array.from(body.querySelectorAll("section,article,div,main,pre"));
    for (const n of candidates){
      const t = (n.innerText || "").trim();
      if (!t) continue;
      if (!needles.some(x => t.includes(x))) continue;

      let p = n;
      for (let i=0;i<16 && p && p !== body; i++){
        const cls = (p.className || "").toString();
        const h = (p.getBoundingClientRect && p.getBoundingClientRect().height) ? p.getBoundingClientRect().height : 0;
        if (cls.includes("card") || cls.includes("panel") || cls.includes("container") || h >= 160) break;
        p = p.parentElement;
      }
      (p || n).setAttribute("data-vsp-legacy-hidden","1");
      (p || n).style.display="none";
    }
  }

  function cssOnce(){
    if (document.getElementById("vsp_ovr_css_p403")) return;
    const css = `
      .ovr-p403{ padding:16px; }
      .ovr-h1{ font-size:18px; margin:0 0 12px 0; }
      .ovr-grid{ display:grid; grid-template-columns: 1fr 1fr; gap:12px; }
      .ovr-card{ border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.18); border-radius:14px; padding:12px; min-height:120px; }
      .ovr-card h2{ font-size:13px; margin:0 0 10px 0; opacity:.9; }
      .ovr-row{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin:0 0 10px 0; }
      .ovr-btn{ cursor:pointer; border:1px solid rgba(255,255,255,.15); background:rgba(255,255,255,.06); color:#eaeaea; padding:6px 10px; border-radius:10px; font-size:12px; }
      textarea.ovr-ta{ width:100%; min-height:240px; resize:vertical; border-radius:12px; padding:10px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.25); color:#eaeaea; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size:12px; line-height:1.4; }
      .ovr-msg{ margin-top:8px; font-size:12px; opacity:.8; }
      @media (max-width: 1100px){ .ovr-grid{ grid-template-columns:1fr; } }
    `;
    document.head.appendChild(el("style",{id:"vsp_ovr_css_p403"},css));
  }

  function findMount(){
    return document.querySelector("#vsp_tab_content")
      || document.querySelector("#content")
      || document.querySelector("main")
      || document.body;
  }

  async function ensureViewerLoaded(){
    if (window.VSP && window.VSP.jsonViewer) return true;
    return await new Promise((resolve)=>{
      const s = document.createElement("script");
      s.src = "/static/js/vsp_json_viewer_v1.js?v=" + Date.now();
      s.onload = ()=>resolve(true);
      s.onerror = ()=>resolve(false);
      document.head.appendChild(s);
    });
  }

  async function fetchJson(url){
    try{
      const r = await fetch(url, { cache:"no-store", credentials:"same-origin" });
      const text = await r.text();
      let data=null; try{ data=JSON.parse(text); }catch(_){}
      return { ok:r.ok, status:r.status, text, data };
    }catch(e){
      return { ok:false, status:0, text:String(e), data:null };
    }
  }

  async function detectEndpoint(){
    const fixed = (window.VSP_OVR_ENDPOINT || "").trim();
    if (fixed) return fixed;
    const cands = ["/api/vsp/rule_overrides_v1","/api/vsp/overrides_v1","/api/vsp/rule_overrides","/api/vsp/overrides"];
    for (const u of cands){
      const r = await fetchJson(u);
      if (r.ok && r.data !== null) return u;
    }
    return cands[0];
  }

  async function main(){
    hideLegacy();
    cssOnce();
    const mount = findMount();

    const root = el("div",{class:"ovr-p403"});
    root.appendChild(el("div",{class:"ovr-h1"},"Rule Overrides • P403 (legacy hidden harder)"));

    const grid = el("div",{class:"ovr-grid"});
    const left = el("div",{class:"ovr-card"});
    const right = el("div",{class:"ovr-card"});
    left.appendChild(el("h2",null,"Live view (stable JSON)"));
    right.appendChild(el("h2",null,"Editor (read-only safe)"));

    const jsonBox = el("div"); left.appendChild(jsonBox);
    const ta = el("textarea",{class:"ovr-ta",spellcheck:"false"}); right.appendChild(ta);
    const msg = el("div",{class:"ovr-msg"},""); right.appendChild(msg);

    grid.appendChild(left); grid.appendChild(right);
    root.appendChild(grid);
    mount.prepend(root);

    const endpoint = await detectEndpoint();
    const r = await fetchJson(endpoint);
    msg.textContent = `endpoint=${endpoint} status=${r.status}`;
    ta.value = r.data ? JSON.stringify(r.data, null, 2) : (r.text || "");

    const viewerOk = await ensureViewerLoaded();
    if (viewerOk && window.VSP && window.VSP.jsonViewer){
      window.VSP.jsonViewer.render(jsonBox, { endpoint, payload: (r.data||{raw:r.text}) }, { title:"RuleOverrides", maxDepth: 8 });
    } else {
      jsonBox.innerHTML = `<pre style="white-space:pre-wrap;word-break:break-word;opacity:.9">${(r.text||"").slice(0,3000)}</pre>`;
    }

    log("rendered");
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
JS

echo "== [CHECK] node --check =="
node --check "$SET_JS"
node --check "$OVR_JS"

echo ""
echo "[OK] P403 installed."
echo "[NEXT] Hard refresh Ctrl+Shift+R:"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
