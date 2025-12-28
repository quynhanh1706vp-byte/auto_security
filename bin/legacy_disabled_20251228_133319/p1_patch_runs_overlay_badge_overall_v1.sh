#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_runs_reports_overlay_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_badge_${TS}"
echo "[BACKUP] ${JS}.bak_badge_${TS}"

python3 - <<'PY'
from pathlib import Path

js_path = Path("static/js/vsp_runs_reports_overlay_v1.js")
s = js_path.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUNS_OVERALL_BADGE_V1"
if marker in s:
    print("[OK] marker already present, skip (idempotent).")
    raise SystemExit(0)

patch = r"""
/* VSP_P1_RUNS_OVERALL_BADGE_V1 (badge colors + inferred fallback; hide UNKNOWN on /runs) */
(()=> {
  try{
    if (window.__vsp_p1_runs_overall_badge_v1) return;
    window.__vsp_p1_runs_overall_badge_v1 = true;

    // Scope: only affect /runs-like pages to avoid side effects
    const path = (location && location.pathname) ? String(location.pathname) : "";
    if (!/\/runs\b/i.test(path) && !/runs/i.test(path)){
      // still allow if the runs table is embedded somewhere else
      // (no hard return) – but keep effects minimal via DOM selectors below
    }

    function pickOverall(it){
      const src = (it && it.overall_source) ? String(it.overall_source) : "";
      let ov = (it && it.overall) ? String(it.overall) : "";
      const inf = (it && it.overall_inferred) ? String(it.overall_inferred) : "";

      const bad = (!ov || ov === "UNKNOWN" || ov === "unknown");
      const inferredSrc = (src === "inferred_counts" || src === "inferred" || src === "inferred_count");

      if ((bad || inferredSrc) && inf && inf !== "UNKNOWN" && inf !== "unknown"){
        ov = inf;
      }
      if (!ov) ov = "UNKNOWN";
      return ov.toUpperCase();
    }

    function overallClass(ov){
      ov = String(ov||"UNKNOWN").toUpperCase();
      if (ov === "RED") return "vsp-badge vsp-badge-red";
      if (ov === "AMBER") return "vsp-badge vsp-badge-amber";
      if (ov === "GREEN") return "vsp-badge vsp-badge-green";
      return "vsp-badge vsp-badge-gray";
    }

    // CSS injected once
    const styleId = "VSP_P1_RUNS_OVERALL_BADGE_V1_CSS";
    if (!document.getElementById(styleId)){
      const css = `
      .vsp-badge{display:inline-flex;align-items:center;gap:.35em;padding:.15em .55em;border-radius:999px;
        font-size:12px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#d7d7d7;line-height:1.4;}
      .vsp-badge-red{background:rgba(255,60,60,.12);border-color:rgba(255,60,60,.25);color:#ffb8b8;}
      .vsp-badge-amber{background:rgba(255,170,0,.12);border-color:rgba(255,170,0,.25);color:#ffe2a6;}
      .vsp-badge-green{background:rgba(0,220,120,.12);border-color:rgba(0,220,120,.25);color:#b7ffd7;}
      .vsp-badge-gray{background:rgba(160,160,160,.10);border-color:rgba(160,160,160,.20);color:#e7e7e7;}
      `;
      const st = document.createElement("style");
      st.id = styleId;
      st.textContent = css;
      document.head.appendChild(st);
    }

    // Cache latest runs list (keyed by rid) from /api/ui/runs_v3
    const origFetch = window.fetch;
    if (typeof origFetch === "function" && !origFetch.__vsp_p1_runs_overall_badge_v1){
      window.fetch = async function(input, init){
        const url = (typeof input === "string") ? input : (input && input.url) || "";
        const resp = await origFetch(input, init);
        try{
          if (url && url.includes("/api/ui/runs_v3")){
            const clone = resp.clone();
            const j = await clone.json();
            const items = Array.isArray(j && j.items) ? j.items : [];
            window.__vsp_runs_cache_v1 = window.__vsp_runs_cache_v1 || {};
            for (const it of items){
              if (it && it.rid) window.__vsp_runs_cache_v1[it.rid] = it;
            }
            setTimeout(fixDom, 0);
          }
        }catch(_){}
        return resp;
      };
      window.fetch.__vsp_p1_runs_overall_badge_v1 = true;
      window.fetch.__vsp_p1_runs_overall_badge_v1 = true;
    }

    function fixCell(td, it){
      const ov = it ? pickOverall(it) : String((td.textContent||"").trim() || "UNKNOWN").toUpperCase();
      const cls = overallClass(ov);
      td.innerHTML = `<span class="${cls}">${ov}</span>`;
    }

    function findRidFromRow(row){
      if (!row) return "";
      return row.getAttribute("data-rid")
          || row.getAttribute("data-id")
          || row.getAttribute("data-run-id")
          || row.getAttribute("rid")
          || "";
    }

    function fixDom(){
      try{
        // Only operate if a runs table likely exists
        const root = document.querySelector("#runs, #runs_tab, .runs, [data-tab='runs'], [data-page='runs'], body") || document.body;
        if (!root) return;

        // cells likely containing "overall"
        const cells = root.querySelectorAll(
          "[data-field='overall'], td.overall, .col-overall, .overall, td[data-col='overall'], td[data-key='overall']"
        );
        if (!cells || !cells.length) return;

        for (const td of cells){
          const row = td.closest("tr");
          const rid = findRidFromRow(row);
          const it = (rid && window.__vsp_runs_cache_v1 && window.__vsp_runs_cache_v1[rid]) ? window.__vsp_runs_cache_v1[rid] : null;

          // If UI already showing badge, skip
          if (td.querySelector && td.querySelector(".vsp-badge")) continue;

          // if text is UNKNOWN but we can infer => replace
          const txt = String((td.textContent||"").trim() || "");
          if (it){
            fixCell(td, it)
          } else if (txt){
            // still render as badge (keeps consistent visuals)
            fixCell(td, null)
          }
        }
      }catch(_){}
    }

    // periodic re-apply (in case table rerenders)
    const boot = () => {
      fixDom();
      setInterval(fixDom, 1200);
    };
    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", boot);
    } else {
      boot();
    }
  }catch(_){}
})();
"""

# Append patch safely (newline + patch)
if not s.endswith("\n"):
    s += "\n"
s += "\n" + patch + "\n"

js_path.write_text(s, encoding="utf-8")
print("[OK] appended:", "VSP_P1_RUNS_OVERALL_BADGE_V1")
PY

echo "== quick grep marker =="
grep -n "VSP_P1_RUNS_OVERALL_BADGE_V1" -n "$JS" | head -n 5 || true

echo "[OK] patch applied. Restart UI and hard-refresh browser (Ctrl+F5) if cache is sticky."
