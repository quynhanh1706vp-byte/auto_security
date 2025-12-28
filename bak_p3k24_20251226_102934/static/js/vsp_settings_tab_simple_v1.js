(function () {
  var API_URL = "/api/vsp/settings_ui_v1";
  var hydrated = false;

  function hydratePane() {
    if (hydrated) return;
    var pane = document.getElementById("vsp-tab-settings");
    if (!pane) return;

    hydrated = true;

    pane.innerHTML =
      '<div class="vsp-section-header">' +
        '<div>' +
          '<h2 class="vsp-section-title">Settings</h2>' +
          '<p class="vsp-section-subtitle">Cấu hình SECURITY_BUNDLE (settings_ui_v1)</p>' +
        '</div>' +
      '</div>' +
      '<div class="vsp-card">' +
        '<pre id="vsp-settings-pre">{\n  "ok": false,\n  "settings": {}\n}</pre>' +
      '</div>';

    var pre = document.getElementById("vsp-settings-pre");
    if (!pre) return;

    fetch(API_URL, { cache: "no-store" })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        console.log("[VSP_SETTINGS_TAB_V2] settings_ui_v1 loaded.", data);
        try {
          pre.textContent = JSON.stringify(data, null, 2);
        } catch (e) {
          pre.textContent = "Lỗi format JSON settings_ui_v1.";
        }
      })
      .catch(function (err) {
        console.error("[VSP_SETTINGS_TAB_V2] Failed to load settings_ui_v1:", err);
        pre.textContent = "Lỗi gọi API settings_ui_v1.";
      });
  }

  window.vspInitSettingsTab = hydratePane;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydratePane);
  } else {
    hydratePane();
  }
})();




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
        <div><code>/api/vsp/runs_v3</code></div>
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

