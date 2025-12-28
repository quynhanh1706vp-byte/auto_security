#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_FORCE_KPI_FROM_DASHKPIS_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_forcekpi_${TS}"
echo "[BACKUP] ${JS}.bak_forcekpi_${TS}"

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

# Replace the first occurrence of: applyCounts(__ct || null);
pat = r'applyCounts\(\s*__ct\s*\|\|\s*null\s*\)\s*;'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find applyCounts(__ct || null); to patch")

inject = r"""
      applyCounts(__ct || null);

      // ===================== VSP_P3_FORCE_KPI_FROM_DASHKPIS_V1 =====================
      // After baseline applyCounts(from run_gate_summary), re-apply using dash_kpis (source-of-truth) for current rid.
      try{
        (async function(){
          try{
            const _rid = (typeof rid !== "undefined" && rid) ? rid : (new URL(location.href)).searchParams.get("rid") || "";
            if(!_rid) return;

            const _fetch = (typeof fetchJson === "function") ? fetchJson : ((typeof fetchJSON === "function") ? fetchJSON : null);
            if(!_fetch) return;

            const _j = await _fetch("/api/vsp/dash_kpis?rid=" + encodeURIComponent(_rid));
            if(!_j || _j.ok !== true) return;

            // cache for other blocks
            try{ window.__vsp_dashkpis_cache = _j; }catch(_){}

            const _ctU = (_j.counts_total || _j.counts || {});
            const _tf  = parseInt((_j.total_findings ?? _j.total ?? 0) || 0, 10) || 0;
            if(_tf <= 0) return;

            // applyCounts() in luxe expects a "counts_total-ish" object but often reads lower-case keys
            const _ct = {
              total_findings: _tf,
              TOTAL: _tf,
              CRITICAL: parseInt((_ctU.CRITICAL ?? 0) || 0, 10) || 0,
              HIGH:     parseInt((_ctU.HIGH ?? 0) || 0, 10) || 0,
              MEDIUM:   parseInt((_ctU.MEDIUM ?? 0) || 0, 10) || 0,
              LOW:      parseInt((_ctU.LOW ?? 0) || 0, 10) || 0,
              INFO:     parseInt((_ctU.INFO ?? 0) || 0, 10) || 0,
              TRACE:    parseInt((_ctU.TRACE ?? 0) || 0, 10) || 0,
            };
            // friendly aliases (some UI paths read these)
            _ct.critical = _ct.CRITICAL;
            _ct.high     = _ct.HIGH;
            _ct.medium   = _ct.MEDIUM;
            _ct.low      = _ct.LOW;
            _ct.info     = _ct.INFO;
            _ct.trace    = _ct.TRACE;

            applyCounts(_ct);

            // Hide degraded banner if still present
            try{
              const blocks = document.querySelectorAll("div,section,article,aside");
              for (const el of blocks){
                const t = (el.textContent||"").replace(/\s+/g," ").trim();
                if (t.includes("KPI/Charts Degraded") || t.includes("KPI data not available")){
                  el.style.display="none";
                }
              }
            }catch(_){}

            try{ console.log("[FORCE_KPI_FROM_DASHKPIS_V1] applied", {rid:_rid, total:_tf, high:_ct.HIGH, medium:_ct.MEDIUM}); }catch(_){}
          }catch(e){
            try{ console.warn("[FORCE_KPI_FROM_DASHKPIS_V1] failed:", e); }catch(_){}
          }
        })();
      }catch(_){}
      // ===================== /VSP_P3_FORCE_KPI_FROM_DASHKPIS_V1 =====================
"""

s = s[:m.start()] + inject + s[m.end():]

s += f"\n/* {mark} */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker present =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing"; exit 2; }

echo "[DONE] FORCE KPI installed. HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
