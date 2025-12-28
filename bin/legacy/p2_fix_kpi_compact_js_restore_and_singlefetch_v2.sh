#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_runs_kpi_compact_v3.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

echo "== [1] snapshot current JS =="
cp -f "$JS" "${JS}.bak_broken_${TS}"
echo "[SNAPSHOT] ${JS}.bak_broken_${TS}"

echo "== [2] find latest backup that passes node --check and restore =="
python3 - <<'PY'
from pathlib import Path
import subprocess, sys

js = Path("static/js/vsp_runs_kpi_compact_v3.js")
baks = sorted(js.parent.glob(js.name + ".bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

def ok(p: Path)->bool:
    try:
        subprocess.check_call(["node","--check",str(p)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception:
        return False

# if current already ok -> keep
if ok(js):
    print("[OK] current JS already syntax-ok; no restore needed:", js)
    sys.exit(0)

for b in baks:
    if ok(b):
        js.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print("[OK] restored from:", b.name)
        sys.exit(0)

print("[ERR] cannot find any syntax-ok backup for", js)
sys.exit(2)
PY

echo "== [3] apply safe single-fetch lock (NO risky try-injection) =="
cp -f "$JS" "${JS}.bak_singlefetch_v2_${TS}"
echo "[BACKUP] ${JS}.bak_singlefetch_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_kpi_compact_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_KPI_SINGLEFETCH_LOCK_V2"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

# must be an IIFE with final "})();"
end = s.rfind("})();")
if end < 0:
    raise SystemExit("[ERR] cannot locate IIFE end '})();'")

inject = r"""
  /* ===================== VSP_P2_KPI_SINGLEFETCH_LOCK_V2 ===================== */
  let __kpi_inflight_v2 = false;
  let __kpi_last_key_v2 = null;
  let __kpi_last_at_v2  = 0;

  async function fetchKpiThrottled(days, force){
    const key = String(days||30);
    const now = Date.now();
    if (!force){
      if (__kpi_inflight_v2) return null;
      if (__kpi_last_key_v2 === key && (now - __kpi_last_at_v2) < 3000) return null;
    }
    __kpi_inflight_v2 = true;
    __kpi_last_key_v2 = key;
    __kpi_last_at_v2  = now;
    try{
      return await fetchKpi(days);
    } finally {
      __kpi_inflight_v2 = false;
    }
  }
  /* ===================== /VSP_P2_KPI_SINGLEFETCH_LOCK_V2 ===================== */
"""

# insert before end of IIFE
s = s[:end] + "\n" + inject + "\n" + s[end:]

# replace await fetchKpi(  -> await fetchKpiThrottled(
s2, n = re.subn(r'\bawait\s+fetchKpi\s*\(', 'await fetchKpiThrottled(', s)
# also replace "return fetchKpi(" if any
s2, n2 = re.subn(r'\breturn\s+fetchKpi\s*\(', 'return fetchKpiThrottled(', s2)

p.write_text(s2, encoding="utf-8")
print(f"[OK] inserted lock + rewired calls: await={n} return={n2}")
PY

echo "== [4] node --check =="
node --check "$JS" >/dev/null && echo "[OK] node --check OK"

echo "== [5] restart service =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

echo "== [6] sanity =="
echo "-- kpi v2 --"
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo
echo "-- /runs has placeholders + js include --"
curl -sS "$BASE/runs" | grep -n "VSP_P2_RUNS_KPI_PLACEHOLDERS_V1" >/dev/null && echo "[OK] placeholders present" || echo "[WARN] placeholders missing"
curl -sS "$BASE/runs" | grep -n "vsp_runs_kpi_compact_v3.js" >/dev/null && echo "[OK] compact JS included" || echo "[WARN] compact JS NOT included"

echo "[DONE] p2_fix_kpi_compact_js_restore_and_singlefetch_v2"
