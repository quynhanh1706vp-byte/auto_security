#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_CLEANUP_AUTOFIX_AND_USE_RID_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_cleanup_${TS}"
echo "[BACKUP] ${JS}.bak_cleanup_${TS}"

python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, re

js_path = sys.argv[1]
mark = sys.argv[2]

p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="ignore")

# 1) Disable the risky AUTOFIX blocks (they can hide big containers => blank dashboard)
def disable_block(src: str, begin: str, end: str) -> str:
    if begin not in src or end not in src:
        return src
    # non-greedy block replace between markers
    pattern = re.escape(begin) + r".*?" + re.escape(end)
    repl = begin + "\n// [DISABLED] This block was too aggressive for layout; truefix is done elsewhere.\n" + end
    return re.sub(pattern, repl, src, flags=re.S)

s2 = s
s2 = disable_block(s2,
    "/* ===================== VSP_P3_AUTOFIX_KPI_DEGRADED_V1 ===================== */",
    " /* ===================== /VSP_P3_AUTOFIX_KPI_DEGRADED_V1 ===================== */"
)
s2 = disable_block(s2,
    "/* ===================== VSP_P3_AUTOFIX_KPI_DEGRADED_V2 ===================== */",
    " /* ===================== /VSP_P3_AUTOFIX_KPI_DEGRADED_V2 ===================== */"
)
s2 = disable_block(s2,
    "/* ===================== VSP_P3_AUTOFIX_KPI_DEGRADED_V3 ===================== */",
    " /* ===================== /VSP_P3_AUTOFIX_KPI_DEGRADED_V3 ===================== */"
)

# 2) Make dash_kpis fetch use CURRENT rid (query param) instead of window.__vsp_rid_latest
# You have: var k=await fetchJson(vspWithRid("/api/vsp/dash_kpis", (window.__vsp_rid_latest||"")));
# Replace arg with: (rid||window.__vsp_rid_latest||"")
s2_new = re.sub(
    r'\(window\.__vsp_rid_latest\|\|""\)',
    r'(rid||window.__vsp_rid_latest||"")',
    s2
)
# also handle single-quote variant if any
s2_new = re.sub(
    r"\(window\.__vsp_rid_latest\|\|''\)",
    r"(rid||window.__vsp_rid_latest||'')",
    s2_new
)

# 3) Ensure dash_kpis cache exists after the await line (if not already)
pat_fetch = r'(var\s+k\s*=\s*await\s+fetchJson\(\s*vspWithRid\(\s*"/api/vsp/dash_kpis"[^\)]*\)\s*\)\s*;)'
if re.search(pat_fetch, s2_new):
    s2_new = re.sub(
        pat_fetch,
        r'\1\n      try{ window.__vsp_dashkpis_cache = k || null; }catch(_){ }\n',
        s2_new,
        count=1
    )

if s2_new == s:
    print("[WARN] no changes detected (already cleaned?)")
else:
    s2 = s2_new

# 4) Add marker footer
if mark not in s2:
    s2 += f"\n/* {mark} */\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker present =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing"; exit 2; }

echo "[DONE] Cleanup applied. Now HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
