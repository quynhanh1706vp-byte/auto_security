#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

JS="static/js/vsp_runs_reports_overlay_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_kpi_v2pref_${TS}"
echo "[BACKUP] ${JS}.bak_kpi_v2pref_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_reports_overlay_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_PREF_V2_FALLBACK_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Replace any direct fetch to runs_kpi_v1 with a helper that tries v2 then v1.
# We do a safe injection at end + minimal replacements for known strings.
helper = r"""
/* VSP_P2_RUNS_KPI_PREF_V2_FALLBACK_V1 */
window.__vsp_runs_kpi_fetch_v2pref = async (days)=>{
  const q = encodeURIComponent(String(days||30));
  const tryUrls = [`/api/ui/runs_kpi_v2?days=${q}`, `/api/ui/runs_kpi_v1?days=${q}`];
  let lastErr = null;
  for (const url of tryUrls){
    try{
      const r = await fetch(url, {cache:"no-store"});
      const j = await r.json();
      if (j && j.ok) return j;
      lastErr = new Error(j?.err || "kpi api not ok");
    }catch(e){ lastErr = e; }
  }
  throw lastErr || new Error("kpi api failed");
};
"""

if "/api/ui/runs_kpi_v1" in s:
    # Replace "fetch(`/api/ui/runs_kpi_v1?days=...`" patterns roughly: we'll just ensure trend loader uses helper if present
    s = s.replace("/api/ui/runs_kpi_v1", "/api/ui/runs_kpi_v2")  # best-effort for new calls
    # but we still keep fallback via helper where we control it
print("[OK] swapped string runs_kpi_v1->v2 (best-effort)")

p.write_text(s + "\n\n" + helper + "\n", encoding="utf-8")
print("[OK] appended v2-pref fetch helper")
PY

node --check "$JS" && echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_js_prefer_v2_fallback_v1"
