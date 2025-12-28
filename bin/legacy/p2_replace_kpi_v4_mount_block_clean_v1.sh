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
MARK="VSP_P2_REPLACE_KPI_V4_MOUNT_BLOCK_CLEAN_V1"

cp -f "$F" "${F}.bak_kpiblk_${TS}"
echo "[BACKUP] ${F}.bak_kpiblk_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

# Find the broken block exactly (from 'try:\n    _app_v4 = _vsp_pick_flask_app_v4()' up to the line that prints mount failed)
start_pat = r'\ntry:\n\s+_app_v4\s*=\s*_vsp_pick_flask_app_v4\(\)\n'
end_pat   = r'\n\s*print\("\[VSP_KPI_V4\]\s*mount failed:",\s*_e\)\n'

m1 = re.search(start_pat, s)
m2 = re.search(end_pat, s)
if not m1 or not m2:
    print("[ERR] cannot locate KPI_V4 mount block to replace")
    sys.exit(2)

start = m1.start() + 1  # keep leading newline
end = m2.end()

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
""").strip("\n") + "\n"

s2 = s[:start] + replacement + s[end:]
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] replaced KPI_V4 mount block + py_compile OK:", MARK)
PY

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC" || true
sleep 0.6
sudo systemctl status "$SVC" -l --no-pager || true

echo "== quick probe =="
for u in /vsp5 /api/vsp/rid_latest /api/ui/settings_v2 /api/ui/rule_overrides_v2 /api/vsp/dash_kpis /api/vsp/dash_charts; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

echo "== KPI_V4 tail =="
sudo journalctl -u "$SVC" -n 140 --no-pager | grep -n "VSP_KPI_V4" | tail -n 40 || true
