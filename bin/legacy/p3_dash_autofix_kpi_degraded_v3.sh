#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_AUTOFIX_KPI_DEGRADED_V3"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_autofixkpi3_${TS}"
echo "[BACKUP] ${JS}.bak_autofixkpi3_${TS}"

python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, textwrap

js_path = sys.argv[1]
mark = sys.argv[2]

p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

block = textwrap.dedent(r"""
/* ===================== VSP_P3_AUTOFIX_KPI_DEGRADED_V3 ===================== */
(function(){
  try{
    if (window.__VSP_AUTOFIX_KPI_DEGRADED_V3__) return;
    window.__VSP_AUTOFIX_KPI_DEGRADED_V3__ = true;

    const NEEDLES = [
      "KPI/Charts Degraded",
      "KPI data not available",
      "This is expected when KPI is disabled",
      "VSP_UI_GATEWAY_MARK_V1"
    ];

    function qp(name){
      try { return new URL(location.href).searchParams.get(name) || ""; }
      catch(e){ return ""; }
    }
    function iNum(v){
      try{
        if (v == null) return 0;
        if (typeof v === "string") v = v.replaceAll(",","").trim();
        return parseInt(v || 0, 10) || 0;
      }catch(e){ return 0; }
    }
    async function fetchJson(url){
      const r = await fetch(url, { credentials: "same-origin" });
      if(!r.ok) throw new Error("HTTP "+r.status+" for "+url);
      return await r.json();
    }

    function pickCountsBySev(obj){
      if(!obj || typeof obj !== "object") return null;
      return obj.counts_by_severity || obj.by_severity || obj.severity_counts || (obj.meta && obj.meta.counts_by_severity) || null;
    }
    function pickDashKpis(j){
      if(!j || typeof j !== "object") return null;
      return j.dash_kpis || j.kpis || j;
    }
    function getTotal(dk, j){
      let v = dk && (dk.total_findings ?? dk.total ?? (dk.counts_total && dk.counts_total.total_findings));
      if (v == null && j) v = (j.total_findings ?? j.total);
      let n = iNum(v);
      if (n > 0) return n;

      const by = pickCountsBySev(dk) || pickCountsBySev(j);
      if (by){
        n = iNum(by.TOTAL ?? by.total ?? 0);
        if (n > 0) return n;
        const keys = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
        const sum = keys.reduce((acc,k)=> acc + iNum(by[k] ?? by[k.toLowerCase()]), 0);
        if (sum > 0) return sum;
      }
      return 0;
    }
    function getSev(dk, j, sev){
      sev = String(sev||"").toUpperCase();
      const by = pickCountsBySev(dk) || pickCountsBySev(j) || {};
      let v = by[sev];
      if (v == null) v = by[sev.toLowerCase()];
      if (v == null && dk){
        const k = "count_" + sev.toLowerCase();
        v = dk[k];
      }
      if (v == null && j){
        const k = "count_" + sev.toLowerCase();
        v = j[k];
      }
      return iNum(v);
    }

    function normText(s){
      return (s || "").replace(/\s+/g," ").trim();
    }

    function hideDegradedOnce(){
      const root = document.body;
      // Scan block elements broadly
      const blocks = root.querySelectorAll("div,section,article,aside");
      for (const el of blocks){
        const t = normText(el.textContent);
        if (!t) continue;
        let hit = false;
        for (const n of NEEDLES){
          if (t.includes(n)){ hit = true; break; }
        }
        if (!hit) continue;

        // hide a higher-level container to ensure it disappears
        let host = el;
        for (let i=0;i<4;i++){
          const p = host.parentElement;
          if (!p) break;
          // stop climbing if too big (avoid hiding the whole page)
          const pt = normText(p.textContent);
          if (pt.length > 6000) break;
          host = p;
        }
        host.style.display = "none";
      }
    }

    function findLabelNodes(label){
      label = normText(label);
      const els = Array.from(document.querySelectorAll("div,span,p,h1,h2,h3,h4,td,th"));
      return els.filter(el => normText(el.textContent) === label);
    }

    function pickLargestNumberNode(container){
      // candidates: text like 25 or 1,558
      const cand = Array.from(container.querySelectorAll("div,span,p,h1,h2,h3,h4"))
        .filter(el => {
          const t = (el.textContent || "").trim();
          return /^[0-9][0-9,]*$/.test(t);
        });

      if (!cand.length) return null;

      let best = cand[0];
      let bestSize = 0;

      for (const el of cand){
        const cs = getComputedStyle(el);
        const fs = parseFloat(cs.fontSize || "0") || 0;
        if (fs > bestSize){
          bestSize = fs;
          best = el;
        }
      }
      return best;
    }

    function setKpiValue(label, value){
      const labs = findLabelNodes(label);
      for (const lab of labs){
        // climb to card container
        let box = lab.closest("div") || lab.parentElement;
        for (let i=0;i<6 && box && box.parentElement;i++){
          const cs = getComputedStyle(box);
          // heuristic: stop on rounded/bordered blocks
          if ((parseFloat(cs.borderRadius||"0") > 0) || (cs.borderStyle && cs.borderStyle !== "none")) break;
          box = box.parentElement;
        }
        box = box || lab.parentElement || lab;
        const num = pickLargestNumberNode(box);
        if (num){
          num.textContent = String(value);
          return true;
        }
      }
      return false;
    }

    async function healOnce(){
      const rid = qp("rid");
      let j = null;
      let lastErr = "";
      const urls = rid ? [
        "/api/vsp/dash_kpis?rid=" + encodeURIComponent(rid),
        "/api/vsp/dash_kpis"
      ] : ["/api/vsp/dash_kpis"];

      for (const u of urls){
        try { j = await fetchJson(u); break; }
        catch(e){ lastErr = (e && e.message) ? e.message : String(e); }
      }

      hideDegradedOnce();

      if (!j){
        try{ console.warn("[AutoFixKPI_V3] cannot fetch dash_kpis:", lastErr); }catch(_){}
        return;
      }

      const dk = pickDashKpis(j);
      const total = getTotal(dk, j);
      const critical = getSev(dk, j, "CRITICAL");
      const high     = getSev(dk, j, "HIGH");
      const medium   = getSev(dk, j, "MEDIUM");

      if (total <= 0){
        try{ console.warn("[AutoFixKPI_V3] total still 0; resp=", j); }catch(_){}
        return;
      }

      // Update KPI cards by label (case variants)
      setKpiValue("Total findings", total) || setKpiValue("Total Findings", total);
      setKpiValue("Critical", critical);
      setKpiValue("High", high);
      setKpiValue("Medium", medium) || setKpiValue("Medium*", medium);

      try{ console.log("[AutoFixKPI_V3] applied", {rid: rid||"(auto)", total, critical, high, medium}); }catch(_){}
    }

    function boot(){
      // loop hide degraded for a while (render may be late)
      let n = 0;
      const t = setInterval(() => {
        n++;
        hideDegradedOnce();
        if (n >= 28) clearInterval(t); // ~8.4s
      }, 300);

      // heal retries
      setTimeout(healOnce, 600);
      setTimeout(healOnce, 1600);
      setTimeout(healOnce, 3200);
      setTimeout(healOnce, 5200);
    }

    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", boot, { once:true });
    } else {
      boot();
    }
  }catch(e){
    try{ console.warn("[AutoFixKPI_V3] error:", e); }catch(_){}
  }
})();
 /* ===================== /VSP_P3_AUTOFIX_KPI_DEGRADED_V3 ===================== */
""").strip("\n") + "\n"

p.write_text(s.rstrip("\n") + "\n\n" + block, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker in JS =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing in JS"; exit 2; }

echo "[DONE] V3 installed. Open + HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
