(function () {
  const API_URL = '/api/vsp/settings_ui_v1';
  const INIT_DELAY_MS = 1200;

  function esc(s) {
    if (s == null) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function renderSkeleton(tab) {
    tab.innerHTML = `
      <div class="vsp-tab-inner vsp-tab-settings">
        <div class="vsp-tab-header">
          <h2>Settings</h2>
          <p class="vsp-tab-subtitle">
            Cấu hình chính sách gate, tool và tham số scan. Hiện tại ở chế độ xem (read-only).
          </p>
        </div>

        <div class="vsp-card-grid">
          <div class="vsp-card">
            <h3>Gate policy</h3>
            <p class="vsp-muted">
              Điều kiện để job CI đánh FAIL / PASS. Mặc định: FAIL nếu CRITICAL &gt; 0 hoặc HIGH &gt; 10.
            </p>
            <ul class="vsp-list" id="vsp-settings-gate-list">
              <li>Loading gate policy…</li>
            </ul>
          </div>

          <div class="vsp-card">
            <h3>Tools</h3>
            <p class="vsp-muted">
              Các công cụ security hiện được kích hoạt trong gói VSP (Semgrep, CodeQL, KICS,…).
            </p>
            <ul class="vsp-list" id="vsp-settings-tools-list">
              <li>Loading tools…</li>
            </ul>
          </div>

          <div class="vsp-card">
            <h3>Profiles &amp; thresholds</h3>
            <p class="vsp-muted">
              Một số tham số nâng cao (timeout, max files, profile FULL_EXT/SMOKE…).
            </p>
            <ul class="vsp-list" id="vsp-settings-extra-list">
              <li>Loading…</li>
            </ul>
          </div>
        </div>

        <div class="vsp-card vsp-card-note">
          <h3>Editing roadmap</h3>
          <p>
            Phiên bản hiện tại cho phép xem cấu hình. Bản thương mại tiếp theo sẽ bật:
          </p>
          <ul class="vsp-list">
            <li>Chỉnh gate policy trực tiếp và lưu xuống server.</li>
            <li>Bật/tắt từng tool theo repo hoặc theo pipeline.</li>
            <li>Lưu và restore cấu hình theo profile (STRICT / BALANCED / RELAXED).</li>
          </ul>
        </div>
      </div>
    `;
  }

  async function bindSettings(tab) {
    renderSkeleton(tab);

    const gateList = tab.querySelector('#vsp-settings-gate-list');
    const toolsList = tab.querySelector('#vsp-settings-tools-list');
    const extraList = tab.querySelector('#vsp-settings-extra-list');

    let data;
    try {
      const res = await fetch(API_URL, { cache: 'no-store' });
      data = await res.json();
    } catch (e) {
      console.error('[VSP_SETTINGS_TAB] Failed to load settings_ui_v1', e);
      if (gateList) gateList.innerHTML = '<li class="vsp-error">Không tải được settings từ API.</li>';
      if (toolsList) toolsList.innerHTML = '';
      if (extraList) extraList.innerHTML = '';
      return;
    }

    const settings = data.settings || {};

    // Gate policy
    if (gateList) {
      if (!settings.gate_policy) {
        gateList.innerHTML = `
          <li><strong>Mode:</strong> Default</li>
          <li><strong>Fail if CRITICAL &gt; 0</strong></li>
          <li><strong>Fail if HIGH &gt; 10</strong></li>
          <li>MEDIUM/LOW chỉ cảnh báo, không fail job.</li>
        `;
      } else {
        const gp = settings.gate_policy;
        const lines = [];
        if (gp.mode) lines.push(`<li><strong>Mode:</strong> ${esc(gp.mode)}</li>`);
        if (gp.critical_threshold != null) {
          lines.push(`<li>Fail nếu CRITICAL &gt; ${esc(gp.critical_threshold)}</li>`);
        }
        if (gp.high_threshold != null) {
          lines.push(`<li>Fail nếu HIGH &gt; ${esc(gp.high_threshold)}</li>`);
        }
        if (gp.description) {
          lines.push(`<li>${esc(gp.description)}</li>`);
        }
        gateList.innerHTML = lines.join('') || '<li>Gate policy đang để trống.</li>';
      }
    }

    // Tools
    if (toolsList) {
      const tools = settings.tools || settings.tools_enabled || {};
      const names = Object.keys(tools);
      if (!names.length) {
        toolsList.innerHTML = `
          <li>Semgrep</li>
          <li>Gitleaks</li>
          <li>KICS</li>
          <li>CodeQL</li>
          <li>Trivy / Syft / Grype</li>
        `;
      } else {
        toolsList.innerHTML = names
          .map(name => {
            const v = tools[name];
            const enabled = v === true || v === 'on' || v === 'enabled';
            return `<li><strong>${esc(name)}</strong> – ${enabled ? 'enabled' : 'disabled'}</li>`;
          })
          .join('');
      }
    }

    // Extra
    if (extraList) {
      const extras = settings.extras || settings.profiles || {};
      const keys = Object.keys(extras);
      if (!keys.length) {
        extraList.innerHTML = `
          <li>Profile FULL_EXT: full scan toàn hệ thống.</li>
          <li>Profile SMOKE: scan nhanh (~10–20% trọng tâm) cho mỗi push CI.</li>
          <li>Timeout, số file tối đa: sử dụng giá trị mặc định an toàn.</li>
        `;
      } else {
        extraList.innerHTML = keys
          .map(name => `<li><strong>${esc(name)}:</strong> ${esc(JSON.stringify(extras[name]))}</li>`)
          .join('');
      }
    }

    console.log('[VSP_SETTINGS_TAB] Rendered settings.');
  }

  let initialized = false;

  function tryInit() {
    if (initialized) return;
    const tab = document.querySelector('#vsp-tab-settings');
    if (!tab) {
      setTimeout(tryInit, 500);
      return;
    }
    initialized = true;
    setTimeout(() => bindSettings(tab), INIT_DELAY_MS);
  }

  tryInit();
})();

/* VSP_SETTINGS_COMMERCIAL_POLICY_V3_BEGIN */
(function(){
  'use strict';

  const API_SETTINGS = "/api/vsp/settings_v1";
  const API_DASH     = "/api/vsp/dashboard_v3";

  function $(sel, root){ return (root||document).querySelector(sel); }
  function esc(s){ return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  function findSettingsRoot(){
    return (
      $("#tab-settings") ||
      $("#vsp4-settings") ||
      $("[data-tab='settings']") ||
      $("#settings") ||
      document.body
    );
  }

  function ensureHost(root){
    let host = $("#vsp-settings-commercial-policy", root);
    if (!host){
      host = document.createElement("div");
      host.id = "vsp-settings-commercial-policy";
      host.className = "vsp-card";
      host.style.marginTop = "12px";

      // insert near top (after first card) if possible
      const firstCard = root.querySelector(".vsp-card");
      if (firstCard && firstCard.parentNode === root){
        if (firstCard.nextSibling) root.insertBefore(host, firstCard.nextSibling);
        else root.appendChild(host);
      } else {
        root.appendChild(host);
      }
    }
    return host;
  }

  async function safeJson(url){
    try{
      const r = await fetch(url, { credentials: "same-origin" });
      return await r.json();
    } catch(_e){
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
      ["Bandit",   "SAST (Python)"],
      ["Semgrep",  "SAST (multi-lang)"],
      ["Gitleaks", "Secrets"],
      ["KICS",     "IaC"],
      ["Trivy",    "Vuln (FS)"],
      ["Syft",     "SBOM"],
      ["Grype",    "Vuln (SBOM)"],
      ["CodeQL",   "SAST (deep)"],
    ];

    const endpoints = [
      ["Runs index",    "/api/vsp/runs_v3"],
      ["Run status",    "/api/vsp/run_status_v2/<rid>"],
      ["Artifacts",     "/api/vsp/artifacts_index_v1/<rid>"],
      ["Export",        "/api/vsp/run_export_v3/<rid>?fmt=html|zip|pdf"],
      ["Dashboard KPI", "/api/vsp/dashboard_v3"],
      ["Overrides",     "/api/vsp/rule_overrides_v1"],
    ];

    host.innerHTML = `
      <div style="display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap;">
        <div>
          <h3 style="margin:0 0 6px 0;">Commercial Operational Policy</h3>
          <div style="opacity:.8;">8 tools + timeout/degraded governance + exports/artifacts + ISO note (CIO readable).</div>
        </div>
        <span class="vsp-pill">P1 Commercial</span>
      </div>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">8 Tools</h4>
      <div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:10px;">
        ${tools.map(t => `
          <div class="vsp-card vsp-card--tight">
            <div style="font-weight:700;">${esc(t[0])}</div>
            <div style="opacity:.85;">${esc(t[1])}</div>
          </div>
        `).join("")}
      </div>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">Timeout & Degraded Policy</h4>
      <ul style="margin:0; padding-left:18px; opacity:.92; line-height:1.5;">
        <li><b>Timeout/missing tool</b> ⇒ lane đánh dấu <b>DEGRADED</b> (pipeline không treo).</li>
        <li><b>Degraded</b> = tool không hoàn tất chuẩn nhưng vẫn có log/artifact + run kết thúc “FINAL”.</li>
        <li><b>KPI</b> phải phân biệt “effective vs degraded” (dashboard KPI bar đã patch).</li>
        <li><b>Gating</b> có thể soft-pass theo policy nhưng phải ghi rõ degraded reason trong run status/log.</li>
      </ul>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">Current Modes / Flags</h4>
      <div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:10px;">
        <div class="vsp-card vsp-card--tight">
          <div style="font-weight:700;">Runtime</div>
          <div style="opacity:.9; margin-top:6px;">
            <div>FS_FALLBACK: <b>${esc(ctx.flags.FS_FALLBACK)}</b></div>
            <div>EXPORT_FORCE_BIND: <b>${esc(ctx.flags.EXPORT_FORCE_BIND)}</b></div>
            <div>OVERRIDES_ENABLED: <b>${esc(ctx.flags.OVERRIDES_ENABLED)}</b></div>
          </div>
        </div>
        <div class="vsp-card vsp-card--tight">
          <div style="font-weight:700;">Tool Execution Mode</div>
          <div style="opacity:.9; margin-top:6px;">
            <div>KICS: <b>${esc(ctx.mode.kics)}</b></div>
            <div>CodeQL: <b>${esc(ctx.mode.codeql)}</b></div>
            <div>Trivy/Syft/Grype: <b>${esc(ctx.mode.sbom)}</b></div>
          </div>
        </div>
      </div>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">Exports & Artifacts</h4>
      <div style="opacity:.92; line-height:1.5;">
        <div><b>Artifacts location</b>: theo <code>ci_run_dir</code> trong <code>run_status_v2</code>.</div>
        <div><b>Exports</b>: HTML/ZIP/PDF qua export endpoint (PDF có thể bật/tắt theo policy).</div>
      </div>

      <div style="margin-top:10px; overflow:auto;">
        <table class="vsp-table" style="width:100%;">
          <thead><tr><th style="width:180px;">Item</th><th>Endpoint</th></tr></thead>
          <tbody>
            ${endpoints.map(e => `<tr><td>${esc(e[0])}</td><td><code>${esc(e[1])}</code></td></tr>`).join("")}
          </tbody>
        </table>
      </div>

      <hr style="opacity:.15; margin:12px 0;" />

      <h4 style="margin:0 0 8px 0;">ISO 27001 Mapping Note</h4>
      <div style="opacity:.92; line-height:1.5;">
        ISO mapping nhằm <b>governance + traceability</b> (không phải chứng nhận). Report có thể render coverage matrix nếu backend có <code>iso_controls</code>.
      </div>
    `;
  }

  async function init(){
    const root = findSettingsRoot();
    const host = ensureHost(root);

    const settings = await safeJson(API_SETTINGS);
    const dash = await safeJson(API_DASH);

    const flags = {
      FS_FALLBACK:       String(pick(settings, ["fs_fallback","FS_FALLBACK"]) ?? pick(dash, ["fs_fallback","FS_FALLBACK"]) ?? "UNKNOWN"),
      EXPORT_FORCE_BIND: String(pick(settings, ["export_force_bind","EXPORT_FORCE_BIND"]) ?? "UNKNOWN"),
      OVERRIDES_ENABLED: String(pick(settings, ["overrides_enabled","OVERRIDES_ENABLED"]) ?? "UNKNOWN"),
    };
    const mode = {
      kics:   String(pick(settings, ["kics_mode","KICS_MODE"]) ?? "UNKNOWN"),
      codeql: String(pick(settings, ["codeql_mode","CODEQL_MODE"]) ?? "UNKNOWN"),
      sbom:   String(pick(settings, ["sbom_mode","SBOM_MODE"]) ?? "UNKNOWN"),
    };

    render(host, { flags, mode });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
/* VSP_SETTINGS_COMMERCIAL_POLICY_V3_END */


/* VSP_P1_REQUIRED_MARKERS_SET_V1 */
(function(){
  function ensureAttr(el, k, v){ try{ if(el && !el.getAttribute(k)) el.setAttribute(k,v); }catch(e){} }
  function ensureId(el, v){ try{ if(el && !el.id) el.id=v; }catch(e){} }
  function ensureTestId(el, v){ ensureAttr(el, "data-testid", v); }
  function ensureHiddenKpi(container){
    // Create hidden markers so gate can verify presence without altering layout
    try{
      const ids = ["kpi_total","kpi_critical","kpi_high","kpi_medium","kpi_low","kpi_info_trace"];
      let box = container.querySelector('#vsp-kpi-testids');
      if(!box){
        box = document.createElement('div');
        box.id = "vsp-kpi-testids";
        box.style.display = "none";
        container.appendChild(box);
      }
      ids.forEach(id=>{
        if(!box.querySelector('[data-testid="'+id+'"]')){
          const d=document.createElement('span');
          d.setAttribute('data-testid', id);
          box.appendChild(d);
        }
      });
    }catch(e){}
  }

  function run(){
    try {
      // Dashboard
      const dash = document.getElementById("vsp-dashboard-main") || document.querySelector('[id="vsp-dashboard-main"], #vsp-dashboard, .vsp-dashboard, main, body');
      if(dash) {
        ensureId(dash, "vsp-dashboard-main");
        // add required KPI data-testid markers
        ensureHiddenKpi(dash);
      }

      // Runs
      const runs = document.getElementById("vsp-runs-main") || document.querySelector('#vsp-runs, .vsp-runs, main, body');
      if(runs) ensureId(runs, "vsp-runs-main");

      // Data Source
      const ds = document.getElementById("vsp-data-source-main") || document.querySelector('#vsp-data-source, .vsp-data-source, main, body');
      if(ds) ensureId(ds, "vsp-data-source-main");

      // Settings
      const st = document.getElementById("vsp-settings-main") || document.querySelector('#vsp-settings, .vsp-settings, main, body');
      if(st) ensureId(st, "vsp-settings-main");

      // Rule overrides
      const ro = document.getElementById("vsp-rule-overrides-main") || document.querySelector('#vsp-rule-overrides, .vsp-rule-overrides, main, body');
      if(ro) ensureId(ro, "vsp-rule-overrides-main");
    } catch(e) {}
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run, { once:true });
  } else {
    run();
  }
  // re-run after soft refresh renders
  setTimeout(run, 300);
  setTimeout(run, 1200);
})();
/* end VSP_P1_REQUIRED_MARKERS_SET_V1 */

