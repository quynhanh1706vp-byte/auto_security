#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# auto-detect settings js
F2=""
for cand in \
  "static/js/vsp_settings_tab_v1.js" \
  "static/js/vsp_settings_tab_v2.js" \
  "static/js/vsp_settings_tab.js"
do
  if [ -f "$cand" ]; then F2="$cand"; break; fi
done
[ -n "$F2" ] || { echo "[ERR] missing settings js"; exit 2; }

echo "== PATCH SETTINGS POLICY FIX V2 =="
echo "[FILE] $F2"

# restore from latest backup if exists (the previous run already made one)
BK="$(ls -1t "${F2}.bak_policy_"* 2>/dev/null | head -n1 || true)"
if [ -n "${BK:-}" ] && [ -f "$BK" ]; then
  cp -f "$BK" "$F2"
  echo "[RESTORE] from $BK"
fi

# remove previous injected block if any
python3 - <<'PY'
from pathlib import Path
import re, os
p = Path(os.environ.get("F2",""))
if not p.exists():
  raise SystemExit(0)
s = p.read_text(encoding="utf-8", errors="replace")
BEGIN = "/* VSP_SETTINGS_COMMERCIAL_POLICY_V2_BEGIN */"
END   = "/* VSP_SETTINGS_COMMERCIAL_POLICY_V2_END */"
if BEGIN in s and END in s:
  s = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), "", s, flags=re.S)
  p.write_text(s.rstrip()+"\n", encoding="utf-8")
PY
F2="$F2" python3 - <<'PY'
# (keep env in sync for the snippet above in some shells)
PY

# append safe JS block (no python templating; no bash expansion)
if ! grep -q "VSP_SETTINGS_COMMERCIAL_POLICY_V2_BEGIN" "$F2"; then
  cat >> "$F2" <<'JS'

/* VSP_SETTINGS_COMMERCIAL_POLICY_V2_BEGIN */
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
      // try insert near top (after first card), else append
      const firstCard = root.querySelector(".vsp-card");
      if (firstCard && firstCard.parentNode === root && firstCard.nextSibling){
        root.insertBefore(host, firstCard.nextSibling);
      } else if (firstCard && firstCard.parentNode === root){
        root.appendChild(host);
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
      ["Runs index",   "/api/vsp/runs_index_v3_fs_resolved"],
      ["Run status",   "/api/vsp/run_status_v2/<rid>"],
      ["Artifacts",    "/api/vsp/artifacts_index_v1/<rid>"],
      ["Export",       "/api/vsp/run_export_v3/<rid>?fmt=html|zip|pdf"],
      ["Dashboard KPI","/api/vsp/dashboard_v3"],
      ["Overrides",    "/api/vsp/rule_overrides_v1"],
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
      kics:  String(pick(settings, ["kics_mode","KICS_MODE"]) ?? "UNKNOWN"),
      codeql:String(pick(settings, ["codeql_mode","CODEQL_MODE"]) ?? "UNKNOWN"),
      sbom:  String(pick(settings, ["sbom_mode","SBOM_MODE"]) ?? "UNKNOWN"),
    };

    render(host, { flags, mode });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
/* VSP_SETTINGS_COMMERCIAL_POLICY_V2_END */

JS
fi

node --check "$F2" >/dev/null && echo "[OK] settings JS syntax OK"
echo "[DONE] Settings commercial policy injected. Hard refresh (Ctrl+Shift+R)."
