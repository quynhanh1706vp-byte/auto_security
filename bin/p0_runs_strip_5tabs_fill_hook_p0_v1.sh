#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_runs_reports_v1.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$TPL" "${TPL}.bak_strip_fill_${TS}"
echo "[BACKUP] ${TPL}.bak_strip_fill_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("templates/vsp_runs_reports_v1.html")
s = p.read_text(encoding="utf-8", errors="replace")

# remove the gateway block if present
s2 = re.sub(
    r"\s*<!--\s*VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY\s*-->.*?<!--\s*/VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY\s*-->\s*",
    "\n",
    s,
    flags=re.S|re.I
)

# also remove direct script tag if someone inserted it without the block
s2 = re.sub(
    r"\s*<script[^>]+src=['\"]/static/js/vsp_fill_real_data_5tabs_p1_v1\.js['\"][^>]*>\s*</script>\s*",
    "\n",
    s2,
    flags=re.I
)

if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("[OK] stripped vsp_fill_real_data_5tabs_p1_v1.js from /runs template")
else:
    print("[OK] nothing to strip (already clean)")
PY

echo "== quick verify: /runs should NOT include vsp_fill_real_data_5tabs_p1_v1.js =="
curl -sS http://127.0.0.1:8910/runs | grep -n "vsp_fill_real_data_5tabs_p1_v1.js" || echo "[OK] clean"

# restart UI
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify body not empty =="
curl -sS http://127.0.0.1:8910/runs | wc -c
