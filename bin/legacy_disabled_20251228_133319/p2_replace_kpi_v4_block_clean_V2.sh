#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_REPLACE_KPI_V4_BLOCK_CLEAN_V2"

cp -f "$F" "${F}.bak_kpiV2_${TS}"
echo "[BACKUP] ${F}.bak_kpiV2_${TS}"

python3 - <<PY
from pathlib import Path
import re, textwrap, py_compile, sys

MARK = "${MARK}"
p = Path("${F}")
s = p.read_text(errors="ignore")

if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

# Replace the whole KPI_V4 mount block safely
pat = re.compile(
    r"""
(?P<blk>
^try:\s*\n
[ \t]+_app_v4[ \t]*=[ \t]*_vsp_pick_flask_app_v4\(\)[^\n]*\n
(?:.*?\n)
^[ \t]*#\s*====================\s*/VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1\s*====================\s*\n
)
""",
    re.M | re.S | re.X
)

m = pat.search(s)
if not m:
    print("[ERR] cannot find KPI_V4 block to replace (pattern not found)")
    sys.exit(2)

replacement = textwrap.dedent(f"""
try:
    _app_v4 = _vsp_pick_flask_app_v4()
    if _app_v4 is not None:
        _app_v4.add_url_rule("/api/ui/runs_kpi_v4", "vsp_ui_runs_kpi_v4", vsp_ui_runs_kpi_v4, methods=["GET"])
        print("[VSP_KPI_V4] mounted /api/ui/runs_kpi_v4")
    else:
        print("[VSP_KPI_V4] no Flask app found to mount")
except Exception as _e:
    try:
        import os as _os
        if _os.environ.get("VSP_SAFE_DISABLE_KPI_V4","1") == "1":
            print("[VSP_KPI_V4] mount skipped by VSP_SAFE_DISABLE_KPI_V4=1")
        else:
            print("[VSP_KPI_V4] mount failed:", _e)
    except Exception:
        print("[VSP_KPI_V4] mount failed:", _e)

# ===================== {MARK} =====================
# ===================== /VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1 =====================
""")

s2 = s[:m.start("blk")] + replacement + s[m.end("blk"):]
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] replaced KPI_V4 block + py_compile OK:", MARK)
PY

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC" || true
sleep 0.6
sudo systemctl status "$SVC" -l --no-pager || true

echo "== quick probe =="
for u in /vsp5 /api/vsp/rid_latest /api/ui/settings_v2 /api/ui/rule_overrides_v2; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

echo "== KPI_V4 log tail =="
sudo journalctl -u "$SVC" -n 140 --no-pager | grep -n "VSP_KPI_V4" | tail -n 30 || true
