#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

DASH_JS="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$DASH_JS" ] || { echo "[ERR] missing $DASH_JS"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$DASH_JS" "$DASH_JS.bak_drill_export_${TS}"
echo "[BACKUP] $DASH_JS.bak_drill_export_${TS}"

# try locate datasource js (best effort)
DS_JS=""
for f in static/js/*datasource* static/js/*data_source* static/js/*ds*tab*; do
  if [ -f "$f" ]; then DS_JS="$f"; break; fi
done

if [ -n "$DS_JS" ] && [ -f "$DS_JS" ]; then
  cp -f "$DS_JS" "$DS_JS.bak_drill_export_${TS}"
  echo "[BACKUP] $DS_JS.bak_drill_export_${TS}"
else
  echo "[WARN] datasource js not found by filename pattern; will still emit events + localStorage bus."
fi

python3 - <<'PY'
from pathlib import Path
import re

dash_path = Path("static/js/vsp_dashboard_enhance_v1.js")
dash = dash_path.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_UI_DRILLDOWN_AND_EXPORTPROBE_V1 ==="
if TAG in dash:
    print("[OK] dashboard patch already present; skip dashboard insert")
else:
    # append at end (safe)
    patch = r"""
%s
(function(){
  'use strict';

  // --- tiny utils ---
  const LOG_ONCE = new Set();
  function logOnce(k, ...a){ if(LOG_ONCE.has(k)) return; LOG_ONCE.add(k); console.log(...a); }
  function nowMs(){ try { return Date.now(); } catch(_){ return 0; } }

  function ridFromPage(){
    // best-effort: try globals, DOM attrs, URL params
    try {
      if (window.VSP_RID) return String(window.VSP_RID);
      if (window.__VSP_RID__) return String(window.__VSP_RID__);
    } catch(_){}
    try {
      const u = new URL(location.href);
      const rid = u.searchParams.get("rid") || u.searchParams.get("run_id") || u.searchParams.get("id");
      if (rid) return String(rid);
    } catch(_){}
    try {
      const el = document.querySelector("[data-rid],[data-run-id],[data-runid]");
      const v = el && (el.getAttribute("data-rid") || el.getAttribute("data-run-id") || el.getAttribute("data-runid"));
      if (v) return String(v);
    } catch(_){}
    return null;
  }

  function openTab(tabId){
    // expects your 4-tabs router to exist; best-effort click
    try {
      // common patterns: button#tab-datasource / a[href='#datasource']
      const btn = document.querySelector("#tab-" + tabId + ", [data-tab='"+tabId+"'], a[href='#"+tabId+"']");
      if (btn) { btn.click(); return true; }
    } catch(_){}
    // fallback: try call existing router func if you have one
    try {
      if (typeof window.VSP_SWITCH_TAB === "function") { window.VSP_SWITCH_TAB(tabId); return true; }
      if (typeof window.vspSwitchTab === "function") { window.vspSwitchTab(tabId); return true; }
    } catch(_){}
    return false;
  }

  // --- datasource filter bus (localStorage + CustomEvent) ---
  const LS_KEY = "vsp_ds_filters_v1";

  function pushDatasourceFilters(filters, opts){
    opts = opts || {};
    const payload = {
      v: 1,
      ts: nowMs(),
      rid: opts.rid || ridFromPage(),
      filters: filters || {}
    };
    try { localStorage.setItem(LS_KEY, JSON.stringify(payload)); } catch(_){}
    try {
      window.dispatchEvent(new CustomEvent("vsp:datasource:setFilters", { detail: payload }));
    } catch(_){}
  }

  // public API for drilldown
  window.VSP_DRILL_TO_DATASOURCE = function(filters, opts){
    try {
      pushDatasourceFilters(filters || {}, opts || {});
      openTab("datasource");
    } catch(e) {
      console.warn("[VSP][DRILL] failed", e);
    }
  };

  // --- export probe: make it quiet + stop after first success ---
  async function probeExportOnce(url){
    // HEAD is often blocked/noisy in browser setups; fallback to GET safely.
    try {
      const r = await fetch(url, { method: "HEAD", cache: "no-store", credentials: "same-origin" });
      if (r && r.ok) return { ok:true, via:"HEAD", status:r.status, headers:r.headers };
    } catch(_){}
    try {
      const r = await fetch(url + (url.includes("?") ? "&" : "?") + "_probe=1", { method: "GET", cache: "no-store", credentials: "same-origin" });
      if (r && r.ok) return { ok:true, via:"GET", status:r.status, headers:r.headers };
      return { ok:false, via:"GET", status: (r && r.status) || 0, headers: r && r.headers };
    } catch(e){
      return { ok:false, via:"ERR", status:0, err:String(e) };
    }
  }

  async function commercialExportProbeQuiet(){
    // only run on pages that show export controls
    const rid = ridFromPage();
    if (!rid) return;

    // build canonical export URL once (commercial behavior)
    const base = (window.VSP_RUN_EXPORT_BASE || "/api/vsp/run_export_v3").replace(/\/+$/,"");
    const pdfUrl = base + "/" + encodeURIComponent(rid) + "?fmt=pdf";

    const key = "export-probe-" + rid;
    if (window.__VSP_EXPORT_PROBED__ && window.__VSP_EXPORT_PROBED__[rid]) return;
    window.__VSP_EXPORT_PROBED__ = window.__VSP_EXPORT_PROBED__ || {};
    window.__VSP_EXPORT_PROBED__[rid] = true;

    const res = await probeExportOnce(pdfUrl);
    // treat failures as non-fatal; do NOT spam console
    if (!res.ok){
      logOnce(key+"-fail", "[VSP][EXPORT][PROBE] pdf probe not OK (non-fatal)", { rid, url: pdfUrl, via: res.via, status: res.status });
      window.VSP_EXPORT_AVAILABLE = window.VSP_EXPORT_AVAILABLE || {};
      window.VSP_EXPORT_AVAILABLE.pdf = 0;
      return;
    }

    // success: set availability and stop further probes
    window.VSP_EXPORT_AVAILABLE = window.VSP_EXPORT_AVAILABLE || {};
    window.VSP_EXPORT_AVAILABLE.pdf = 1;
    logOnce(key+"-ok", "[VSP][EXPORT][PROBE] pdf available", { rid, via: res.via, status: res.status });

    // if you have UI pills/badges, update them quietly
    try {
      const pill = document.querySelector("[data-export='pdf'], #pill-export-pdf, #pill-pdf");
      if (pill) { pill.classList.add("is-ok"); pill.classList.remove("is-bad"); }
    } catch(_){}
  }

  // run once after DOM ready
  function onReady(fn){
    if (document.readyState === "complete" || document.readyState === "interactive") return setTimeout(fn, 0);
    document.addEventListener("DOMContentLoaded", fn, { once: true });
  }

  // --- attach drilldown click helpers (best-effort, non-breaking) ---
  function wireDrilldownClicks(){
    // opt-in attributes (recommended): data-vsp-drill-tool / data-vsp-drill-sev / data-vsp-drill-cwe
    const els = document.querySelectorAll("[data-vsp-drill-tool],[data-vsp-drill-sev],[data-vsp-drill-cwe]");
    els.forEach(el=>{
      if (el.__vsp_drilled__) return;
      el.__vsp_drilled__ = true;
      el.style.cursor = "pointer";
      el.addEventListener("click", ()=>{
        const tool = el.getAttribute("data-vsp-drill-tool");
        const sev  = el.getAttribute("data-vsp-drill-sev");
        const cwe  = el.getAttribute("data-vsp-drill-cwe");
        const filters = {};
        if (tool) filters.tool = tool;
        if (sev)  filters.severity = sev;
        if (cwe)  filters.cwe = cwe;
        window.VSP_DRILL_TO_DATASOURCE(filters);
      });
    });

    // fallback: gate summary pills often include tool/sev text
    const pills = document.querySelectorAll(".vsp-pill,[data-pill]");
    pills.forEach(p=>{
      if (p.__vsp_drilled__) return;
      const t = (p.textContent || "").trim();
      // simple patterns: "GITLEAKS", "SEMGREP", "CRITICAL", "HIGH", "CWE-79"
      const tool = (/^(GITLEAKS|SEMGREP|TRIVY|CODEQL|KICS|GRYPE|SYFT|BANDIT)$/i.exec(t) or [None])[0] if False else None
    });
  }

  // NOTE: avoid python-style in JS; keep safe fallback only
  function wireFallbackPills(){
    const pills = document.querySelectorAll(".vsp-pill,[data-pill]");
    pills.forEach(p=>{
      if (p.__vsp_drilled__) return;
      const txt = (p.textContent || "").trim();
      if (!txt) return;

      const up = txt.toUpperCase();
      const filters = {};
      const toolSet = new Set(["GITLEAKS","SEMGREP","TRIVY","CODEQL","KICS","GRYPE","SYFT","BANDIT"]);
      const sevSet  = new Set(["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]);
      if (toolSet.has(up)) filters.tool = up;
      if (sevSet.has(up))  filters.severity = up;
      if (/^CWE-\d+$/i.test(up)) filters.cwe = up;

      if (Object.keys(filters).length === 0) return;

      p.__vsp_drilled__ = true;
      p.style.cursor = "pointer";
      p.title = "Click to drilldown → Data Source";
      p.addEventListener("click", ()=> window.VSP_DRILL_TO_DATASOURCE(filters));
    });
  }

  onReady(()=>{
    try { commercialExportProbeQuiet(); } catch(e){ /* silent */ }
    try { wireDrilldownClicks(); } catch(e){ /* silent */ }
    try { wireFallbackPills(); } catch(e){ /* silent */ }
  });

})();
""" % TAG

    # small fix: remove any accidental python remnants
    patch = patch.replace("const tool = (/^(GITLEAKS|SEMGREP|TRIVY|CODEQL|KICS|GRYPE|SYFT|BANDIT)$/i.exec(t) or [None])[0] if False else None",
                          "// (intentionally empty; handled by wireFallbackPills)")

    dash += "\n\n" + patch + "\n"
    dash_path.write_text(dash, encoding="utf-8")
    print("[OK] patched dashboard enhance js")

print("[INFO] done dashboard")

# Patch datasource JS if found, add listener + apply pending filters from LS
import os, glob, json
cands = []
for pat in ["static/js/*datasource*", "static/js/*data_source*", "static/js/*ds*tab*"]:
    cands += glob.glob(pat)
ds_js = cands[0] if cands else ""
if ds_js and os.path.isfile(ds_js):
    p = Path(ds_js)
    s = p.read_text(encoding="utf-8", errors="ignore")
    TAG2 = "// === VSP_DATASOURCE_FILTERBUS_V1 ==="
    if TAG2 in s:
        print("[OK] datasource patch already present; skip")
    else:
        add = r"""
