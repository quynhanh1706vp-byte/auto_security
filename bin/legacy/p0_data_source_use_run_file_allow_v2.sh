#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node
TS="$(date +%Y%m%d_%H%M%S)"

JS="static/js/vsp_data_source_lazy_v1.js"
[ -d static/js ] || mkdir -p static/js

cp -f "$JS" "${JS}.bak_rfallow_${TS}" 2>/dev/null || true
echo "[BACKUP] ${JS}.bak_rfallow_${TS}"

cat > "$JS" <<'JS'
/* VSP_P0_DATA_SOURCE_USE_RUN_FILE_ALLOW_V2 (no /api/vsp/findings_page dependency) */
(()=> {
  if (window.__vsp_ds_rfallow_v2) return;
  window.__vsp_ds_rfallow_v2 = true;

  const $ = (sel, root=document)=> root.querySelector(sel);
  const $$ = (sel, root=document)=> Array.from(root.querySelectorAll(sel));

  const state = {
    rid: null,
    findings: [],
    meta: {},
    filtered: [],
    offset: 0,
    limit: 50,
    q: "",
    sev: "ALL",
    tool: "ALL",
    loading: false,
    err: null,
  };

  function esc(s){
    return String(s??"").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
  }

  async function jget(url){
    const r = await fetch(url, { credentials:"same-origin", cache:"no-store" });
    const t = await r.text();
    let j=null;
    try { j = JSON.parse(t); } catch(e){ throw new Error(`JSON parse fail ${r.status} ${url}: ${t.slice(0,160)}`); }
    if (!r.ok) throw new Error(`HTTP ${r.status} ${url}: ${(j && (j.err||j.error)) || t.slice(0,160)}`);
    if (j && j.ok === false && (j.err||j.error)) throw new Error(`API not ok ${url}: ${j.err||j.error}`);
    return j;
  }

  function pick(obj, keys){
    for (const k of keys){
      if (obj && obj[k] != null) return obj[k];
    }
    return null;
  }

  function normalizeFinding(f){
    const tool = pick(f, ["tool","scanner","source"]) || "UNKNOWN";
    const severity = (pick(f, ["severity","sev","level"]) || "INFO").toString().toUpperCase();
    const title = pick(f, ["title","message","name","rule_message"]) || pick(f, ["rule_id","check_id"]) || "(no title)";
    const rule = pick(f, ["rule_id","check_id","id","rule"]) || "";
    const file = pick(f, ["file","path","filename","location_path"]) || "";
    const line = pick(f, ["line","start_line","location_line"]) || "";
    const sink = pick(f, ["sink","cwe","owasp","category"]) || "";
    const desc = pick(f, ["desc","description","details"]) || "";
    return { tool, severity, title, rule, file, line, sink, desc, raw: f };
  }

  function applyFilters(){
    const q = state.q.trim().toLowerCase();
    const sev = state.sev;
    const tool = state.tool;

    let arr = state.findings;
    if (sev !== "ALL") arr = arr.filter(x=>x.severity === sev);
    if (tool !== "ALL") arr = arr.filter(x=>x.tool === tool);
    if (q){
      arr = arr.filter(x=>{
        const hay = `${x.title} ${x.rule} ${x.file} ${x.sink} ${x.tool} ${x.severity}`.toLowerCase();
        return hay.includes(q);
      });
    }
    state.filtered = arr;
    state.offset = 0;
  }

  function renderTools(){
    const sel = $("#vsp_ds_tool");
    if (!sel) return;
    const tools = Array.from(new Set(state.findings.map(x=>x.tool))).sort((a,b)=>a.localeCompare(b));
    const cur = state.tool;
    sel.innerHTML = `<option value="ALL">ALL tools (${tools.length})</option>` + tools.map(t=>`<option value="${esc(t)}">${esc(t)}</option>`).join("");
    sel.value = tools.includes(cur) ? cur : "ALL";
  }

  function renderCounts(){
    const el = $("#vsp_ds_counts");
    if (!el) return;
    el.textContent = `RID: ${state.rid || "-"} • Total: ${state.findings.length} • Filtered: ${state.filtered.length}`;
  }

  function renderTable(){
    const tbody = $("#vsp_ds_tbody");
    if (!tbody) return;

    const start = state.offset;
    const end = Math.min(state.filtered.length, start + state.limit);
    const page = state.filtered.slice(start, end);

    tbody.innerHTML = page.map((x, idx)=> {
      return `<tr>
        <td>${start + idx + 1}</td>
        <td><span class="badge sev-${esc(x.severity)}">${esc(x.severity)}</span></td>
        <td>${esc(x.tool)}</td>
        <td title="${esc(x.title)}">${esc(x.title)}</td>
        <td>${esc(x.rule)}</td>
        <td title="${esc(x.file)}">${esc(x.file)}</td>
        <td>${esc(x.line)}</td>
      </tr>`;
    }).join("");

    const pager = $("#vsp_ds_pager");
    if (pager){
      pager.textContent = `${start+1}-${end} / ${state.filtered.length}`;
    }
  }

  function setBusy(on, msg){
    state.loading = on;
    const el = $("#vsp_ds_busy");
    if (!el) return;
    el.style.display = on ? "block" : "none";
    el.textContent = msg || (on ? "Loading..." : "");
  }

  async function loadLatest(){
    try{
      setBusy(true, "Loading latest run + findings...");
      const runs = await jget(`/api/vsp/runs?limit=1`);
      const r0 = (runs.runs || runs.items || [])[0] || {};
      const rid = pick(r0, ["rid","run_id","id"]);
      if (!rid) throw new Error("No rid from /api/vsp/runs?limit=1");
      state.rid = rid;

      // prefer findings_unified.json via allow endpoint
      const path = "findings_unified.json";
      const data = await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`);

      // support both shapes: {meta,findings} or {findings:[...]}
      const rawFindings = data.findings || (data.data && data.data.findings) || [];
      state.meta = data.meta || {};
      state.findings = rawFindings.map(normalizeFinding);

      applyFilters();
      renderTools();
      renderCounts();
      renderTable();

      setBusy(false, "");
    } catch(e){
      console.error("[VSP_DS] loadLatest failed:", e);
      setBusy(false, "");
      const err = $("#vsp_ds_err");
      if (err){
        err.style.display = "block";
        err.textContent = String(e && e.message ? e.message : e);
      }
    }
  }

  function wire(){
    const q = $("#vsp_ds_q");
    const sev = $("#vsp_ds_sev");
    const tool = $("#vsp_ds_tool");

    let tmr = null;
    if (q){
      q.addEventListener("input", ()=>{
        clearTimeout(tmr);
        tmr = setTimeout(()=> {
          state.q = q.value || "";
          applyFilters(); renderCounts(); renderTable();
        }, 120);
      });
    }
    if (sev){
      sev.addEventListener("change", ()=>{
        state.sev = sev.value || "ALL";
        applyFilters(); renderCounts(); renderTable();
      });
    }
    if (tool){
      tool.addEventListener("change", ()=>{
        state.tool = tool.value || "ALL";
        applyFilters(); renderCounts(); renderTable();
      });
    }

    const prev = $("#vsp_ds_prev");
    const next = $("#vsp_ds_next");
    if (prev){
      prev.addEventListener("click", ()=>{
        state.offset = Math.max(0, state.offset - state.limit);
        renderTable();
      });
    }
    if (next){
      next.addEventListener("click", ()=>{
        if (state.offset + state.limit < state.filtered.length){
          state.offset += state.limit;
          renderTable();
        }
      });
    }

    const reload = $("#vsp_ds_reload");
    if (reload){
      reload.addEventListener("click", ()=> loadLatest());
    }
  }

  function ensureSkeleton(){
    // If template didn’t ship controls, create minimal UI inside #vsp_data_source_root
    const root = $("#vsp_data_source_root") || $("#root") || document.body;
    if (!$("#vsp_ds_q")){
      const wrap = document.createElement("div");
      wrap.innerHTML = `
      <div class="vsp-ds-top">
        <div class="row">
          <button id="vsp_ds_reload" class="btn">Reload</button>
          <span id="vsp_ds_counts" class="muted">...</span>
        </div>
        <div class="row">
          <input id="vsp_ds_q" class="inp" placeholder="Search title/rule/file/tool/severity..." />
          <select id="vsp_ds_sev" class="sel">
            <option value="ALL">ALL severity</option>
            <option value="CRITICAL">CRITICAL</option>
            <option value="HIGH">HIGH</option>
            <option value="MEDIUM">MEDIUM</option>
            <option value="LOW">LOW</option>
            <option value="INFO">INFO</option>
            <option value="TRACE">TRACE</option>
          </select>
          <select id="vsp_ds_tool" class="sel"><option>ALL tools</option></select>
          <span id="vsp_ds_busy" class="muted" style="display:none"></span>
          <span id="vsp_ds_err" class="err" style="display:none"></span>
        </div>
      </div>
      <div class="vsp-ds-table">
        <table>
          <thead><tr>
            <th>#</th><th>Sev</th><th>Tool</th><th>Title</th><th>Rule</th><th>File</th><th>Line</th>
          </tr></thead>
          <tbody id="vsp_ds_tbody"></tbody>
        </table>
      </div>
      <div class="vsp-ds-foot">
        <button id="vsp_ds_prev" class="btn">Prev</button>
        <span id="vsp_ds_pager" class="muted">0-0/0</span>
        <button id="vsp_ds_next" class="btn">Next</button>
      </div>
      <style>
        .vsp-ds-top{padding:12px 10px}
        .row{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:6px 0}
        .btn{padding:8px 12px;border-radius:10px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:#e8eefc;cursor:pointer}
        .inp{min-width:320px;padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.04);color:#e8eefc}
        .sel{padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.04);color:#e8eefc}
        .muted{opacity:.8}
        .err{color:#ffb4b4}
        .vsp-ds-table{padding:0 10px 10px}
        table{width:100%;border-collapse:collapse}
        th,td{padding:10px 8px;border-bottom:1px solid rgba(255,255,255,.08);vertical-align:top}
        th{opacity:.85;text-align:left}
        .badge{padding:2px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.14);font-size:12px;display:inline-block}
        .sev-CRITICAL{font-weight:700}
        .sev-HIGH{font-weight:700}
      </style>
      `;
      root.prepend(wrap);
    }
  }

  document.addEventListener("DOMContentLoaded", ()=>{
    ensureSkeleton();
    wire();
    loadLatest();
  });
})();
JS

node --check "$JS" >/dev/null
echo "[OK] node --check passed: $JS"
echo "[DONE] Reload /data_source (Ctrl+F5). Data Source will NOT call /api/vsp/findings_page anymore."
