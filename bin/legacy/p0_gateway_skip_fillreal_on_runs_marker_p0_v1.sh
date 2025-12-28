#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_skip_fillreal_runs_${TS}"
echo "[BACKUP] ${F}.bak_skip_fillreal_runs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_SKIP_FILLREAL_ON_RUNS_MARKER_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) Extend the "inject fillreal" guard(s) to skip if standalone runs marker exists in html
# Typical pattern (you already saw in grep):
# if ("vsp_fill_real_data_5tabs_p1_v1.js" not in html) and ("VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" not in html):
pat = r'if\s*\(\s*"vsp_fill_real_data_5tabs_p1_v1\.js"\s+not\s+in\s+html\s*\)\s*and\s*\(\s*"VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY"\s+not\s+in\s+html\s*\)\s*:'
rep = (
    'if ("vsp_fill_real_data_5tabs_p1_v1.js" not in html) and ("VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" not in html)'
    ' and ("VSP_RUNS_STANDALONE_HARDFIX_P0_V2" not in html)'
    ' and ("VSP_RUNS_PAGE_FACTORY_RESET_STATIC_P0_V1" not in html):'
    f'  # {MARK}'
)
s2, n1 = re.subn(pat, rep, s)

# 2) Also handle variants that only check one side (defensive)
pat2 = r'if\s*\(\s*"vsp_fill_real_data_5tabs_p1_v1\.js"\s+not\s+in\s+html\s*\)\s*:'
rep2 = (
    'if ("vsp_fill_real_data_5tabs_p1_v1.js" not in html)'
    ' and ("VSP_RUNS_STANDALONE_HARDFIX_P0_V2" not in html)'
    ' and ("VSP_RUNS_PAGE_FACTORY_RESET_STATIC_P0_V1" not in html):'
    f'  # {MARK}'
)
s3, n2 = re.subn(pat2, rep2, s2)

p.write_text(s3, encoding="utf-8")
print(f"[OK] patched {p} (guards_fixed={n1}, simple_fixed={n2})")
PY

# restart
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify /runs no fillreal injector =="
curl -sS http://127.0.0.1:8910/runs | grep -n "vsp_fill_real_data_5tabs_p1_v1\\.js" || echo "[OK] no fillreal on /runs"
echo "== verify API =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=2" | sed -n '1,12p'
