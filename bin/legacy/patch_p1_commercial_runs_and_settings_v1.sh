#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [A] PATCH RUNS: JSON-based filters (has_findings/degraded) =="
F1="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F1" ] || { echo "[ERR] missing $F1"; exit 2; }
cp -f "$F1" "$F1.bak_runs_jsonfilter_${TS}" && echo "[BACKUP] $F1.bak_runs_jsonfilter_${TS}"

cat > "$F1" <<'JS'
/* VSP_RUNS_TAB_RESOLVED_V1 (commercial): filter by dataset flags from API fields only */
(function(){
  'use strict';

  const API_RUNS = "/api/vsp/runs_index_v3_fs_resolved";
  const EXPORT_BASE = "/api/vsp/run_export_v3";   // /<rid>?fmt=html|zip|pdf
  const STATUS_BASE = "/api/vsp/run_status_v2";   // /<rid>
  const ART_BASE   = "/api/vsp/artifacts_index_v1"; // /<rid> (if exists)

  function $(sel, root){ return (root||document).querySelector(sel); }
  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function esc(s){ return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function toBoolOrNull(v){
    if (v === true || v === false) return v;
    if (v === 1 || v === 0) return !!v;
    if (typeof v === "string"){
      const t = v.trim().toLowerCase();
      if (t === "1" || t === "true" || t === "yes") return true;
      if (t === "0" || t === "false" || t === "no") return false;
    }
    return null;
  }
  function flagToAttr(v){ return v === true ? "1" : v === false ? "0" : "?"; }
  function attrToTri(v){
    if (v === "1") return true;
    if (v === "0") return false;
    return null;
  }

  function pickApiFlagOnly(item, keys){
    // Commercial rule: ONLY trust explicit fields from API; if missing => unknown ("?")
    for (const k of keys){
      if (Object.prototype.hasOwnProperty.call(item, k)){
        const b = toBoolOrNull(item[k]);
        if (b !== null) return b;
        // if API provided but not parseable, still treat unknown
        return null;
      }
    }
    return null;
  }

  function normalizeRuns(json){
    const items = (json && (json.items || json.data || json.runs)) || [];
    return Array.isArray(items) ? items : [];
  }

  function ensureRunsRoot(){
    return (
      $("#tab-runs") ||
      $("#vsp4-runs") ||
      $("[data-tab='runs']") ||
      $("#runs") ||
      document.body
    );
  }

  function ensureUI(root){
    // toolbar
    let tb = $("#vsp-runs-toolbar", root);
    if (!tb){
      tb = document.createElement("div");
      tb.id = "vsp-runs-toolbar";
      tb.className = "vsp-card vsp-card--tight";
      tb.style.marginBottom = "12px";
      tb.innerHTML = `
        <div class="vsp-row" style="display:flex; gap:10px; flex-wrap:wrap; align-items:center;">
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
      // place toolbar near top of runs tab
      root.prepend(tb);
    }

    // table
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
      root.appendChild(table);
    }

    return { tb, table, tbody: $("#vsp-runs-tbody", root) || table.querySelector("tbody") };
  }

  function buildRow(item){
    const rid = String(item.run_id || item.rid || item.id || "");
    const created = item.ts || item.created_at || item.created || item.time || item.started_at || "";
    const target = item.target_id || item.target || item.profile || item.app || "";
    const status = item.status || item.stage || item.state || "";

    // Commercial: only trust explicit fields (no heuristic text scan)
    const hasFindings = pickApiFlagOnly(item, ["has_findings","hasFindings","hasFinding","findings_present"]);
    const degraded    = pickApiFlagOnly(item, ["degraded","is_degraded","degraded_any","degradedAny","tool_degraded"]);

    const tr = document.createElement("tr");
    tr.dataset.hasFindings = flagToAttr(hasFindings);
    tr.dataset.degraded = flagToAttr(degraded);
    tr.setAttribute("data-has-findings", tr.dataset.hasFindings);
    tr.setAttribute("data-degraded", tr.dataset.degraded);

    const hfLabel = tr.dataset.hasFindings === "1" ? "YES" : tr.dataset.hasFindings === "0" ? "NO" : "UNKNOWN";
    const degLabel = tr.dataset.degraded === "1" ? "YES" : tr.dataset.degraded === "0" ? "NO" : "UNKNOWN";

    const exportHtml = rid ? `${EXPORT_BASE}/${encodeURIComponent(rid)}?fmt=html` : "#";
    const exportZip  = rid ? `${EXPORT_BASE}/${encodeURIComponent(rid)}?fmt=zip`  : "#";
    const exportPdf  = rid ? `${EXPORT_BASE}/${encodeURIComponent(rid)}?fmt=pdf`  : "#";
    const statusUrl  = rid ? `${STATUS_BASE}/${encodeURIComponent(rid)}` : "#";
    const artUrl     = rid ? `${ART_BASE}/${encodeURIComponent(rid)}`    : "#";

    tr.innerHTML = `
      <td>${esc(created)}</td>
      <td><code>${esc(rid)}</code></td>
      <td>${esc(target)}</td>
      <td>${esc(status)}</td>
      <td><span class="vsp-pill">${esc(hfLabel)}</span></td>
      <td><span class="vsp-pill">${esc(degLabel)}</span></td>
      <td style="display:flex; gap:8px; flex-wrap:wrap;">
        <a class="vsp-btn vsp-btn--ghost" href="${esc(statusUrl)}" target="_blank" rel="noopener">status</a>
        <a class="vsp-btn vsp-btn--ghost" href="${esc(artUrl)}" target="_blank" rel="noopener">artifacts</a>
        <a class="vsp-btn vsp-btn--ghost" href="${esc(exportHtml)}" target="_blank" rel="noopener">html</a>
        <a class="vsp-btn vsp-btn--ghost" href="${esc(exportZip)}" target="_blank" rel="noopener">zip</a>
        <a class="vsp-btn vsp-btn--ghost" href="${esc(exportPdf)}" target="_blank" rel="noopener">pdf</a>
      </td>
    `;
    return tr;
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

  async function loadRuns(root){
    const limit = parseInt($("#vsp-runs-limit", root)?.value || "50", 10) || 50;
    const url = `${API_RUNS}?limit=${encodeURIComponent(String(limit))}&hide_empty=0&filter=1`;
    const meta = $("#vsp-runs-meta", root);
    if (meta) meta.textContent = "Loading...";

    const res = await fetch(url, { credentials: "same-origin" });
    const json = await res.json().catch(() => ({}));
    const items = normalizeRuns(json);

    // cache for other tabs/debug
    window.__vspRunsItems = items;

    const {tbody} = ensureUI(root);
    tbody.innerHTML = "";
    for (const it of items){
      tbody.appendChild(buildRow(it));
    }
    applyFilters(root);

    // also show counts per flag quickly
    const rows = $all("#vsp-runs-tbody tr", root);
    const c = { hf1:0,hf0:0,hfu:0,dg1:0,dg0:0,dgu:0 };
    for (const tr of rows){
      const rhf = tr.getAttribute("data-has-findings") || "?";
      const rdg = tr.getAttribute("data-degraded") || "?";
      if (rhf === "1") c.hf1++; else if (rhf === "0") c.hf0++; else c.hfu++;
      if (rdg === "1") c.dg1++; else if (rdg === "0") c.dg0++; else c.dgu++;
    }
    if (meta){
      meta.textContent = `Loaded ${rows.length}. has_findings: Y=${c.hf1} N=${c.hf0} U=${c.hfu} | degraded: Y=${c.dg1} N=${c.dg0} U=${c.dgu}`;
    }
  }

  function bind(root){
    const refresh = $("#vsp-runs-refresh", root);
    const limit = $("#vsp-runs-limit", root);
    const hf = $("#vsp-runs-filter-hf", root);
    const dg = $("#vsp-runs-filter-deg", root);
    const q  = $("#vsp-runs-search", root);

    if (refresh) refresh.addEventListener("click", () => loadRuns(root).catch(e => console.error("[VSP_RUNS] load error", e)));
    if (limit) limit.addEventListener("change", () => loadRuns(root).catch(e => console.error("[VSP_RUNS] load error", e)));

    const onFilter = () => applyFilters(root);
    if (hf) hf.addEventListener("change", onFilter);
    if (dg) dg.addEventListener("change", onFilter);
    if (q)  q.addEventListener("input", onFilter);
  }

  function init(){
    const root = ensureRunsRoot();
    ensureUI(root);
    bind(root);
    loadRuns(root).catch(e => console.error("[VSP_RUNS] init load error", e));
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
JS

node --check "$F1" >/dev/null && echo "[OK] runs JS syntax OK"


echo
echo "== [B] PATCH SETTINGS: Commercial Operational Policy section =="
F2=""
for cand in \
  "static/js/vsp_settings_tab_v1.js" \
  "static/js/vsp_settings_tab_v2.js" \
  "static/js/vsp_settings_tab.js"
do
  if [ -f "$cand" ]; then F2="$cand"; break; fi
done
[ -n "$F2" ] || { echo "[ERR] missing settings js (vsp_settings_tab_v1.js/v2.js)"; exit 3; }

cp -f "$F2" "$F2.bak_policy_${TS}" && echo "[BACKUP] $F2.bak_policy_${TS}"

python3 - <<PY
from pathlib import Path
import re

p = Path("$F2")
s = p.read_text(encoding="utf-8", errors="replace")

BEGIN = "/* VSP_SETTINGS_COMMERCIAL_POLICY_V1_BEGIN */"
END   = "/* VSP_SETTINGS_COMMERCIAL_POLICY_V1_END */"

block = r'''%s
(function(){
  'use strict';

  const API_SETTINGS = "/api/vsp/settings_v1";
  const API_DASH     = "/api/vsp/dashboard_v3";
  const API_ISO      = "/api/vsp/iso_controls_v1";

  function $(sel, root){ return (root||document).querySelector(sel); }
  function esc(s){ return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function toYesNo(v){
    if (v === true) return "ON";
    if (v === false) return "OFF";
    if (v is None) return "UNKNOWN";
    return String(v);
  }

  function findSettingsRoot(){
    return (
      $("#tab-settings") ||
      $("#vsp4-settings") ||
      $("[data-tab='settings']") ||
      $("#settings") ||
      document.body
    );
  }

  function ensurePolicyBlock(root){
    let host = $("#vsp-settings-commercial-policy", root);
    if (!host){
      host = document.createElement("div");
      host.id = "vsp-settings-commercial-policy";
      host.className = "vsp-card";
      host.style.marginTop = "12px";
      // Append near top of settings tab (but after existing config header if present)
      const firstCard = root.querySelector(".vsp-card");
      if (firstCard and firstCard.parentNode == root):
        root.insertBefore(host, firstCard.nextSibling)
      else:
        root.appendChild(host)
    }
    return host;
  }

  async function safeJson(url){
    try{
      const r = await fetch(url, { credentials: "same-origin" });
      const j = await r.json().catch(() => ({}));
      return j || {};
    }catch(e){
      return {};
    }
  }

  function render(host, ctx){
    const tools = [
      {name:"Bandit", lane:"SAST (Python)"},
      {name:"Semgrep", lane:"SAST (multi-lang)"},
      {name:"Gitleaks", lane:"Secrets"},
      {name:"KICS", lane:"IaC"},
      {name:"Trivy", lane:"Vuln (FS)"},
      {name:"Syft", lane:"SBOM"},
      {name:"Grype", lane:"Vuln (SBOM)"},
      {name:"CodeQL", lane:"SAST (deep)"},
    ];

    const mode = ctx.mode || {};
    const flags = ctx.flags || {};
    const endpoints = [
      {k:"Runs index", v:"/api/vsp/runs_index_v3_fs_resolved"},
      {k:"Run status", v:"/api/vsp/run_status_v2/<rid>"},
      {k:"Artifacts index", v:"/api/vsp/artifacts_index_v1/<rid>"},
      {k:"Export", v:"/api/vsp/run_export_v3/<rid>?fmt=html|zip|pdf"},
      {k:"Dashboard KPI", v:"/api/vsp/dashboard_v3"},
      {k:"Rule overrides", v:"/api/vsp/rule_overrides_v1"},
    ];

    host.innerHTML = `
      <div style="display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap;">
        <div>
          <h3 style="margin:0 0 6px 0;">Commercial Operational Policy</h3>
          <div style="opacity:.8;">Governance + runtime rules for 8-tool pipeline, timeouts, degraded behavior, exports & compliance notes.</div>
        </div>
        <span class="vsp-pill">P1 Commercial</span>
      </div>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">8 Tools</h4>
      <div class="vsp-grid" style="display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:10px;">
        ${tools.map(t => `
          <div class="vsp-card vsp-card--tight">
            <div style="font-weight:700;">${esc(t.name)}</div>
            <div style="opacity:.85;">${esc(t.lane)}</div>
          </div>
        `).join("")}
      </div>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">Timeout & Degraded Policy</h4>
      <ul style="margin:0; padding-left:18px; opacity:.92; line-height:1.5;">
        <li><b>Timeout</b>: tool/lane vượt ngưỡng hoặc missing tool ⇒ lane được đánh dấu <b>DEGRADED</b> (pipeline không treo).</li>
        <li><b>Degraded</b> nghĩa là: có artifact/log cho thấy tool không hoàn tất đúng chuẩn, nhưng run vẫn kết thúc và ghi trạng thái.</li>
        <li><b>Commercial KPI</b>: dashboard phải hiển thị “effective” vs “degraded” (bạn vừa patch KPI bar).</li>
        <li><b>Gating</b>: có thể cho phép “soft pass” theo policy, nhưng phải ghi rõ <b>degraded reason</b> trong run status/log.</li>
      </ul>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">Current Modes / Flags</h4>
      <div class="vsp-grid" style="display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:10px;">
        <div class="vsp-card vsp-card--tight">
          <div style="font-weight:700;">Runtime</div>
          <div style="opacity:.9; margin-top:6px;">
            <div>FS_FALLBACK: <b>${esc(flags.FS_FALLBACK ?? "UNKNOWN")}</b></div>
            <div>EXPORT_FORCE_BIND: <b>${esc(flags.EXPORT_FORCE_BIND ?? "UNKNOWN")}</b></div>
            <div>OVERRIDES_ENABLED: <b>${esc(flags.OVERRIDES_ENABLED ?? "UNKNOWN")}</b></div>
          </div>
        </div>
        <div class="vsp-card vsp-card--tight">
          <div style="font-weight:700;">Tool Execution Mode</div>
          <div style="opacity:.9; margin-top:6px;">
            <div>KICS: <b>${esc(mode.kics ?? "docker/local ?")}</b></div>
            <div>CodeQL: <b>${esc(mode.codeql ?? "local ?")}</b></div>
            <div>Trivy/Syft/Grype: <b>${esc(mode.sbom ?? "local ?")}</b></div>
          </div>
        </div>
      </div>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">Exports & Artifacts</h4>
      <div style="opacity:.92; line-height:1.5;">
        <div><b>Artifacts location</b>: theo <code>ci_run_dir</code> trong <code>run_status_v2</code> (mỗi run có folder riêng).</div>
        <div><b>Exports</b>: HTML/ZIP/PDF lấy theo endpoint export; PDF có thể bật/tắt theo policy.</div>
      </div>

      <div style="margin-top:10px; overflow:auto;">
        <table class="vsp-table" style="width:100%;">
          <thead><tr><th style="width:180px;">Item</th><th>Endpoint</th></tr></thead>
          <tbody>
            ${endpoints.map(e => `<tr><td>${esc(e.k)}</td><td><code>${esc(e.v)}</code></td></tr>`).join("")}
          </tbody>
        </table>
      </div>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">ISO 27001 Mapping Note</h4>
      <div style="opacity:.92; line-height:1.5;">
        ISO mapping trong report/dashboard là <b>hỗ trợ quản trị & traceability</b> (không phải chứng nhận).
        Nếu hệ thống có <code>iso_controls</code>, report có thể render coverage matrix theo controls đó.
      </div>
    `;
  }

  async function init(){
    const root = findSettingsRoot();
    const host = ensurePolicyBlock(root);

    // best-effort extract flags/mode from settings/dashboard
    const settings = await safeJson(API_SETTINGS);
    const dash = await safeJson(API_DASH);
    const iso = await safeJson(API_ISO);

    const flags = {
      FS_FALLBACK: settings.fs_fallback ?? settings.FS_FALLBACK ?? dash.fs_fallback ?? "UNKNOWN",
      EXPORT_FORCE_BIND: settings.export_force_bind ?? settings.EXPORT_FORCE_BIND ?? "UNKNOWN",
      OVERRIDES_ENABLED: settings.overrides_enabled ?? settings.OVERRIDES_ENABLED ?? "UNKNOWN",
    };

    const mode = {
      kics: settings.kics_mode ?? settings.KICS_MODE ?? "UNKNOWN",
      codeql: settings.codeql_mode ?? settings.CODEQL_MODE ?? "UNKNOWN",
      sbom: settings.sbom_mode ?? "UNKNOWN",
    };

    render(host, { flags, mode, iso });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
%s
''' % (BEGIN, END)

if BEGIN in s and END in s:
  s = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), block, s, flags=re.S)
else:
  s = s.rstrip() + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected commercial policy block into", str(p))
PY

node --check "$F2" >/dev/null && echo "[OK] settings JS syntax OK"

echo
echo "[DONE] P1 commercial UI patches applied: Runs JSON filters + Settings policy"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
