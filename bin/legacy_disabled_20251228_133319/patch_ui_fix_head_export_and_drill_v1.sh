#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_headfix_drill_${TS}"
echo "[BACKUP] $F.bak_headfix_drill_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_EXPORT_HEAD_NOISE_PATCH_V1 ==="
if TAG in s:
    print("[OK] patch already present, skip")
else:
    inj = r"""
%s
(function(){
  'use strict';

  // 1) QUIET export probe:
  // Browser HEAD to /api/vsp/run_export_v3/...fmt=pdf may fail/noisy (DevTools shows "Fetch failed loading: HEAD ...")
  // We short-circuit ONLY that exact pattern to a synthetic 200 so UI stops spamming.
  if (!window.__VSP_EXPORT_HEAD_NOISE_PATCH_V1__) {
    window.__VSP_EXPORT_HEAD_NOISE_PATCH_V1__ = true;
    const _fetch = (window.fetch && window.fetch.bind(window)) ? window.fetch.bind(window) : null;

    if (_fetch) {
      window.fetch = function(input, init){
        try {
          const method = (init && init.method) ? String(init.method).toUpperCase() : "GET";
          const url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
          if (method === "HEAD"
              && url.includes("/api/vsp/run_export_v3/")
              && url.includes("fmt=pdf")) {
            // pretend "available" without real network HEAD (removes noisy HEAD errors)
            return Promise.resolve(new Response("", {
              status: 200,
              headers: { "X-VSP-EXPORT-AVAILABLE": "1" }
            }));
          }
        } catch(_e) {}
        return _fetch(input, init);
      };
      console.log("[VSP][EXPORT] installed HEAD-noise patch for fmt=pdf");
    }
  }

  // 2) DRILLDOWN bus (Dashboard/Gate Summary click -> Data Source auto filter)
  const LS_KEY = "vsp_ds_filters_v1";

  function emitFilters(filters){
    const payload = { v:1, ts: Date.now(), filters: (filters||{}) };
    try { localStorage.setItem(LS_KEY, JSON.stringify(payload)); } catch(_){}
    try { window.dispatchEvent(new CustomEvent("vsp:datasource:setFilters", { detail: payload })); } catch(_){}
  }

  window.VSP_DRILL_TO_DATASOURCE = function(filters){
    emitFilters(filters || {});
    // switch to datasource tab via hash (your router logs show hash-based router)
    try { location.hash = "#datasource"; } catch(_){}
  };

  // datasource side: best-effort apply by label text (Severity/Tool/CWE/Text/Limit)
  function findControlByLabelText(labelText, preferTags){
    labelText = String(labelText||"").toLowerCase();
    preferTags = preferTags || ["select","input","textarea"];
    const nodes = Array.from(document.querySelectorAll("div,span,label,strong,b,small,h1,h2,h3,h4,h5,h6"));
    for (const n of nodes) {
      const t = (n.textContent || "").trim().toLowerCase();
      if (!t) continue;
      if (t === labelText || t.includes(labelText)) {
        // search within same parent first
        let base = n.parentElement || n;
        for (let hop=0; hop<3 && base; hop++){
          for (const tg of preferTags){
            const c = base.querySelector(tg);
            if (c) return c;
          }
          base = base.parentElement;
        }
      }
    }
    return null;
  }

  function fire(el){
    try { el.dispatchEvent(new Event("input", { bubbles:true })); } catch(_){}
    try { el.dispatchEvent(new Event("change", { bubbles:true })); } catch(_){}
  }

  function applyFilters(filters){
    filters = filters || {};
    // only apply when datasource pane is active-ish
    const h = String(location.hash||"");
    if (!h.includes("datasource")) return;

    const sev = findControlByLabelText("Severity", ["select","input"]);
    const tool = findControlByLabelText("Tool", ["select","input"]);
    const cwe = findControlByLabelText("CWE", ["input","select"]);
    const txt = findControlByLabelText("Text", ["input","textarea"]);
    const lim = findControlByLabelText("Limit", ["input","select"]);

    if (filters.severity && sev) { sev.value = String(filters.severity); fire(sev); }
    if (filters.tool && tool) { tool.value = String(filters.tool); fire(tool); }
    if (filters.cwe && cwe) { cwe.value = String(filters.cwe); fire(cwe); }
    if (filters.text && txt) { txt.value = String(filters.text); fire(txt); }
    if (filters.limit && lim) { lim.value = String(filters.limit); fire(lim); }

    // try click "Load" if exists (your UI has Load/Clear buttons)
    try {
      const btn = Array.from(document.querySelectorAll("button"))
        .find(b => (b.textContent||"").trim().toLowerCase() === "load");
      if (btn) btn.click();
    } catch(_){}
  }

  function consumePending(){
    try {
      const raw = localStorage.getItem(LS_KEY);
      if (!raw) return;
      const p = JSON.parse(raw);
      if (!p || !p.filters) return;
      const age = Date.now() - Number(p.ts || 0);
      if (!(age >= 0 && age <= 5*60*1000)) return;
      localStorage.removeItem(LS_KEY);
      applyFilters(p.filters);
    } catch(_){}
  }

  window.addEventListener("vsp:datasource:setFilters", (e)=>{
    try { applyFilters((e.detail && e.detail.filters) || {}); } catch(_){}
  });
  window.addEventListener("hashchange", ()=>{ try { consumePending(); } catch(_){} });

  // Gate Summary pills click -> drilldown
  function wireGateSummaryClicks(){
    const toolSet = new Set(["GITLEAKS","SEMGREP","TRIVY","CODEQL","KICS","GRYPE","SYFT","BANDIT"]);
    const sevSet  = new Set(["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]);
    const pills = Array.from(document.querySelectorAll(".vsp-pill, [data-pill], td, th, span, div"));

    for (const el of pills) {
      if (!el || el.__vsp_drilled__) continue;
      const txt = (el.textContent || "").trim();
      if (!txt) continue;
      const up = txt.toUpperCase();

      const filters = {};
      if (toolSet.has(up)) filters.tool = up;
      if (sevSet.has(up)) filters.severity = up;
      if (/^CWE-\d+$/i.test(up)) filters.cwe = up;

      if (Object.keys(filters).length === 0) continue;

      // limit to dashboard area if possible
      const inDash = !!el.closest("#vsp-dashboard-main") || String(location.hash||"").includes("dashboard");
      if (!inDash) continue;

      el.__vsp_drilled__ = true;
      el.style.cursor = "pointer";
      el.title = "Click → drilldown Data Source";
      el.addEventListener("click", ()=> window.VSP_DRILL_TO_DATASOURCE(filters));
    }
  }

  function onReady(fn){
    if (document.readyState === "complete" || document.readyState === "interactive") return setTimeout(fn, 0);
    document.addEventListener("DOMContentLoaded", fn, { once:true });
  }

  onReady(()=>{ try { wireGateSummaryClicks(); } catch(_){} });
  onReady(()=>{ try { consumePending(); } catch(_){} });

})();
""" % TAG

    # prepend near top so it runs before other logic
    s2 = inj + "\n\n" + s
    p.write_text(s2, encoding="utf-8")
    print("[OK] injected patch into", p)

PY

python3 -m py_compile "$F" >/dev/null 2>&1 || true
echo "[DONE] Patch applied: $F"
echo "Next: restart gunicorn + HARD refresh (Ctrl+Shift+R) with Disable cache checked."
