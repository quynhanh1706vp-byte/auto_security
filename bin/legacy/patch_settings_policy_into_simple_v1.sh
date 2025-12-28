#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_settings_tab_simple_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_policy_inject_${TS}" && echo "[BACKUP] $F.bak_policy_inject_${TS}"

# remove previous injected blocks if any
perl -0777 -i -pe 's@/\*\s*VSP_SETTINGS_COMMERCIAL_POLICY_SIMPLE_V1_BEGIN\s*\*/.*?/\*\s*VSP_SETTINGS_COMMERCIAL_POLICY_SIMPLE_V1_END\s*\*/@@sg' "$F"

cat >> "$F" <<'JS'

/* VSP_SETTINGS_COMMERCIAL_POLICY_SIMPLE_V1_BEGIN */
(function(){
  'use strict';

  const API_SETTINGS = "/api/vsp/settings_v1";
  const API_DASH     = "/api/vsp/dashboard_v3";

  function $(sel, root){ return (root||document).querySelector(sel); }
  function esc(s){ return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  function findSettingsRoot(){
    return (
      document.querySelector("#tab-settings") ||
      document.querySelector("#vsp4-settings") ||
      document.querySelector("[data-tab='settings']") ||
      document.querySelector("#settings") ||
      document.body
    );
  }

  function ensureHost(root){
    let host = root.querySelector("#vsp-settings-commercial-policy");
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
      <div style="opacity:.8; margin-bottom:10px;">8 tools + timeout/degraded governance + exports/artifacts + ISO note.</div>

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
        <li>Timeout/missing tool ⇒ <b>DEGRADED</b> (không treo pipeline).</li>
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
    const root = findSettingsRoot();
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
/* VSP_SETTINGS_COMMERCIAL_POLICY_SIMPLE_V1_END */

JS

node --check "$F" >/dev/null && echo "[OK] simple settings JS syntax OK"
echo "[DONE] injected policy into $F (the file actually included by vsp_dashboard_2025.html). Hard refresh Ctrl+Shift+R."
