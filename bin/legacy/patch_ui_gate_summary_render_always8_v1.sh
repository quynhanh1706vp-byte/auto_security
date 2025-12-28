#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_gate8_${TS}"
echo "[BACKUP] $F.bak_gate8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

TAG="// === VSP_UI_GATE_SUMMARY_ALWAYS8_V1 ==="
if TAG in s:
    print("[OK] already patched, skip")
    raise SystemExit(0)

patch = r"""
%s
(function(){
  'use strict';

  const CANON = ["SEMGREP","GITLEAKS","TRIVY","CODEQL","KICS","GRYPE","SYFT","BANDIT"];

  function esc(s){ return String(s||"").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c])); }
  function pick(obj, keys){ for(const k of keys){ if(obj && obj[k] != null) return obj[k]; } return null; }

  function normalizeToolEntry(t, entry){
    entry = entry || {};
    const verdict = String(pick(entry, ["verdict","status"]) || "NOT_RUN").toUpperCase();
    const total = Number(pick(entry, ["total","n","count"]) || 0) || 0;
    return { tool: t, verdict, total };
  }

  function buildListFromStatus(status){
    status = status || {};
    const tools = status.tools || null;
    const order = status.tools_order || CANON;
    const out = [];

    // Prefer .tools (new backend)
    if (tools && typeof tools === "object") {
      for (const t of order) out.push(normalizeToolEntry(t, tools[t]));
      return out;
    }

    // Fallback: legacy run_gate_summary
    const gs = status.run_gate_summary || {};
    if (gs && typeof gs === "object") {
      for (const t of order) out.push(normalizeToolEntry(t, gs[t]));
      return out;
    }

    // Last fallback: legacy 4 tools flat fields
    const legacyMap = {
      "SEMGREP": { verdict: status.semgrep_verdict, total: status.semgrep_total },
      "GITLEAKS": { verdict: status.gitleaks_verdict, total: status.gitleaks_total },
      "TRIVY": { verdict: status.trivy_verdict, total: status.trivy_total },
      "CODEQL": { verdict: status.codeql_verdict, total: status.codeql_total }
    };
    for (const t of CANON) out.push(normalizeToolEntry(t, legacyMap[t] || {}));
    return out;
  }

  function badgeClass(v){
    v = String(v||"").toUpperCase();
    if (v === "RED" || v === "FAIL" || v === "CRITICAL") return "vsp-badge vsp-badge-red";
    if (v === "AMBER" || v === "WARN" || v === "HIGH") return "vsp-badge vsp-badge-amber";
    if (v === "GREEN" || v === "OK" || v === "PASS") return "vsp-badge vsp-badge-green";
    if (v === "DEGRADED") return "vsp-badge vsp-badge-amber";
    return "vsp-badge vsp-badge-gray";
  }

  function renderGateSummaryAlways8(status){
    const host = document.querySelector("#vsp-gate-summary, #gate-summary, [data-vsp='gate-summary']");
    if (!host) return false;

    const list = buildListFromStatus(status);
    const rows = list.map(x => {
      const t = esc(x.tool);
      const v = esc(x.verdict);
      const n = esc(x.total);
      return `
        <div class="vsp-gs-row" data-vsp-drill-tool="${t}">
          <div class="vsp-gs-tool vsp-pill" data-vsp-drill-tool="${t}">${t}</div>
          <div class="${badgeClass(v)} vsp-pill" data-vsp-drill-tool="${t}">${v}</div>
          <div class="vsp-gs-total vsp-pill" data-vsp-drill-tool="${t}">${n}</div>
        </div>
      `;
    }).join("");

    host.innerHTML = `
      <div class="vsp-gs-head">
        <div class="vsp-gs-col">TOOL</div>
        <div class="vsp-gs-col">VERDICT</div>
        <div class="vsp-gs-col">TOTAL</div>
      </div>
      <div class="vsp-gs-body">${rows}</div>
    `;

    return true;
  }

  // Hook: if your code already has a function that receives status JSON, we wrap it.
  function wrapStatusConsumer(){
    const names = ["VSP_UI_APPLY_STATUS", "vspApplyStatus", "renderRunStatus", "updateStatusUI"];
    for (const n of names){
      if (typeof window[n] === "function" && !window[n].__vsp_wrapped__) {
        const orig = window[n];
        window[n] = function(status){
          try { renderGateSummaryAlways8(status); } catch(_){}
          return orig.apply(this, arguments);
        };
        window[n].__vsp_wrapped__ = true;
        console.log("[VSP][UI] wrapped status consumer:", n);
        return;
      }
    }
    // fallback: poll global last status if exists
    try {
      if (window.VSP_LAST_STATUS && !window.__VSP_GATE8_TICK__) {
        window.__VSP_GATE8_TICK__ = setInterval(()=>{ try { renderGateSummaryAlways8(window.VSP_LAST_STATUS); } catch(_){} }, 1200);
      }
    } catch(_){}
  }

  // Ensure a container exists (non-breaking)
  function ensureHost(){
    let host = document.querySelector("#vsp-gate-summary");
    if (host) return;
    const dash = document.querySelector("#vsp-dashboard-main");
    if (!dash) return;
    host = document.createElement("div");
    host.id = "vsp-gate-summary";
    host.style.marginTop = "10px";
    dash.appendChild(host);
  }

  function onReady(fn){
    if (document.readyState === "complete" || document.readyState === "interactive") return setTimeout(fn, 0);
    document.addEventListener("DOMContentLoaded", fn, { once:true });
  }

  onReady(()=>{ try { ensureHost(); } catch(_){} });
  onReady(()=>{ try { wrapStatusConsumer(); } catch(_){} });

})();
""" % TAG

# Append patch to end (safe)
s2 = s + "\n\n" + patch + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended gate summary always-8 renderer")
PY

echo "[DONE] UI patch applied: $F"
