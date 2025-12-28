#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

F_DASH="static/js/vsp_dashboard_enhance_v1.js"
F_DS="static/js/vsp_datasource_tab_v1.js"
F_TPL="templates/vsp_5tabs_full.html"

[ -f "$F_DASH" ] || { echo "[ERR] missing $F_DASH"; exit 1; }
[ -f "$F_DS" ] || { echo "[ERR] missing $F_DS"; exit 1; }

cp -f "$F_DASH" "$F_DASH.bak_p2_drill_${TS}"
cp -f "$F_DS"   "$F_DS.bak_p2_table_${TS}"
echo "[BACKUP] $F_DASH.bak_p2_drill_${TS}"
echo "[BACKUP] $F_DS.bak_p2_table_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

dash = Path("static/js/vsp_dashboard_enhance_v1.js")
ds   = Path("static/js/vsp_datasource_tab_v1.js")

TAG_DASH = "// === VSP_P2_DRILL_ROUTER_V1 ==="
TAG_DS   = "// === VSP_P2_DATASOURCE_TABLE_V1 ==="

dash_t = dash.read_text(encoding="utf-8", errors="ignore")
ds_t   = ds.read_text(encoding="utf-8", errors="ignore")

# ---------------------------
# Patch DataSource tab JS
# ---------------------------
if TAG_DS not in ds_t:
    ds_patch = r'''
// === VSP_P2_DATASOURCE_TABLE_V1 ===
// Commercial Data Source: hash drilldown + filters + table renderer
(function(){
  function esc(s){
    if (s === null || s === undefined) return "";
    return String(s)
      .replace(/&/g,"&amp;")
      .replace(/</g,"&lt;")
      .replace(/>/g,"&gt;")
      .replace(/"/g,"&quot;")
      .replace(/'/g,"&#39;");
  }

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function ensureRoot(){
    // Try common containers, fallback create
    let root = document.getElementById("vsp-datasource-root")
            || document.getElementById("tab-datasource")
            || document.getElementById("vsp4-datasource")
            || qs("[data-tab='datasource']");
    if (!root){
      root = document.createElement("div");
      root.id = "vsp-datasource-root";
      document.body.appendChild(root);
    }
    if (!root.id) root.id = "vsp-datasource-root";
    return root;
  }

  function parseHashParams(){
    // accept "#tab=datasource&sev=HIGH" or "#/tab=datasource&sev=HIGH"
    let h = (location.hash || "").replace(/^#\/?/,"");
    if (!h) return {};
    // allow "tab=datasource" plus extra
    const out = {};
    for (const part of h.split("&")){
      if (!part) continue;
      const [k,v] = part.split("=",2);
      if (!k) continue;
      out[decodeURIComponent(k)] = decodeURIComponent(v||"");
    }
    return out;
  }

  function buildQuery(params){
    const sp = new URLSearchParams();
    for (const [k,v] of Object.entries(params||{})){
      if (v === undefined || v === null) continue;
      const sv = String(v).trim();
      if (!sv) continue;
      sp.set(k, sv);
    }
    return sp.toString();
  }

  function setStatus(root, html){
    const st = qs("#vsp-ds-status", root);
    if (st) st.innerHTML = html || "";
  }

  function renderSkeleton(root){
    if (qs("#vsp-ds-toolbar", root)) return;

    root.innerHTML = `
      <div id="vsp-ds-toolbar" class="vsp-panel" style="margin:10px 0; padding:10px;">
        <div style="display:flex; gap:10px; flex-wrap:wrap; align-items:flex-end;">
          <div style="min-width:130px;">
            <div class="vsp-label">Severity</div>
            <select id="vsp-ds-sev" class="vsp-input">
              <option value="">(all)</option>
              <option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option>
              <option>LOW</option><option>INFO</option><option>TRACE</option>
            </select>
          </div>
          <div style="min-width:200px;">
            <div class="vsp-label">Tool</div>
            <select id="vsp-ds-tool" class="vsp-input">
              <option value="">(all)</option>
            </select>
          </div>
          <div style="min-width:160px;">
            <div class="vsp-label">CWE</div>
            <input id="vsp-ds-cwe" class="vsp-input" placeholder="CWE-79">
          </div>
          <div style="min-width:220px; flex:1;">
            <div class="vsp-label">Text</div>
            <input id="vsp-ds-q" class="vsp-input" placeholder="title/file/rule contains...">
          </div>
          <div style="min-width:110px;">
            <div class="vsp-label">Limit</div>
            <input id="vsp-ds-limit" class="vsp-input" type="number" min="1" max="2000" value="200">
          </div>
          <label style="display:flex; gap:8px; align-items:center; margin:0 6px;">
            <input id="vsp-ds-show-supp" type="checkbox">
            <span class="vsp-label" style="margin:0;">Show suppressed</span>
          </label>
          <button id="vsp-ds-apply" class="vsp-btn">Load</button>
          <button id="vsp-ds-clear" class="vsp-btn vsp-btn-ghost">Clear</button>
        </div>
        <div id="vsp-ds-status" style="margin-top:10px; opacity:.9;"></div>
      </div>

      <div class="vsp-panel" style="padding:10px;">
        <div style="overflow:auto;">
          <table id="vsp-ds-table" style="width:100%; border-collapse:collapse;">
            <thead>
              <tr>
                <th style="text-align:left; padding:8px;">Sev</th>
                <th style="text-align:left; padding:8px;">Tool</th>
                <th style="text-align:left; padding:8px;">CWE</th>
                <th style="text-align:left; padding:8px;">Title</th>
                <th style="text-align:left; padding:8px;">File</th>
                <th style="text-align:left; padding:8px;">Line</th>
                <th style="text-align:left; padding:8px;">Rule</th>
                <th style="text-align:left; padding:8px;">Flags</th>
              </tr>
            </thead>
            <tbody id="vsp-ds-tbody"></tbody>
          </table>
        </div>
      </div>
    `;
  }

  function rowFlags(it){
    const flags = [];
    // try to detect override effects in a tolerant way
    const sup = it.suppressed || it.is_suppressed || (it.override && it.override.action === "suppress");
    const down = it.downgraded || (it.override && it.override.action === "downgrade");
    if (sup) flags.push("SUPPRESSED");
    if (down) flags.push("DOWNGRADED");
    if (it.degraded) flags.push("DEGRADED");
    return flags.join(", ");
  }

  function getField(it, keys, dflt=""){
    for (const k of keys){
      const v = it?.[k];
      if (v !== undefined && v !== null && String(v).trim() !== "") return v;
    }
    return dflt;
  }

  function renderTable(root, items){
    const tb = qs("#vsp-ds-tbody", root);
    if (!tb) return;
    tb.innerHTML = "";

    if (!items || !items.length){
      tb.innerHTML = `<tr><td colspan="8" style="padding:12px; opacity:.8;">No findings.</td></tr>`;
      return;
    }

    for (const it of items){
      const sev  = getField(it, ["severity","sev","severity_norm","severity_normalized"], "");
      const tool = getField(it, ["tool","scanner","engine"], "");
      const cwe  = getField(it, ["cwe","cwe_id","cwe_name"], "");
      const title= getField(it, ["title","name","issue","message"], "");
      const file = getField(it, ["file","path","filename","location"], "");
      const line = getField(it, ["line","start_line","line_start"], "");
      const rule = getField(it, ["rule","rule_id","check_id","id"], "");
      const flags= rowFlags(it);

      // expandable details row
      const fid = esc(getField(it, ["fingerprint","hash","key","finding_id"], "")) || Math.random().toString(16).slice(2);
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td style="padding:8px; white-space:nowrap;">${esc(sev)}</td>
        <td style="padding:8px; white-space:nowrap;">${esc(tool)}</td>
        <td style="padding:8px; white-space:nowrap;">${esc(cwe)}</td>
        <td style="padding:8px;">
          <a href="#" data-vsp-expand="${esc(fid)}" style="text-decoration:underline;">${esc(title)}</a>
        </td>
        <td style="padding:8px; max-width:380px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${esc(file)}</td>
        <td style="padding:8px; white-space:nowrap;">${esc(line)}</td>
        <td style="padding:8px; max-width:280px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${esc(rule)}</td>
        <td style="padding:8px; white-space:nowrap; opacity:.9;">${esc(flags)}</td>
      `;
      tb.appendChild(tr);

      const tr2 = document.createElement("tr");
      tr2.id = "vsp-ds-details-"+fid;
      tr2.style.display = "none";
      tr2.innerHTML = `
        <td colspan="8" style="padding:10px;">
          <pre style="margin:0; white-space:pre-wrap; word-break:break-word; opacity:.95;">${esc(JSON.stringify(it, null, 2))}</pre>
        </td>
      `;
      tb.appendChild(tr2);
    }

    // bind expand
    qsa("[data-vsp-expand]", root).forEach(a=>{
      a.addEventListener("click", (e)=>{
        e.preventDefault();
        const fid = a.getAttribute("data-vsp-expand");
        const el = document.getElementById("vsp-ds-details-"+fid);
        if (!el) return;
        el.style.display = (el.style.display === "none") ? "" : "none";
      });
    });
  }

  async function loadToolOptions(root){
    const sel = qs("#vsp-ds-tool", root);
    if (!sel || sel._vspLoaded) return;
    sel._vspLoaded = true;

    try{
      const r = await fetch("/api/vsp/dashboard_latest_v1", {cache:"no-store"});
      const j = await r.json();
      const tools = new Set();

      // best-effort extraction
      const byTool = j?.summary_all?.by_tool || j?.kpi?.by_tool || j?.charts?.by_tool || null;
      if (byTool && typeof byTool === "object"){
        Object.keys(byTool).forEach(t=>tools.add(t));
      }
      const series = j?.charts?.tool_bar?.series || j?.charts?.by_tool?.series || null;
      if (Array.isArray(series)){
        series.forEach(s=>{
          const name = s?.name || s?.tool;
          if (name) tools.add(name);
        });
      }
      const labels = j?.charts?.tool_bar?.labels || j?.charts?.by_tool?.labels || null;
      if (Array.isArray(labels)){
        labels.forEach(x=>tools.add(x));
      }

      const list = Array.from(tools).filter(Boolean).sort((a,b)=>String(a).localeCompare(String(b)));
      for (const t of list){
        const opt = document.createElement("option");
        opt.value = t;
        opt.textContent = t;
        sel.appendChild(opt);
      }
    }catch(e){
      // ignore
    }
  }

  async function fetchFindings(filters){
    const q = buildQuery(filters || {});
    const url = "/api/vsp/findings_preview_v1" + (q ? ("?"+q) : "");
    const r = await fetch(url, {cache:"no-store"});
    const j = await r.json();
    return j;
  }

  function getFiltersFromUI(root){
    const sev = (qs("#vsp-ds-sev", root)?.value || "").trim();
    const tool= (qs("#vsp-ds-tool", root)?.value || "").trim();
    const cwe = (qs("#vsp-ds-cwe", root)?.value || "").trim();
    const q   = (qs("#vsp-ds-q", root)?.value || "").trim();
    const limit = (qs("#vsp-ds-limit", root)?.value || "200").trim();
    const show_suppressed = !!qs("#vsp-ds-show-supp", root)?.checked;

    // API supports: sev, tool, cwe, limit, show_suppressed
    // Optional "q" is best-effort: if backend doesn't support, it will just ignore.
    const out = { limit };
    if (sev) out.sev = sev;
    if (tool) out.tool = tool;
    if (cwe) out.cwe = cwe;
    if (q) out.q = q;
    if (show_suppressed) out.show_suppressed = "1";
    return out;
  }

  function setUIFromFilters(root, f){
    if (!f) return;
    const setv=(id,val)=>{
      const el = qs(id, root);
      if (!el) return;
      if (el.type === "checkbox") el.checked = !!val && String(val) !== "0";
      else el.value = val ?? "";
    };
    setv("#vsp-ds-sev", f.sev || "");
    setv("#vsp-ds-tool", f.tool || "");
    setv("#vsp-ds-cwe", f.cwe || "");
    setv("#vsp-ds-q", f.q || "");
    setv("#vsp-ds-limit", f.limit || "200");
    setv("#vsp-ds-show-supp", f.show_suppressed || "");
  }

  async function loadWithFilters(filters, opts){
    const root = ensureRoot();
    renderSkeleton(root);
    await loadToolOptions(root);

    setUIFromFilters(root, filters);

    setStatus(root, `<span style="opacity:.9;">Loading…</span>`);
    let j;
    try{
      j = await fetchFindings(filters);
    }catch(e){
      setStatus(root, `<span style="color:#fca5a5;">Fetch failed: ${esc(e?.message||e)}</span>`);
      renderTable(root, []);
      return;
    }

    const total = j?.total ?? j?.items_n ?? (Array.isArray(j?.items)?j.items.length:0);
    const items = j?.items || [];
    const warn  = j?.warning ? ` <span style="opacity:.8;">(${esc(j.warning)})</span>` : "";
    setStatus(root, `<b>Total</b>: ${esc(total)}${warn}`);

    renderTable(root, items);

    // optionally sync hash
    if (!(opts && opts.noHashSync)){
      const hp = Object.assign({tab:"datasource"}, filters||{});
      const h = "#" + buildQuery(hp);
      if (location.hash !== h) history.replaceState(null, "", h);
    }
  }

  function bindUI(root){
    const apply = qs("#vsp-ds-apply", root);
    const clear = qs("#vsp-ds-clear", root);
    if (apply && !apply._vspBound){
      apply._vspBound = true;
      apply.addEventListener("click", ()=>{
        const f = getFiltersFromUI(root);
        loadWithFilters(f);
      });
    }
    if (clear && !clear._vspBound){
      clear._vspBound = true;
      clear.addEventListener("click", ()=>{
        setUIFromFilters(root, {sev:"",tool:"",cwe:"",q:"",limit:"200",show_suppressed:""});
        loadWithFilters({limit:"200"}, {});
      });
    }
  }

  function ensureInit(){
    const root = ensureRoot();
    renderSkeleton(root);
    bindUI(root);

    // expose a stable global sink for drill router
    window.VSP_DATASOURCE_APPLY_FILTERS_V1 = async function(filters, opts){
      const r = ensureRoot();
      renderSkeleton(r);
      bindUI(r);
      await loadWithFilters(filters||{}, opts||{});
    };

    // if opened directly with hash
    const hp = parseHashParams();
    if ((hp.tab||"") === "datasource"){
      const f = Object.assign({limit:"200"}, hp);
      delete f.tab;
      window.VSP_DATASOURCE_APPLY_FILTERS_V1(f, {noHashSync:true});
    }
  }

  // run init lazily after DOM is ready
  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ensureInit);
  }else{
    ensureInit();
  }
})();
'''
    ds_t = ds_t.rstrip() + "\n" + ds_patch + "\n"
    ds.write_text(ds_t, encoding="utf-8")
    print("[OK] appended datasource table+filters+hash sink")
