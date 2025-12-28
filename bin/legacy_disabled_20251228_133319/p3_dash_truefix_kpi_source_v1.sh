#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_TRUEFIX_KPI_SOURCE_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_truefix_kpi_${TS}"
echo "[BACKUP] ${JS}.bak_truefix_kpi_${TS}"

python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, re

js_path = sys.argv[1]
mark = sys.argv[2]

p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

# 1) Ensure we cache dash_kpis response after the known fetch line:
#    var k=await fetchJson(vspWithRid("/api/vsp/dash_kpis", ...));
# Add: window.__vsp_dashkpis_cache = k;
pat_fetch = r'var\s+k\s*=\s*await\s+fetchJson\(\s*vspWithRid\(\s*"/api/vsp/dash_kpis"[^;]*\)\s*;'
m = re.search(pat_fetch, s)
if not m:
    raise SystemExit("[ERR] cannot locate dash_kpis await fetchJson(vspWithRid(\"/api/vsp/dash_kpis\"...)) in JS")

ins_cache = m.group(0) + "\n      try{ window.__vsp_dashkpis_cache = k || null; }catch(_){ }\n"
s = s[:m.start()] + ins_cache + s[m.end():]

# 2) Override counts source right after the line:
#    let counts = (gateSummary?.meta?.counts_by_severity) || (gateSummary?.counts_by_severity) || null;
pat_counts = r'let\s+counts\s*=\s*\(gateSummary\?\.\s*meta\?\.\s*counts_by_severity\)\s*\|\|\s*\(gateSummary\?\.\s*counts_by_severity\)\s*\|\|\s*null\s*;'
m2 = re.search(pat_counts, s)
if not m2:
    raise SystemExit("[ERR] cannot locate 'let counts = (gateSummary?.meta?.counts_by_severity) ...' in JS")

override = r"""
      // ===================== VSP_P3_TRUEFIX_KPI_SOURCE_V1 =====================
      // If dash_kpis has real numbers, prefer it over run_gate_summary counts (commercial KPI correctness)
      try{
        const _k = window.__vsp_dashkpis_cache || null;
        const _dk = (_k && (_k.dash_kpis || _k.kpis || _k)) || null;

        const _by = (_dk && (_dk.counts_by_severity || _dk.by_severity || _dk.severity_counts || (_dk.meta && _dk.meta.counts_by_severity))) || null;

        // total_findings signal (tolerant)
        let _tf = (_dk && (_dk.total_findings ?? _dk.total ?? (_dk.counts_total && _dk.counts_total.total_findings))) ?? null;
        if (_tf == null && _by){
          const keys=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
          _tf = keys.reduce((a,k)=> a + parseInt((_by[k] ?? _by[k.toLowerCase()] ?? 0) || 0,10), 0);
        }
        _tf = parseInt((_tf || 0), 10) || 0;

        // Only override when dash_kpis is actually populated
        if (_tf > 0 && _by && typeof _by === "object"){
          counts = _by;
          // also provide TOTAL if missing (some render paths expect TOTAL)
          if (counts.TOTAL == null && counts.total == null){
            counts.TOTAL = _tf;
          }
          // Kill degraded banner if any (text-based)
          try{
            const blocks = document.querySelectorAll("div,section,article,aside");
            for (const el of blocks){
              const t = (el.textContent||"").replace(/\s+/g," ").trim();
              if (t.includes("KPI/Charts Degraded") || t.includes("KPI data not available")){
                el.style.display="none";
              }
            }
          }catch(_){}
          try{ console.log("[TRUEFIX_KPI_SOURCE_V1] using dash_kpis counts, total_findings=", _tf); }catch(_){}
        } else {
          try{ console.log("[TRUEFIX_KPI_SOURCE_V1] keep run_gate_summary counts (dash_kpis empty)"); }catch(_){}
        }
      }catch(e){
        try{ console.warn("[TRUEFIX_KPI_SOURCE_V1] override failed:", e); }catch(_){}
      }
      // ===================== /VSP_P3_TRUEFIX_KPI_SOURCE_V1 =====================
"""
s = s[:m2.end()] + override + s[m2.end():]

# Final marker presence for grepping
s += "\n/* " + mark + " */\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker present =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing"; exit 2; }

echo "[DONE] TRUEFIX applied. Open + HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
