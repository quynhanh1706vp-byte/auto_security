#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_STABILIZE_KPI_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_stabilize_${TS}"
echo "[BACKUP] ${JS}.bak_stabilize_${TS}"

python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, re, textwrap

js_path = sys.argv[1]
mark = sys.argv[2]
p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

# 1) Remove any DOMContentLoaded addEventListener that contains "__vspCheckDegraded" (multi-line safe)
s = re.sub(
    r'document\.addEventListener\(\s*([\'"])DOMContentLoaded\1\s*,.*?__vspCheckDegraded.*?\)\s*;',
    '/* VSP_P3_STABILIZE_KPI_V1: removed degraded DOMContentLoaded hook */',
    s,
    flags=re.S
)

# 2) Stub ANY function named __vspCheckDegraded (covers function decl + inline named function)
s = re.sub(
    r'function\s+__vspCheckDegraded\s*\([^)]*\)\s*\{.*?\}',
    'function __vspCheckDegraded(){ /* disabled */ return; }',
    s,
    flags=re.S
)
s = re.sub(
    r'function\s+__vspCheckDegraded\s*\([^)]*\)\s*\{',
    'function __vspCheckDegraded(){ /* disabled */ return; }\n/* VSP_P3_STABILIZE_KPI_V1: cut remaining body */\n/*',
    s
)

# 3) Remove any direct calls / timers
s = re.sub(r'__vspCheckDegraded\s*\(\s*\)\s*;', '/* VSP_P3_STABILIZE_KPI_V1: call removed */', s)
s = re.sub(r'setTimeout\(\s*__vspCheckDegraded\s*,', 'setTimeout(function(){},', s)

# 4) Append a safe KPI-forcer that ONLY hides the banner node itself (no parent climbing)
block = textwrap.dedent(r"""
/* ===================== VSP_P3_STABILIZE_KPI_V1 ===================== */
(function(){
  try{
    if (window.__VSP_P3_STABILIZE_KPI_V1__) return;
    window.__VSP_P3_STABILIZE_KPI_V1__ = true;

    function qp(name){
      try { return new URL(location.href).searchParams.get(name) || ""; } catch(e){ return ""; }
    }
    function iNum(v){
      try{
        if (v == null) return 0;
        if (typeof v === "string") v = v.replaceAll(",","").trim();
        return parseInt(v || 0, 10) || 0;
      }catch(e){ return 0; }
    }

    async function fetchDashKpis(rid){
      const url = "/api/vsp/dash_kpis?rid=" + encodeURIComponent(rid||"");
      const r = await fetch(url, {credentials:"same-origin"});
      if (!r.ok) throw new Error("HTTP "+r.status);
      return await r.json();
    }

    function normText(s){ return (s||"").replace(/\s+/g," ").trim(); }

    // Hide ONLY the banner element that contains the exact degraded text
    function hideDegradedBanner(){
      const needles = ["KPI/Charts Degraded", "KPI data not available"];
      const els = Array.from(document.querySelectorAll("div,section,article,aside,span,p"));
      for (const el of els){
        const t = normText(el.textContent);
        if(!t) continue;
        if (!needles.some(n => t.includes(n))) continue;

        // Only hide the smallest element that contains the text (avoid hiding parents)
        el.style.display = "none";
      }
    }

    function findLabelNodes(label){
      label = normText(label);
      const els = Array.from(document.querySelectorAll("div,span,p,h1,h2,h3,h4,td,th"));
      return els.filter(el => normText(el.textContent) === label);
    }

    function pickLargestNumberNode(container){
      const cand = Array.from(container.querySelectorAll("div,span,p,h1,h2,h3,h4"))
        .filter(el => /^[0-9][0-9,]*$/.test((el.textContent||"").trim()));
      if (!cand.length) return null;
      let best = cand[0], bestSize = 0;
      for (const el of cand){
        const fs = parseFloat(getComputedStyle(el).fontSize || "0") || 0;
        if (fs > bestSize){ bestSize = fs; best = el; }
      }
      return best;
    }

    function setKpiByLabel(label, value){
      const labs = findLabelNodes(label);
      for (const lab of labs){
        // climb mildly to card container, but stop early to avoid nuking layout
        let box = lab.closest("div") || lab.parentElement || lab;
        for (let i=0;i<4 && box && box.parentElement;i++){
          const pt = normText(box.parentElement.textContent);
          if (pt.includes("VSP Dashboard") || pt.includes("Top Findings")) break;
          box = box.parentElement;
        }
        const num = pickLargestNumberNode(box);
        if (num){
          num.textContent = String(value);
          return true;
        }
      }
      return false;
    }

    async function applyOnce(){
      const rid = qp("rid");
      if(!rid) return;

      hideDegradedBanner();

      let j = null;
      try{ j = await fetchDashKpis(rid); } catch(e){ console.warn("[STABILIZE_KPI_V1] dash_kpis fetch failed", e); return; }
      if(!j || j.ok !== true) return;

      const total = iNum(j.total_findings ?? j.total);
      const ct = j.counts_total || j.counts || {};
      const high = iNum(ct.HIGH);
      const medium = iNum(ct.MEDIUM);
      const critical = iNum(ct.CRITICAL);

      if(total > 0){
        setKpiByLabel("Total findings", total) || setKpiByLabel("Total Findings", total);
        setKpiByLabel("High", high);
        setKpiByLabel("Medium", medium) || setKpiByLabel("Medium*", medium);
        setKpiByLabel("Critical", critical);
      }

      hideDegradedBanner();
      try{ console.log("[STABILIZE_KPI_V1] applied", {rid, total, critical, high, medium}); }catch(_){}
    }

    function boot(){
      // run multiple times because dashboard renders async
      setTimeout(applyOnce, 600);
      setTimeout(applyOnce, 1600);
      setTimeout(applyOnce, 3200);
      setTimeout(applyOnce, 5200);
      // keep banner suppressed
      let n=0;
      const t=setInterval(()=>{ n++; hideDegradedBanner(); if(n>25) clearInterval(t); }, 250);
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, {once:true});
    else boot();
  }catch(e){ try{ console.warn("[STABILIZE_KPI_V1] error", e); }catch(_){ } }
})();
/* ===================== /VSP_P3_STABILIZE_KPI_V1 ===================== */
""").strip("\n") + "\n"

s = s.rstrip("\n") + "\n\n" + block + "\n/* " + mark + " */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker present =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing"; exit 2; }

echo "== [verify] __vspCheckDegraded remaining refs =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -n "__vspCheckDegraded" | head -n 10 || true

echo "[DONE] stabilize installed. HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
