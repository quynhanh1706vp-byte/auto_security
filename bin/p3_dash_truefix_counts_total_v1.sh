#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_TRUEFIX_COUNTS_TOTAL_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_truefix_ct_${TS}"
echo "[BACKUP] ${JS}.bak_truefix_ct_${TS}"

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

# Locate applyCounts(j.counts_total || null);
pat = r'applyCounts\(\s*j\.counts_total\s*\|\|\s*null\s*\)\s*;'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find applyCounts(j.counts_total || null); in JS")

inject = r"""
      // ===================== VSP_P3_TRUEFIX_COUNTS_TOTAL_V1 =====================
      // counts_total drives KPI cards; prefer dash_kpis when it has real numbers
      let __ct = (j && j.counts_total) ? j.counts_total : null;
      try{
        const __k  = window.__vsp_dashkpis_cache || null;
        const __dk = (__k && (__k.dash_kpis || __k.kpis || __k)) || null;

        const __by = (__dk && (__dk.counts_by_severity || __dk.by_severity || __dk.severity_counts || (__dk.meta && __dk.meta.counts_by_severity))) || null;

        let __tf = (__dk && (__dk.total_findings ?? __dk.total ?? (__dk.counts_total && __dk.counts_total.total_findings))) ?? null;
        if (__tf == null && __by){
          const keys=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
          __tf = keys.reduce((a,k)=> a + parseInt((__by[k] ?? __by[k.toLowerCase()] ?? 0) || 0,10), 0);
        }
        __tf = parseInt((__tf || 0), 10) || 0;

        if (__tf > 0){
          // start from dash counts_total if available, else clone existing ct
          let __src = (__dk && __dk.counts_total) ? __dk.counts_total : (__ct || {});
          if (typeof __src !== "object" || __src === null) __src = {};
          __ct = __src;

          // normalize keys commonly used by KPI
          __ct.total_findings = __tf;
          __ct.TOTAL = (__ct.TOTAL == null) ? __tf : __ct.TOTAL;

          if (__by && typeof __by === "object"){
            const get = (k)=> parseInt((__by[k] ?? __by[k.toLowerCase()] ?? 0) || 0,10) || 0;
            __ct.critical = get("CRITICAL");
            __ct.high     = get("HIGH");
            __ct.medium   = get("MEDIUM");
            __ct.low      = get("LOW");
            __ct.info     = get("INFO");
            __ct.trace    = get("TRACE");
          }

          // hide degraded banner if present
          try{
            const blocks = document.querySelectorAll("div,section,article,aside");
            for (const el of blocks){
              const t = (el.textContent||"").replace(/\s+/g," ").trim();
              if (t.includes("KPI/Charts Degraded") || t.includes("KPI data not available")){
                el.style.display="none";
              }
            }
          }catch(_){}

          try{ console.log("[TRUEFIX_COUNTS_TOTAL_V1] applied counts_total from dash_kpis, total_findings=", __tf); }catch(_){}
        }
      }catch(e){
        try{ console.warn("[TRUEFIX_COUNTS_TOTAL_V1] override failed:", e); }catch(_){}
      }
      // ===================== /VSP_P3_TRUEFIX_COUNTS_TOTAL_V1 =====================
      applyCounts(__ct || null);
"""

# Replace the original call with our injected block
s = s[:m.start()] + inject + s[m.end():]

# Add marker footer for easy grep
s += "\n/* " + mark + " */\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker present =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing"; exit 2; }

echo "[DONE] counts_total TRUEFIX applied. Open + HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
