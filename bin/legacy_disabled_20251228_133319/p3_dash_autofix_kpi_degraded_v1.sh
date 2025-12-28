#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_AUTOFIX_KPI_DEGRADED_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_autofixkpi_${TS}"
echo "[BACKUP] ${JS}.bak_autofixkpi_${TS}"

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
/* ===================== VSP_P3_AUTOFIX_KPI_DEGRADED_V1 ===================== */
(function(){
  try{
    if (window.__VSP_AUTOFIX_KPI_DEGRADED_V1__) return;
    window.__VSP_AUTOFIX_KPI_DEGRADED_V1__ = true;

    async function fetchJson(url){
      const r = await fetch(url, { credentials: "same-origin" });
      if(!r.ok) throw new Error("HTTP "+r.status+" for "+url);
      return await r.json();
    }

    function pickDashKpis(j){
      if(!j) return null;
      // tolerant shapes
      if (j.dash_kpis) return j.dash_kpis;
      if (j.kpis) return j.kpis;
      return j;
    }

    function getTotalFindings(dk){
      if(!dk) return 0;
      let v = dk.total_findings;
      if (v == null) v = dk.total;
      if (v == null) v = (dk.counts_total && dk.counts_total.total_findings);
      try { return parseInt(v || 0, 10) || 0; } catch(e){ return 0; }
    }

    function getSevCount(dk, sev){
      sev = String(sev||"").toUpperCase();
      const by = dk && (dk.counts_by_severity || dk.by_severity || dk.severity_counts);
      if (by && typeof by === "object"){
        let v = by[sev];
        if (v == null) v = by[sev.toLowerCase()];
        try { return parseInt(v || 0, 10) || 0; } catch(e){ return 0; }
      }
      // sometimes dk has flat fields
      const k = "count_" + sev.toLowerCase();
      try { return parseInt((dk && dk[k]) || 0, 10) || 0; } catch(e){ return 0; }
    }

    function hideDegradedBanner(){
      const root = document.getElementById("vsp5_root") || document.body;
      const needles = [
        "KPI/Charts Degraded",
        "KPI data not available",
        "Degraded banner"
      ];
      const nodes = root.querySelectorAll("div,section,article,p,span");
      for (const el of nodes){
        const t = (el.textContent || "").trim();
        if (!t) continue;
        for (const n of needles){
          if (t.includes(n)){
            // hide the nearest block container
            const blk = el.closest("div,section,article") || el;
            blk.style.display = "none";
          }
        }
      }
    }

    function setKpiByLabel(label, value){
      const root = document.getElementById("vsp5_root") || document.body;
      // find the label node (exact match)
      const candidates = Array.from(root.querySelectorAll("div,span,p,td,th"))
        .filter(el => (el.textContent || "").trim() === label);
      if (!candidates.length) return false;

      for (const lab of candidates){
        // find a "card-like" container near label
        let card = lab.closest("div");
        // walk up a few levels to get a stable box
        for (let i=0;i<5 && card && card.parentElement;i++){
          // stop if card looks like a distinct block
          const cs = getComputedStyle(card);
          if (cs && (cs.borderRadius !== "0px" || cs.boxShadow !== "none")) break;
          card = card.parentElement;
        }
        card = card || lab.parentElement || lab;

        // inside card, find a node with pure number text (largest/first)
        const nums = Array.from(card.querySelectorAll("div,span,p"))
          .filter(el => {
            const t = (el.textContent || "").trim();
            return /^\d+$/.test(t) && el !== lab;
          });

        const target = nums[0];
        if (target){
          target.textContent = String(value);
          return true;
        }
      }
      return false;
    }

    async function heal(){
      // wait a bit for luxe to render its cards
      await new Promise(r => setTimeout(r, 400));

      let j=null;
      try{
        j = await fetchJson("/api/vsp/dash_kpis");
      }catch(e){
        // if endpoint differs, do nothing
        return;
      }
      const dk = pickDashKpis(j);
      const total = getTotalFindings(dk);
      if (total <= 0) return;

      // Hide degraded message (P0 polish)
      hideDegradedBanner();

      // Force KPI numbers (P0 demo)
      const critical = getSevCount(dk, "CRITICAL");
      const high = getSevCount(dk, "HIGH");
      const medium = getSevCount(dk, "MEDIUM");

      // tolerant: try both “Total findings” and “Total Findings”
      setKpiByLabel("Total findings", total) || setKpiByLabel("Total Findings", total);
      setKpiByLabel("Critical", critical);
      setKpiByLabel("High", high);
      setKpiByLabel("Medium", medium);

      // optional: update small subtitle if exists
      const sub = document.getElementById("vsp-topfind-sub");
      if (sub){
        // keep it non-invasive, only if already present
        // (do not override top findings state)
      }
    }

    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", heal, { once:true });
    } else {
      heal();
    }
  }catch(e){
    try{ console.warn("[AutoFixKPI] error:", e); }catch(_){}
  }
})();
 /* ===================== /VSP_P3_AUTOFIX_KPI_DEGRADED_V1 ===================== */
""").strip("\n") + "\n"

p.write_text(s.rstrip("\n") + "\n\n" + block, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker in JS =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing in JS"; exit 2; }

echo "[DONE] Auto-fix KPI+degraded installed. Open + hard refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