else:
    print("[OK] datasource patch already present, skip")

# ---------------------------
# Patch Dashboard drill router
# ---------------------------
if TAG_DASH not in dash_t:
    dash_patch = r'''
// === VSP_P2_DRILL_ROUTER_V1 ===
// Drill router: click elements with data-drill -> switch tab datasource + apply filters
(function(){
  function parseHashParams(){
    let h = (location.hash || "").replace(/^#\/?/,"");
    if (!h) return {};
    const out = {};
    for (const part of h.split("&")){
      if (!part) continue;
      const [k,v] = part.split("=",2);
      if (!k) continue;
      out[decodeURIComponent(k)] = decodeURIComponent(v||"");
    }
    return out;
  }

  function buildHash(tab, filters){
    const sp = new URLSearchParams();
    sp.set("tab", tab || "datasource");
    for (const [k,v] of Object.entries(filters||{})){
      if (v === undefined || v === null) continue;
      const sv = String(v).trim();
      if (!sv) continue;
      sp.set(k, sv);
    }
    return "#" + sp.toString();
  }

  function switchToDatasourceTab(){
    // Try click datasource tab button if exists
    const btn = document.querySelector("#tab-datasource, [data-tab-btn='datasource'], a[href*='datasource']");
    if (btn && btn.click) btn.click();
  }

  function applyDatasource(filters){
    // Set hash first (so reload preserves)
    const h = buildHash("datasource", filters||{});
    if (location.hash !== h) location.hash = h;

    // then call sink if available
    const sink = window.VSP_DATASOURCE_APPLY_FILTERS_V1;
    if (typeof sink === "function"){
      try{ sink(filters||{}, {noHashSync:true}); }catch(e){}
    }
  }

  function handleDrillClick(e){
    const a = e.target.closest("[data-drill]");
    if (!a) return;
    e.preventDefault();
    let val = a.getAttribute("data-drill") || "";
    // accept JSON {"sev":"HIGH"} or query "sev=HIGH&tool=semgrep"
    let filters = {};
    try{
      if (val.trim().startsWith("{")) filters = JSON.parse(val);
      else{
        const sp = new URLSearchParams(val.replace(/^#\/?/,""));
        sp.forEach((v,k)=>{ filters[k]=v; });
      }
    }catch(_){
      filters = {};
    }
    switchToDatasourceTab();
    applyDatasource(filters);
  }

  function onHashChange(){
    const hp = parseHashParams();
    if ((hp.tab||"") !== "datasource") return;
    const f = Object.assign({}, hp);
    delete f.tab;
    const sink = window.VSP_DATASOURCE_APPLY_FILTERS_V1;
    if (typeof sink === "function"){
      sink(f, {noHashSync:true});
    }
  }

  function bind(){
    // delegate click drill
    if (!document.body._vspDrillBound){
      document.body._vspDrillBound = true;
      document.body.addEventListener("click", handleDrillClick);
    }
    window.addEventListener("hashchange", onHashChange);
    // initial
    onHashChange();
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", bind);
  }else{
    bind();
  }
})();
'''
    dash_t = dash_t.rstrip() + "\n" + dash_patch + "\n"
    dash.write_text(dash_t, encoding="utf-8")
    print("[OK] appended drill router")
else:
    print("[OK] drill router already present, skip")

PY

# JS syntax check (commercial)
if command -v node >/dev/null 2>&1; then
  node --check static/js/vsp_dashboard_enhance_v1.js
  node --check static/js/vsp_datasource_tab_v1.js
  echo "[OK] node --check JS syntax OK"
else
  echo "[SKIP] node not found; skip JS syntax check"
fi

echo "[DONE] P2 drilldown->datasource table patch applied."
echo "Next: hard refresh (Ctrl+Shift+R) and test:"
echo "  - open: http://127.0.0.1:8910/vsp4"
echo "  - open: http://127.0.0.1:8910/vsp4#tab=datasource&sev=HIGH&limit=200"
