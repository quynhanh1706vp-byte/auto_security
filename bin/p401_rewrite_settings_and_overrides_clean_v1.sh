#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need ls; need grep

SET_JS="static/js/settings_render.js"
OVR_JS="static/js/vsp_c_rule_overrides_v1.js"
VIEW_JS="static/js/vsp_json_viewer_v1.js"

[ -f "$SET_JS" ] || { echo "[ERR] missing $SET_JS"; exit 2; }
[ -f "$OVR_JS" ] || { echo "[ERR] missing $OVR_JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
bk(){ cp -f "$1" "$1.bak_p401_${TS}"; echo "[OK] backup: $1.bak_p401_${TS}"; }

bk "$SET_JS"
bk "$OVR_JS"
[ -f "$VIEW_JS" ] && bk "$VIEW_JS" || true

cat > "$VIEW_JS" <<'JS'
/* VSP_JSON_VIEWER_V1 (P401) - stable JSON panels (no observer), predictable 100% */
(function(){
  "use strict";
  const NS = (window.VSP = window.VSP || {});

  if (NS.jsonViewer && NS.jsonViewer.__ver === "V1_P401") return;

  function esc(s){
    return String(s)
      .replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;")
      .replaceAll('"',"&quot;").replaceAll("'","&#39;");
  }
  function isObj(x){ return x && typeof x === "object" && !Array.isArray(x); }
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
      .vsp-jsonv-tree details{ margin:2px 0 2px 0; padding-left:10px; border-left:1px dashed rgba(255,255,255,.10); }
      .vsp-jsonv-tree summary{ cursor:pointer; list-style:none; user-select:none; }
      .vsp-jsonv-tree summary::-webkit-details-marker{ display:none; }
      .vsp-jsonv-k{ color:#9ad; }
      .vsp-jsonv-t{ opacity:.7; }
      .vsp-jsonv-v{ color:#ddd; }
      .vsp-jsonv-null{ color:#f99; }
      .vsp-jsonv-bool{ color:#9f9; }
      .vsp-jsonv-num{ color:#fd9; }
      .vsp-jsonv-str{ color:#9df; }
      .vsp-jsonv-small{ opacity:.75; font-size:11px; }
    `;
    const st = el("style", { id:"vsp_json_viewer_css_v1" }, css);
    document.head.appendChild(st);
  }

  function renderValue(key, value, depth, maxDepth){
    const k = (key === null ? "" : `<span class="vsp-jsonv-k">${esc(key)}</span>: `);

    if (value === null) return el("div", null, `${k}<span class="vsp-jsonv-null">null</span>`);
    if (typeof value === "boolean") return el("div", null, `${k}<span class="vsp-jsonv-bool">${value}</span>`);
    if (typeof value === "number") return el("div", null, `${k}<span class="vsp-jsonv-num">${value}</span>`);
    if (typeof value === "string") return el("div", null, `${k}<span class="vsp-jsonv-str">"${esc(value)}"</span>`);
    if (typeof value !== "object") return el("div", null, `${k}<span class="vsp-jsonv-v">${esc(String(value))}</span>`);

    const isArr = Array.isArray(value);
    const len = isArr ? value.length : Object.keys(value).length;
    const typeTag = isArr ? `array(${len})` : `object(${len})`;

    const d = el("details", { class:"vsp-jsonv-node" });
    if (depth === 0) d.open = true;

    const summary = el("summary", null,
      `${k}<span class="vsp-jsonv-t">${typeTag}</span> <span class="vsp-jsonv-small">(depth ${depth})</span>`
    );
    d.appendChild(summary);

    if (depth >= maxDepth) {
      d.appendChild(el("div", { class:"vsp-jsonv-small" }, `… truncated at maxDepth=${maxDepth}`));
      return d;
    }

    const container = el("div");
    if (isArr) {
      for (let i=0;i<value.length;i++){
        container.appendChild(renderValue(String(i), value[i], depth+1, maxDepth));
      }
    } else {
      const keys = Object.keys(value);
      keys.sort();
      for (const kk of keys){
        container.appendChild(renderValue(kk, value[kk], depth+1, maxDepth));
      }
    }
    d.appendChild(container);
    return d;
  }

  function setAllDetailsOpen(root, open){
    root.querySelectorAll("details").forEach(d => { d.open = !!open; });
  }

  function render(targetEl, data, opts){
    injectCssOnce();
    const maxDepth = Math.max(1, Math.min(10, (opts && opts.maxDepth) ? opts.maxDepth : 6));
    const title = (opts && opts.title) ? String(opts.title) : "JSON";

    const wrap = el("div", { class:"vsp-jsonv-wrap" });
    const tb = el("div", { class:"vsp-jsonv-toolbar" });
    const bOpen = el("button", { class:"vsp-jsonv-btn", type:"button" }, "Expand all");
    const bClose = el("button", { class:"vsp-jsonv-btn", type:"button" }, "Collapse all");
    const note = el("span", { class:"vsp-jsonv-note" }, `${title} • stable collapsible • maxDepth=${maxDepth}`);
    tb.appendChild(bOpen); tb.appendChild(bClose); tb.appendChild(note);

    const tree = el("div", { class:"vsp-jsonv-tree" });
    tree.appendChild(renderValue(null, data, 0, maxDepth));

    bOpen.addEventListener("click", () => setAllDetailsOpen(tree, true));
    bClose.addEventListener("click", () => setAllDetailsOpen(tree, false));

    wrap.appendChild(tb);
    wrap.appendChild(tree);

    targetEl.innerHTML = "";
    targetEl.appendChild(wrap);
  }

  NS.jsonViewer = { __ver:"V1_P401", render };
})();
JS

cat > "$SET_JS" <<'JS'
/* VSP_SETTINGS_REWRITE_P401 - clean & stable (no observer) */
(function(){
  "use strict";
  const log = (...a)=>console.log("[settings:p401]", ...a);
  const warn = (...a)=>console.warn("[settings:p401]", ...a);

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

  function findMount(){
    return document.querySelector("#vsp_tab_content")
      || document.querySelector("#content")
      || document.querySelector("main")
      || document.body;
  }

  async function fetchWithTimeout(url, opts){
    const ms = (opts && opts.timeoutMs) ? opts.timeoutMs : 4500;
    const ctl = new AbortController();
    const t = setTimeout(()=>ctl.abort(), ms);
    const t0 = performance.now();
    try{
      const r = await fetch(url, { signal: ctl.signal, cache:"no-store", credentials:"same-origin" });
      const text = await r.text();
      let data = null;
      try{ data = JSON.parse(text); }catch(_){}
      return { ok:r.ok, status:r.status, ms:(performance.now()-t0), text, data };
    }finally{ clearTimeout(t); }
  }

  function candidateProbeUrls(){
    // optional override: export VSP_SETTINGS_PROBES="/api/vsp/health,/api/vsp/top_findings_v2"
    const env = (window.VSP_SETTINGS_PROBES || "").trim();
    if (env) return env.split(",").map(s=>s.trim()).filter(Boolean);

    return [
      "/api/vsp/health",
      "/api/vsp/healthz",
      "/api/vsp/probes_v1",
      "/api/vsp/top_findings_v2?limit=5",
      "/api/vsp/runs_v3?limit=5&include_ci=1",
      "/api/vsp/datasource_v3?limit=5",
      "/api/vsp/exports_v1",
      "/api/vsp/run_status_v1",
    ];
  }

  function cssOnce(){
    if (document.getElementById("vsp_settings_css_p401")) return;
    const css = `
      .vsp-p401-wrap{ padding:16px; }
      .vsp-p401-h1{ font-size:18px; margin:0 0 12px 0; }
      .vsp-p401-grid{ display:grid; grid-template-columns: 1.1fr .9fr; gap:12px; }
      .vsp-p401-card{ border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.18); border-radius:14px; padding:12px; }
      .vsp-p401-card h2{ font-size:13px; margin:0 0 10px 0; opacity:.9; }
      .vsp-p401-table{ width:100%; border-collapse:collapse; font-size:12px; }
      .vsp-p401-table td,.vsp-p401-table th{ border-bottom:1px solid rgba(255,255,255,.08); padding:6px 6px; text-align:left; }
      .vsp-p401-badge{ display:inline-block; padding:2px 8px; border-radius:999px; font-size:11px; border:1px solid rgba(255,255,255,.15); }
      .ok{ background:rgba(0,255,0,.08); }
      .bad{ background:rgba(255,0,0,.08); }
      .mid{ background:rgba(255,255,0,.08); }
      .muted{ opacity:.75; }
      @media (max-width: 1100px){ .vsp-p401-grid{ grid-template-columns:1fr; } }
    `;
    const st = el("style",{id:"vsp_settings_css_p401"},css);
    document.head.appendChild(st);
  }

  function badgeFor(status, ok){
    const cls = ok ? "ok" : (status>=500 ? "bad" : "mid");
    return `<span class="vsp-p401-badge ${cls}">${ok ? "OK" : "ERR"} ${status}</span>`;
  }

  async function ensureViewerLoaded(){
    if (window.VSP && window.VSP.jsonViewer) return true;
    // viewer is a static file; should already be included by template, but if not, inject it
    return await new Promise((resolve)=>{
      const s = document.createElement("script");
      s.src = "/static/js/vsp_json_viewer_v1.js?v=" + Date.now();
      s.onload = ()=>resolve(true);
      s.onerror = ()=>resolve(false);
      document.head.appendChild(s);
    });
  }

  async function main(){
    cssOnce();
    const mount = findMount();

    const root = el("div",{class:"vsp-p401-wrap"});
    root.appendChild(el("div",{class:"vsp-p401-h1"}, "Settings (Commercial) • P401 rewrite"));

    const grid = el("div",{class:"vsp-p401-grid"});
    const cardProbes = el("div",{class:"vsp-p401-card"});
    const cardJson   = el("div",{class:"vsp-p401-card"});

    cardProbes.appendChild(el("h2",null,"Endpoint probes"));
    const table = el("table",{class:"vsp-p401-table"});
    table.innerHTML = `<thead><tr><th>Endpoint</th><th>Status</th><th>Time</th></tr></thead><tbody></tbody>`;
    const tbody = table.querySelector("tbody");
    cardProbes.appendChild(table);
    cardProbes.appendChild(el("div",{class:"muted",style:"margin-top:8px;font-size:12px;"},
      "Tip: hard refresh Ctrl+Shift+R if JS cached."
    ));

    cardJson.appendChild(el("h2",null,"Raw JSON (stable collapsible)"));
    const jsonBox = el("div");
    cardJson.appendChild(jsonBox);

    grid.appendChild(cardProbes);
    grid.appendChild(cardJson);
    root.appendChild(grid);

    // Replace only if we detect this is the settings tab area; otherwise append on top
    mount.innerHTML = "";
    mount.appendChild(root);

    const urls = candidateProbeUrls();
    const results = [];
    for (const u of urls){
      const r = await fetchWithTimeout(u, { timeoutMs: 4500 });
      results.push({ url:u, ...r });
      const tr = document.createElement("tr");
      tr.innerHTML =
        `<td><code>${u}</code></td>
         <td>${badgeFor(r.status, r.ok)}</td>
         <td>${Math.round(r.ms)} ms</td>`;
      tbody.appendChild(tr);
    }

    const viewerOk = await ensureViewerLoaded();
    if (!viewerOk || !(window.VSP && window.VSP.jsonViewer)) {
      warn("jsonViewer missing; fallback to <pre>");
      jsonBox.innerHTML = `<pre style="white-space:pre-wrap;word-break:break-word;opacity:.9">${results.map(x=>x.text||"").join("\n\n")}</pre>`;
      return;
    }

    window.VSP.jsonViewer.render(jsonBox, {
      tab:"settings",
      ts: new Date().toISOString(),
      origin: location.origin,
      path: location.pathname,
      probes: results.map(r=>({
        url:r.url, ok:r.ok, status:r.status, ms:Math.round(r.ms),
        data: (r.data !== null ? r.data : undefined),
        text: (r.data === null ? (r.text||"").slice(0, 1200) : undefined),
      }))
    }, { title:"Settings.probes", maxDepth: 7 });

    log("rendered");
  }

  // run when DOM ready
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
JS

cat > "$OVR_JS" <<'JS'
/* VSP_RULE_OVERRIDES_REWRITE_P401 - clean & stable (no observer) */
(function(){
  "use strict";
  const log = (...a)=>console.log("[ovr:p401]", ...a);
  const warn = (...a)=>console.warn("[ovr:p401]", ...a);

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

  function cssOnce(){
    if (document.getElementById("vsp_ovr_css_p401")) return;
    const css = `
      .ovr-p401{ padding:16px; }
      .ovr-h1{ font-size:18px; margin:0 0 12px 0; }
      .ovr-grid{ display:grid; grid-template-columns: 1fr 1fr; gap:12px; }
      .ovr-card{ border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.18); border-radius:14px; padding:12px; min-height:120px; }
      .ovr-card h2{ font-size:13px; margin:0 0 10px 0; opacity:.9; }
      .ovr-row{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin:0 0 10px 0; }
      .ovr-btn{ cursor:pointer; border:1px solid rgba(255,255,255,.15); background:rgba(255,255,255,.06); color:#eaeaea; padding:6px 10px; border-radius:10px; font-size:12px; }
      .ovr-btn:hover{ background:rgba(255,255,255,.10); }
      .ovr-badge{ display:inline-block; padding:2px 8px; border-radius:999px; font-size:11px; border:1px solid rgba(255,255,255,.15); }
      .ok{ background:rgba(0,255,0,.08); }
      .bad{ background:rgba(255,0,0,.08); }
      textarea.ovr-ta{ width:100%; min-height:240px; resize:vertical; border-radius:12px; padding:10px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.25); color:#eaeaea; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size:12px; line-height:1.4; }
      .ovr-msg{ margin-top:8px; font-size:12px; opacity:.8; }
      @media (max-width: 1100px){ .ovr-grid{ grid-template-columns:1fr; } }
    `;
    document.head.appendChild(el("style",{id:"vsp_ovr_css_p401"},css));
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

  async function fetchJson(url, opts){
    const ms = (opts && opts.timeoutMs) ? opts.timeoutMs : 4500;
    const method = (opts && opts.method) ? opts.method : "GET";
    const body = (opts && opts.body) ? opts.body : null;

    const ctl = new AbortController();
    const t = setTimeout(()=>ctl.abort(), ms);
    const t0 = performance.now();
    try{
      const r = await fetch(url, {
        method,
        cache:"no-store",
        credentials:"same-origin",
        headers: body ? { "Content-Type":"application/json" } : undefined,
        body: body ? JSON.stringify(body) : undefined,
        signal: ctl.signal
      });
      const text = await r.text();
      let data = null;
      try{ data = JSON.parse(text); }catch(_){}
      return { ok:r.ok, status:r.status, ms:(performance.now()-t0), text, data };
    }finally{ clearTimeout(t); }
  }

  async function detectEndpoint(){
    // optional override: window.VSP_OVR_ENDPOINT="/api/vsp/rule_overrides_v1"
    const fixed = (window.VSP_OVR_ENDPOINT || "").trim();
    if (fixed) return fixed;

    const cands = [
      "/api/vsp/rule_overrides_v1",
      "/api/vsp/overrides_v1",
      "/api/vsp/rule_overrides",
      "/api/vsp/overrides",
    ];

    for (const u of cands){
      const r = await fetchJson(u, { timeoutMs: 3500 });
      if (r.ok && r.data !== null) return u;
    }
    return cands[0]; // default
  }

  function badge(ok){
    return `<span class="ovr-badge ${ok ? "ok":"bad"}">${ok ? "OK":"ERR"}</span>`;
  }

  async function main(){
    cssOnce();
    const mount = findMount();

    const root = el("div",{class:"ovr-p401"});
    root.appendChild(el("div",{class:"ovr-h1"}, "Rule Overrides • P401 rewrite"));

    const grid = el("div",{class:"ovr-grid"});
    const cardLeft = el("div",{class:"ovr-card"});
    const cardRight = el("div",{class:"ovr-card"});

    cardLeft.appendChild(el("h2",null,"Live view (stable JSON)"));
    const jsonBox = el("div");
    cardLeft.appendChild(jsonBox);

    cardRight.appendChild(el("h2",null,"Editor (validate + save if backend supports POST)"));
    const row = el("div",{class:"ovr-row"});
    const btnReload = el("button",{class:"ovr-btn",type:"button"},"Reload");
    const btnValidate = el("button",{class:"ovr-btn",type:"button"},"Validate JSON");
    const btnSave = el("button",{class:"ovr-btn",type:"button"},"Save");
    const epSpan = el("span",{class:"ovr-msg"},"");
    row.appendChild(btnReload); row.appendChild(btnValidate); row.appendChild(btnSave); row.appendChild(epSpan);

    const ta = el("textarea",{class:"ovr-ta",spellcheck:"false"});
    const msg = el("div",{class:"ovr-msg"},"");

    cardRight.appendChild(row);
    cardRight.appendChild(ta);
    cardRight.appendChild(msg);

    grid.appendChild(cardLeft);
    grid.appendChild(cardRight);
    root.appendChild(grid);

    mount.innerHTML = "";
    mount.appendChild(root);

    const viewerOk = await ensureViewerLoaded();
    const endpoint = await detectEndpoint();
    epSpan.innerHTML = `endpoint: <code>${endpoint}</code>`;

    async function reload(){
      msg.textContent = "Loading…";
      const r = await fetchJson(endpoint, { timeoutMs: 4500 });
      msg.innerHTML = `${badge(r.ok)} status=${r.status} • ${Math.round(r.ms)}ms`;
      const payload = (r.data !== null) ? r.data : { error:"non-json response", status:r.status, text:(r.text||"").slice(0,1600) };

      // populate editor with pretty JSON
      try{ ta.value = JSON.stringify(payload, null, 2); }catch(_){ ta.value = String(r.text||""); }

      if (viewerOk && window.VSP && window.VSP.jsonViewer){
        window.VSP.jsonViewer.render(jsonBox, { endpoint, payload }, { title:"RuleOverrides", maxDepth: 8 });
      } else {
        warn("jsonViewer missing; fallback <pre>");
        jsonBox.innerHTML = `<pre style="white-space:pre-wrap;word-break:break-word;opacity:.9">${(r.text||"").slice(0,3000)}</pre>`;
      }
    }

    btnReload.addEventListener("click", reload);

    btnValidate.addEventListener("click", ()=>{
      try{
        JSON.parse(ta.value);
        msg.innerHTML = `${badge(true)} JSON valid`;
      }catch(e){
        msg.innerHTML = `${badge(false)} JSON invalid: ${String(e && e.message ? e.message : e)}`;
      }
    });

    btnSave.addEventListener("click", async ()=>{
      let obj;
      try{
        obj = JSON.parse(ta.value);
      }catch(e){
        msg.innerHTML = `${badge(false)} Cannot save: JSON invalid`;
        return;
      }
      msg.textContent = "Saving…";
      const r = await fetchJson(endpoint, { method:"POST", body: obj, timeoutMs: 7000 });
      msg.innerHTML = `${badge(r.ok)} POST status=${r.status} • ${Math.round(r.ms)}ms • ${(r.data && (r.data.message||r.data.status)) ? (r.data.message||r.data.status) : ""}`;
      // refresh view after save if ok
      if (r.ok) await reload();
    });

    await reload();
    log("rendered");
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
JS

echo "== [CHECK] node --check =="
node --check "$VIEW_JS"
node --check "$SET_JS"
node --check "$OVR_JS"

echo ""
echo "[OK] P401 rewrite installed:"
echo " - $VIEW_JS"
echo " - $SET_JS"
echo " - $OVR_JS"
echo ""
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
