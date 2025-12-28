#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_runs_kpi_compact_v3.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_singlefetch_${TS}"
echo "[BACKUP] ${JS}.bak_singlefetch_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_kpi_compact_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_KPI_SINGLEFETCH_LOCK_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) add inFlight + lastTs guard near top of file (after window guard)
inject = r"""
  /* ===================== VSP_P2_KPI_SINGLEFETCH_LOCK_V1 ===================== */
  let __kpi_inflight = false;
  let __kpi_last_ts = 0;
  let __kpi_last_days = null;
  /* ===================== /VSP_P2_KPI_SINGLEFETCH_LOCK_V1 ===================== */
"""
# put after: window.__vsp_runs_kpi_compact_v3 = true;
s, n1 = re.subn(r'(window\.__vsp_runs_kpi_compact_v3\s*=\s*true;\s*\n)', r'\1'+inject+"\n", s, count=1)

# 2) wrap fetchKpi(days) with throttle + timeout
def repl_fetch(m):
    body = m.group(0)
    if "AbortController" in body:
        return body
    return re.sub(
        r'async function fetchKpi\s*\(\s*days\s*\)\s*\{',
        r'''async function fetchKpi(days){
    const now = Date.now();
    const d = String(days||30);
    // throttle: same days within 3s => skip refetch
    if (__kpi_inflight) return null;
    if (__kpi_last_days === d and (now - __kpi_last_ts) < 3000) return null;
    __kpi_inflight = true;
    __kpi_last_days = d;
    __kpi_last_ts = now;
    const ac = new AbortController();
    const t = setTimeout(()=>ac.abort(), 2500);
    try{'''.replace("and","&&"),
        body,
        count=1
    )

s = re.sub(r'async function fetchKpi\s*\(\s*days\s*\)\s*\{[\s\S]*?\n\s*\}', repl_fetch, s, count=1)

# add finally block after fetch loop if not present
if "__kpi_inflight = false" not in s:
    s = re.sub(r'(throw lastErr \|\| new Error\("kpi fetch failed"\);\s*\n\s*\})',
               r'''throw lastErr || new Error("kpi fetch failed");
    } finally {
      try{ clearTimeout(t); }catch(_){}
      __kpi_inflight = false;
    }
  }''', s, count=1)

p.write_text(s, encoding="utf-8")
print(f"[OK] patched single-fetch lock (n1={n1})")
PY

node --check "$JS" >/dev/null && echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_compact_singlefetch_lock_v1"
