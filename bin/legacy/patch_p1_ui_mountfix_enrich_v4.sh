#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [1] PATCH RUNS: mount fix + enrich has_findings/degraded via status JSON =="
F_RUNS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F_RUNS" ] || { echo "[ERR] missing $F_RUNS"; exit 2; }
cp -f "$F_RUNS" "$F_RUNS.bak_mountfix_${TS}" && echo "[BACKUP] $F_RUNS.bak_mountfix_${TS}"

cat > "$F_RUNS" <<'JS'
/* VSP_RUNS_TAB_RESOLVED_V2 (commercial): mount fix + dataset filters + enrich flags from JSON */
(function(){
  'use strict';

  const API_RUNS   = "/api/vsp/runs_index_v3_fs_resolved";
  const API_STATUS = "/api/vsp/run_status_v2"; // /<rid>
  const EXPORT_BASE = "/api/vsp/run_export_v3";
  const ART_BASE    = "/api/vsp/artifacts_index_v1";

  function $(sel, root){ return (root||document).querySelector(sel); }
  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function esc(s){ return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function toBoolOrNull(v){
    if (v === true || v === false) return v;
    if (v === 1 || v === 0) return !!v;
    if (typeof v === "string"){
      const t=v.trim().toLowerCase();
      if (t==="1"||t==="true"||t==="yes") return true;
      if (t==="0"||t==="false"||t==="no") return false;
    }
    return null;
  }
  function flagToAttr(v){ return v === true ? "1" : v === false ? "0" : "?"; }

  function visibleEl(el){
    if (!el) return false;
    const r = el.getBoundingClientRect();
    return !!(el.offsetParent !== null && r.width > 200 && r.height > 120);
  }

  function pickBestContainer(){
    const cands = [
      "#tab-runs","#vsp4-runs","[data-tab='runs']","#runs",
      "#tabpane-runs","#pane-runs","#panel-runs",
      ".tab-pane.active",".tab-pane.is-active",
      ".vsp-main",".vsp-content","main",".content","#content",".page-content",
      "body"
    ];
    let best = document.body, bestArea = 0;
    for (const sel of cands){
      const els = $all(sel);
      for (const el of els){
        if (!visibleEl(el)) continue;
        const r = el.getBoundingClientRect();
        const area = r.width * r.height;
        if (area > bestArea){
          bestArea = area;
          best = el;
        }
      }
    }
    return best || document.body;
  }

  function ensureUI(root){
    // toolbar
    let tb = $("#vsp-runs-toolbar", root);
    if (!tb){
      tb = document.createElement("div");
      tb.id = "vsp-runs-toolbar";
      tb.className = "vsp-card vsp-card--tight";
      tb.style.marginBottom = "10px";
      tb.innerHTML = `
        <div style="display:flex; gap:10px; flex-wrap:wrap; align-items:center;">
          <div style="display:flex; gap:8px; align-items:center;">
            <label style="opacity:.9">Limit</label>
            <select id="vsp-runs-limit" class="vsp-input">
              <option value="10">10</option>
              <option value="20">20</option>
              <option value="50" selected>50</option>
              <option value="100">100</option>
              <option value="200">200</option>
            </select>
          </div>

          <div style="display:flex; gap:8px; align-items:center;">
            <label style="opacity:.9">Has findings</label>
            <select id="vsp-runs-filter-hf" class="vsp-input">
              <option value="all" selected>All</option>
              <option value="1">Yes</option>
              <option value="0">No</option>
              <option value="?">Unknown</option>
            </select>
          </div>

          <div style="display:flex; gap:8px; align-items:center;">
            <label style="opacity:.9">Degraded</label>
            <select id="vsp-runs-filter-deg" class="vsp-input">
              <option value="all" selected>All</option>
              <option value="1">Yes</option>
              <option value="0">No</option>
              <option value="?">Unknown</option>
            </select>
          </div>

          <div style="display:flex; gap:8px; align-items:center; flex:1; min-width:220px;">
            <label style="opacity:.9">Search</label>
            <input id="vsp-runs-search" class="vsp-input" placeholder="run_id / target / status..." style="flex:1; min-width:180px;" />
          </div>

          <button id="vsp-runs-refresh" class="vsp-btn">Refresh</button>
          <span id="vsp-runs-meta" style="opacity:.8"></span>
        </div>
      `;
      // IMPORTANT: insert at very top of chosen container to ensure visible
      root.prepend(tb);
    }

    let table = $("#vsp-runs-table", root);
    if (!table){
      table = document.createElement("table");
      table.id = "vsp-runs-table";
      table.className = "vsp-table";
      table.style.width = "100%";
      table.innerHTML = `
        <thead>
          <tr>
            <th style="width:200px;">Time</th>
            <th>Run ID</th>
            <th style="width:140px;">Target</th>
            <th style="width:120px;">Status</th>
            <th style="width:120px;">Findings</th>
            <th style="width:120px;">Degraded</th>
            <th style="width:220px;">Actions</th>
          </tr>
        </thead>
        <tbody id="vsp-runs-tbody"></tbody>
      `;
      root.insertBefore(table, tb.nextSibling);
    }
    const tbody = $("#vsp-runs-tbody", root) || table.querySelector("tbody");
    return {tb, table, tbody};
  }

  function normalizeRuns(json){
    const items = (json && (json.items || json.data || json.runs)) || [];
    return Array.isArray(items) ? items : [];
  }

  function pickFlagOnly(item, keys){
    for (const k of keys){
      if (Object.prototype.hasOwnProperty.call(item, k)){
        const b = toBoolOrNull(item[k]);
        if (b !== null) return b;
        return null;
      }
    }
    return null;
  }

  async function safeJson(url){
    try{
      const r = await fetch(url, {credentials:"same-origin"});
      return await r.json();
    }catch(_e){
      return {};
    }
  }

  // lightweight concurrency to avoid hammering
  async function mapLimit(arr, limit, fn){
    const out = new Array(arr.length);
    let i = 0;
    const workers = new Array(Math.min(limit, arr.length)).fill(0).map(async () => {
      while (true){
        const idx = i++;
        if (idx >= arr.length) break;
        out[idx] = await fn(arr[idx], idx);
      }
    });
    await Promise.all(workers);
    return out;
  }

  function buildRowSkeleton(item){
    const rid = String(item.run_id || item.rid || item.id || "");
    const created = item.ts || item.created_at || item.created || item.time || item.started_at || "";
    const target = item.target_id || item.target || item.profile || item.app || "";
    const status = item.status || item.stage || item.state || "";

    const tr = document.createElement("tr");
    tr.dataset.rid = rid;
    tr.dataset.hasFindings = "?";
    tr.dataset.degraded = "?";
    tr.setAttribute("data-has-findings","?");
    tr.setAttribute("data-degraded","?");

    tr.innerHTML = `
      <td>${esc(created)}</td>
      <td><code>${esc(rid)}</code></td>
      <td>${esc(target)}</td>
      <td>${esc(status)}</td>
      <td><span class="vsp-pill" data-role="hf">UNKNOWN</span></td>
      <td><span class="vsp-pill" data-role="deg">UNKNOWN</span></td>
      <td style="display:flex; gap:8px; flex-wrap:wrap;">
        <a class="vsp-btn vsp-btn--ghost" href="${esc(API_STATUS + "/" + encodeURIComponent(rid))}" target="_blank" rel="noopener">status</a>
        <a class="vsp-btn vsp-btn--ghost" href="${esc(ART_BASE + "/" + encodeURIComponent(rid))}" target="_blank" rel="noopener">artifacts</a>
        <a class="vsp-btn vsp-btn--ghost" href="${esc(EXPORT_BASE + "/" + encodeURIComponent(rid) + "?fmt=html")}" target="_blank" rel="noopener">html</a>
        <a class="vsp-btn vsp-btn--ghost" href="${esc(EXPORT_BASE + "/" + encodeURIComponent(rid) + "?fmt=zip")}" target="_blank" rel="noopener">zip</a>
        <a class="vsp-btn vsp-btn--ghost" href="${esc(EXPORT_BASE + "/" + encodeURIComponent(rid) + "?fmt=pdf")}" target="_blank" rel="noopener">pdf</a>
      </td>
    `;
    return tr;
  }

  function applyFlagsToRow(tr, hasFindings, degraded){
    const hfAttr = flagToAttr(hasFindings);
    const dgAttr = flagToAttr(degraded);
    tr.dataset.hasFindings = hfAttr;
    tr.dataset.degraded = dgAttr;
    tr.setAttribute("data-has-findings", hfAttr);
    tr.setAttribute("data-degraded", dgAttr);

    const hf = tr.querySelector('[data-role="hf"]');
    const dg = tr.querySelector('[data-role="deg"]');
    if (hf) hf.textContent = hfAttr === "1" ? "YES" : hfAttr === "0" ? "NO" : "UNKNOWN";
    if (dg) dg.textContent = dgAttr === "1" ? "YES" : dgAttr === "0" ? "NO" : "UNKNOWN";
  }

  function applyFilters(root){
    const hf = $("#vsp-runs-filter-hf", root)?.value || "all";
    const dg = $("#vsp-runs-filter-deg", root)?.value || "all";
    const q  = ($("#vsp-runs-search", root)?.value || "").trim().toLowerCase();

    const rows = $all("#vsp-runs-tbody tr", root);
    let shown = 0;

    for (const tr of rows){
      const rhf = tr.getAttribute("data-has-findings") || tr.dataset.hasFindings || "?";
      const rdg = tr.getAttribute("data-degraded") || tr.dataset.degraded || "?";

      let ok = true;
      if (hf !== "all" && rhf !== hf) ok = false;
      if (dg !== "all" && rdg !== dg) ok = false;

      if (ok && q){
        const hay = (tr.textContent || "").toLowerCase();
        if (!hay.includes(q)) ok = false;
      }

      tr.hidden = !ok;
      if (ok) shown++;
    }

    const meta = $("#vsp-runs-meta", root);
    if (meta) meta.textContent = `Showing ${shown}/${rows.length}`;
  }

  async function enrichFlags(item){
    const rid = String(item.run_id || item.rid || item.id || "");
    if (!rid) return {rid, hasFindings:null, degraded:null};

    // 1) try from runs_index fields (strict)
    let hasFindings = pickFlagOnly(item, ["has_findings","hasFindings","findings_present"]);
    let degraded    = pickFlagOnly(item, ["degraded","is_degraded","degraded_any","degradedAny"]);

    // 2) if missing -> use status JSON (still deterministic JSON, not row text)
    if (hasFindings === null || degraded === null){
      const st = await safeJson(API_STATUS + "/" + encodeURIComponent(rid));

      if (hasFindings === null){
        // prefer explicit bool; else numeric total
        hasFindings = pickFlagOnly(st, ["has_findings","hasFindings"]);
        if (hasFindings === null){
          const total = st.total_findings ?? st.findings_total ?? st.total ?? null;
          if (typeof total === "number") hasFindings = total > 0;
        }
      }

      if (degraded === null){
        degraded = pickFlagOnly(st, ["degraded","degraded_any","is_degraded","degradedAny"]);
        if (degraded === null){
          const dn = st.degraded_n ?? st.degraded_count ?? null;
          if (typeof dn === "number") degraded = dn > 0;
        }
      }
    }

    return {rid, hasFindings, degraded};
  }

  async function loadRuns(root){
    const limit = parseInt($("#vsp-runs-limit", root)?.value || "50", 10) || 50;
    const url = `${API_RUNS}?limit=${encodeURIComponent(String(limit))}&hide_empty=0&filter=1`;

    const meta = $("#vsp-runs-meta", root);
    if (meta) meta.textContent = "Loading runs...";

    const res = await fetch(url, {credentials:"same-origin"});
    const json = await res.json().catch(() => ({}));
    const items = normalizeRuns(json);
    window.__vspRunsItems = items;

    const {tbody} = ensureUI(root);
    tbody.innerHTML = "";

    // render skeletons first (fast)
    const rowByRid = new Map();
    for (const it of items){
      const tr = buildRowSkeleton(it);
      tbody.appendChild(tr);
      rowByRid.set(tr.dataset.rid, tr);
    }
    applyFilters(root);

    // enrich flags with limited concurrency
    if (meta) meta.textContent = `Enriching flags via JSON status... (${items.length})`;
    const enriched = await mapLimit(items, 6, enrichFlags);

    let okN = 0;
    for (const e of enriched){
      const tr = rowByRid.get(e.rid);
      if (!tr) continue;
      applyFlagsToRow(tr, e.hasFindings, e.degraded);
      okN++;
    }
    applyFilters(root);
    if (meta) meta.textContent = `Loaded ${items.length}. Enriched flags for ${okN} runs.`;
  }

  function bind(root){
    $("#vsp-runs-refresh", root)?.addEventListener("click", () => loadRuns(root).catch(e => console.error("[VSP_RUNS] load error", e)));
    $("#vsp-runs-limit", root)?.addEventListener("change", () => loadRuns(root).catch(e => console.error("[VSP_RUNS] load error", e)));

    const onFilter = () => applyFilters(root);
    $("#vsp-runs-filter-hf", root)?.addEventListener("change", onFilter);
    $("#vsp-runs-filter-deg", root)?.addEventListener("change", onFilter);
    $("#vsp-runs-search", root)?.addEventListener("input", onFilter);
  }

  function init(){
    const root = pickBestContainer();
    ensureUI(root);
    bind(root);
    loadRuns(root).catch(e => console.error("[VSP_RUNS] init load error", e));
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
JS

node --check "$F_RUNS" >/dev/null && echo "[OK] runs JS syntax OK"

echo
echo "== [2] PATCH SETTINGS SIMPLE: mount fix (append into visible main container) =="
F_SET="static/js/vsp_settings_tab_simple_v1.js"
[ -f "$F_SET" ] || { echo "[ERR] missing $F_SET"; exit 3; }
cp -f "$F_SET" "$F_SET.bak_mountfix_${TS}" && echo "[BACKUP] $F_SET.bak_mountfix_${TS}"

# remove previous policy block (simple v1) then append v2 with robust mount
perl -0777 -i -pe 's@/\*\s*VSP_SETTINGS_COMMERCIAL_POLICY_SIMPLE_V1_BEGIN\s*\*/.*?/\*\s*VSP_SETTINGS_COMMERCIAL_POLICY_SIMPLE_V1_END\s*\*/@@sg' "$F_SET"

cat >> "$F_SET" <<'JS'

/* VSP_SETTINGS_COMMERCIAL_POLICY_SIMPLE_V2_BEGIN */
(function(){
  'use strict';

  const API_SETTINGS = "/api/vsp/settings_v1";
  const API_DASH     = "/api/vsp/dashboard_v3";

  function $(sel, root){ return (root||document).querySelector(sel); }
  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function esc(s){ return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function visibleEl(el){
    if (!el) return false;
    const r = el.getBoundingClientRect();
    return !!(el.offsetParent !== null && r.width > 240 && r.height > 160);
  }

  function pickBestSettingsContainer(){
    const cands = [
      "#tab-settings","#vsp4-settings","[data-tab='settings']","#settings",
      "#tabpane-settings","#pane-settings","#panel-settings",
      ".tab-pane.active",".tab-pane.is-active",
      ".vsp-main",".vsp-content","main",".content","#content",".page-content",
      "body"
    ];
    let best = document.body, bestArea = 0;
    for (const sel of cands){
      const els = $all(sel);
      for (const el of els){
        if (!visibleEl(el)) continue;
        const r = el.getBoundingClientRect();
        const area = r.width * r.height;
        if (area > bestArea){
          bestArea = area;
          best = el;
        }
      }
    }
    return best || document.body;
  }

  function ensureHost(root){
    let host = $("#vsp-settings-commercial-policy", root);
    if (!host){
      host = document.createElement("div");
      host.id = "vsp-settings-commercial-policy";
      host.className = "vsp-card";
      host.style.marginTop = "12px";
      root.appendChild(host);
    }
    return host;
  }

  async function safeJson(url){
    try{
      const r = await fetch(url, { credentials: "same-origin" });
      return await r.json();
    }catch(_e){
      return {};
    }
  }

  function pick(obj, keys){
    for (const k of keys){
      if (obj && Object.prototype.hasOwnProperty.call(obj, k)) return obj[k];
    }
    return undefined;
  }

  function render(host, ctx){
    const tools = [
      ["Bandit","SAST (Python)"],["Semgrep","SAST"],["Gitleaks","Secrets"],["KICS","IaC"],
      ["Trivy","Vuln (FS)"],["Syft","SBOM"],["Grype","Vuln (SBOM)"],["CodeQL","SAST (deep)"]
    ];
    host.innerHTML = `
      <h3 style="margin:0 0 6px 0;">Commercial Operational Policy</h3>
      <div style="opacity:.8; margin-bottom:10px;">8 tools + timeout/degraded governance + exports/artifacts + ISO note (CIO readable).</div>

      <div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:10px;">
        ${tools.map(t => `
          <div class="vsp-card vsp-card--tight">
            <div style="font-weight:700;">${esc(t[0])}</div>
            <div style="opacity:.85;">${esc(t[1])}</div>
          </div>
        `).join("")}
      </div>

      <hr style="opacity:.15; margin:12px 0;" />
      <h4 style="margin:0 0 8px 0;">Timeout & Degraded</h4>
      <ul style="margin:0; padding-left:18px; opacity:.92; line-height:1.5;">
        <li>Timeout/missing tool ⇒ <b>DEGRADED</b> (pipeline không treo).</li>
        <li>Degraded = tool không hoàn tất nhưng có log/artifact + run kết thúc FINAL.</li>
      </ul>

      <hr style="opacity:.15; margin:12px 0;" />
      <h4 style="margin:0 0 8px 0;">Current Flags</h4>
      <div class="vsp-card vsp-card--tight" style="opacity:.92; line-height:1.6;">
        <div>FS_FALLBACK: <b>${esc(ctx.flags.FS_FALLBACK)}</b></div>
        <div>EXPORT_FORCE_BIND: <b>${esc(ctx.flags.EXPORT_FORCE_BIND)}</b></div>
        <div>OVERRIDES_ENABLED: <b>${esc(ctx.flags.OVERRIDES_ENABLED)}</b></div>
      </div>

      <hr style="opacity:.15; margin:12px 0;" />
      <h4 style="margin:0 0 8px 0;">Key Endpoints</h4>
      <div style="opacity:.92; line-height:1.6;">
        <div><code>/api/vsp/runs_index_v3_fs_resolved</code></div>
        <div><code>/api/vsp/run_status_v2/&lt;rid&gt;</code></div>
        <div><code>/api/vsp/artifacts_index_v1/&lt;rid&gt;</code></div>
        <div><code>/api/vsp/run_export_v3/&lt;rid&gt;?fmt=html|zip|pdf</code></div>
      </div>

      <hr style="opacity:.15; margin:12px 0;" />
      <h4 style="margin:0 0 8px 0;">ISO 27001 Note</h4>
      <div style="opacity:.92; line-height:1.5;">
        ISO mapping phục vụ governance/traceability (không phải chứng nhận).
      </div>
    `;
  }

  async function init(){
    const root = pickBestSettingsContainer();
    const host = ensureHost(root);

    const settings = await safeJson(API_SETTINGS);
    const dash = await safeJson(API_DASH);

    const flags = {
      FS_FALLBACK: String(pick(settings, ["fs_fallback","FS_FALLBACK"]) ?? pick(dash, ["fs_fallback","FS_FALLBACK"]) ?? "UNKNOWN"),
      EXPORT_FORCE_BIND: String(pick(settings, ["export_force_bind","EXPORT_FORCE_BIND"]) ?? "UNKNOWN"),
      OVERRIDES_ENABLED: String(pick(settings, ["overrides_enabled","OVERRIDES_ENABLED"]) ?? "UNKNOWN"),
    };

    render(host, { flags });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
/* VSP_SETTINGS_COMMERCIAL_POLICY_SIMPLE_V2_END */

JS

node --check "$F_SET" >/dev/null && echo "[OK] settings(simple) JS syntax OK"

echo
echo "== [3] FIX pickLatest ReferenceError (vsp_rid_state_v1.js) =="
F_RID="static/js/vsp_rid_state_v1.js"
if [ -f "$F_RID" ]; then
  cp -f "$F_RID" "$F_RID.bak_pickLatest_${TS}" && echo "[BACKUP] $F_RID.bak_pickLatest_${TS}"
  # prepend shim only if not already present
  if ! grep -q "VSP_PICKLATEST_SHIM_V1" "$F_RID"; then
    tmp="/tmp/vsp_rid_state_v1.${TS}.js"
    cat > "$tmp" <<'JSP'
/* VSP_PICKLATEST_SHIM_V1: define pickLatest if missing (avoid ReferenceError) */
if (typeof pickLatest !== "function") {
  // pick latest item by ts/created_at or by lexical run_id fallback
  var pickLatest = function(items){
    try{
      if (!Array.isArray(items) || !items.length) return null;
      const score = (it) => {
        const t = it && (it.ts || it.created_at || it.created || it.time || it.started_at);
        const n = (t && Date.parse(t)) ? Date.parse(t) : NaN;
        if (!Number.isNaN(n)) return n;
        const rid = String(it.run_id || it.rid || it.id || "");
        // lexical fallback (works for VSP_CI_YYYYmmdd_HHMMSS-ish)
        return rid ? rid.split("").reduce((a,c)=>a + c.charCodeAt(0), 0) : 0;
      };
      let best = items[0], bestS = score(best);
      for (const it of items){
        const s = score(it);
        if (s > bestS){ bestS = s; best = it; }
      }
      return best;
    }catch(_e){
      return items[0] || null;
    }
  };
}
JSP
    cat "$tmp" "$F_RID" > "${F_RID}.new"
    mv -f "${F_RID}.new" "$F_RID"
  fi
  node --check "$F_RID" >/dev/null && echo "[OK] rid_state JS syntax OK"
else
  echo "[WARN] missing $F_RID (skip)"
fi

echo
echo "[DONE] P1 UI mountfix+enrich applied. Hard refresh Ctrl+Shift+R."