%s
(function(){
  'use strict';
  const LS_KEY = "vsp_ds_filters_v1";

  function safeParse(x){ try { return JSON.parse(x); } catch(_){ return null; } }
  function fireChange(el){
    try { el.dispatchEvent(new Event("input", { bubbles:true })); } catch(_){}
    try { el.dispatchEvent(new Event("change", { bubbles:true })); } catch(_){}
  }

  function setValAny(selectors, val){
    for (const sel of selectors){
      const el = document.querySelector(sel);
      if (!el) continue;
      if (el.tagName === "SELECT" || el.tagName === "INPUT" || el.tagName === "TEXTAREA"){
        el.value = String(val);
        fireChange(el);
        return true;
      }
    }
    return false;
  }

  function applyFilters(filters){
    filters = filters || {};
    // best-effort selector list; adapt to your actual ids/classes without breaking
    if (filters.severity) setValAny(["#ds-filter-sev","#filter-sev","select[name='severity']","[data-filter='severity']"], filters.severity);
    if (filters.tool)     setValAny(["#ds-filter-tool","#filter-tool","select[name='tool']","[data-filter='tool']"], filters.tool);
    if (filters.cwe)      setValAny(["#ds-filter-cwe","#filter-cwe","input[name='cwe']","[data-filter='cwe']"], filters.cwe);
    if (filters.text)     setValAny(["#ds-filter-text","#filter-text","input[name='text']","[data-filter='text']"], filters.text);
    if (filters.limit)    setValAny(["#ds-filter-limit","#filter-limit","input[name='limit']","[data-filter='limit']"], filters.limit);

    // refresh hook: call existing functions if present; otherwise click apply/search buttons
    try {
      if (typeof window.VSP_DS_REFRESH === "function") return window.VSP_DS_REFRESH();
      if (typeof window.vspDatasourceRefresh === "function") return window.vspDatasourceRefresh();
      if (typeof window.applyFilters === "function") return window.applyFilters();
    } catch(_){}
    try {
      const btn = document.querySelector("#ds-apply,#btn-apply,#filter-apply,[data-action='apply-filters']");
      if (btn) btn.click();
    } catch(_){}
  }

  function consumePending(){
    let raw = null;
    try { raw = localStorage.getItem(LS_KEY); } catch(_){}
    const payload = safeParse(raw || "");
    if (!payload || !payload.filters) return false;

    // only accept within 5 minutes
    const ts = Number(payload.ts || 0);
    const age = Date.now() - ts;
    if (!(age >= 0 && age <= 5*60*1000)) return false;

    try { localStorage.removeItem(LS_KEY); } catch(_){}
    applyFilters(payload.filters);
    return true;
  }

  function onReady(fn){
    if (document.readyState === "complete" || document.readyState === "interactive") return setTimeout(fn, 0);
    document.addEventListener("DOMContentLoaded", fn, { once: true });
  }

  // listen drilldown event
  window.addEventListener("vsp:datasource:setFilters", (e)=>{
    try { applyFilters((e.detail && e.detail.filters) || {}); } catch(_){}
  });

  // also react to LS updates (other tab / same tab)
  window.addEventListener("storage", (e)=>{
    if (!e || e.key !== LS_KEY) return;
    try { consumePending(); } catch(_){}
  });

  onReady(()=>{ try { consumePending(); } catch(_){} });

})();
""" % TAG2

        s += "\n\n" + add + "\n"
        p.write_text(s, encoding="utf-8")
        print("[OK] patched datasource js:", ds_js)
else:
    print("[WARN] datasource js not patched (not found)")

PY

python3 -m py_compile "$DASH_JS" >/dev/null 2>&1 && echo "[OK] py_compile dashboard"
if [ -n "${DS_JS:-}" ] && [ -f "${DS_JS:-}" ]; then
  python3 -m py_compile "$DS_JS" >/dev/null 2>&1 || true
fi

echo "[DONE] Patch applied. Restart gunicorn + hard refresh (Ctrl+Shift+R)."
