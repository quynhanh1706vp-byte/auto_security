#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_REWRITE_KPI_V4_MOUNT_BY_INDEX_V4"

cp -f "$F" "${F}.bak_kpimount_v4_${TS}"
echo "[BACKUP] ${F}.bak_kpimount_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, sys

MARK="VSP_P2_REWRITE_KPI_V4_MOUNT_BY_INDEX_V4"
p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(errors="ignore").splitlines(True)

# 1) find anchor line: "_app_v4 = _vsp_pick_flask_app_v4()"
anchor = None
for i,l in enumerate(lines):
    if "_app_v4 = _vsp_pick_flask_app_v4()" in l:
        anchor = i
        break
if anchor is None:
    print("[ERR] cannot find anchor: _app_v4 = _vsp_pick_flask_app_v4()")
    sys.exit(2)

# 2) find nearest "try:" above anchor (within 25 lines)
try_i = None
for j in range(anchor, max(-1, anchor-25), -1):
    if re.match(r'^[ \t]*try:\s*(#.*)?$', lines[j].rstrip("\n")):
        try_i = j
        break
if try_i is None:
    print("[ERR] cannot find try: above anchor within 25 lines")
    print("anchor_line=", anchor+1)
    sys.exit(3)

# 3) find end marker line for KPI_V4 block
end_i = None
end_re = re.compile(r'^[ \t]*#\s*====================\s*/VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1\s*====================\s*$')
for k in range(anchor, min(len(lines), anchor+80)):
    if end_re.match(lines[k].rstrip("\n")):
        end_i = k
        break
if end_i is None:
    print("[ERR] cannot find end marker '/VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1' within 80 lines")
    print("anchor_line=", anchor+1)
    sys.exit(4)

indent_try = re.match(r'^([ \t]*)', lines[try_i]).group(1)
in1 = indent_try + "    "
in2 = in1 + "    "

# Clean block with correct indentation (end marker kept as-is)
new_block = []
new_block.append(indent_try + "try:\n")
new_block.append(in1 + "_app_v4 = _vsp_pick_flask_app_v4()\n")
new_block.append(in1 + "if _app_v4 is not None:\n")
new_block.append(in2 + "_app_v4.add_url_rule(\n")
new_block.append(in2 + '    "/api/ui/runs_kpi_v4",\n')
new_block.append(in2 + '    "vsp_ui_runs_kpi_v4",\n')
new_block.append(in2 + "    vsp_ui_runs_kpi_v4,\n")
new_block.append(in2 + '    methods=["GET"],\n')
new_block.append(in2 + ")\n")
new_block.append(in2 + 'print("[VSP_KPI_V4] mounted /api/ui/runs_kpi_v4")\n')
new_block.append(in1 + "else:\n")
new_block.append(in2 + 'print("[VSP_KPI_V4] no Flask app found to mount")\n')
new_block.append(indent_try + "except Exception as _e:\n")
new_block.append(in1 + "try:\n")
new_block.append(in2 + "import os as _os\n")
new_block.append(in2 + 'if _os.environ.get("VSP_SAFE_DISABLE_KPI_V4","1") == "1":\n')
new_block.append(in2 + "    " + 'print("[VSP_KPI_V4] mount skipped by VSP_SAFE_DISABLE_KPI_V4=1")\n')
new_block.append(in2 + "else:\n")
new_block.append(in2 + "    " + 'print("[VSP_KPI_V4] mount failed:", _e)\n')
new_block.append(in1 + "except Exception:\n")
new_block.append(in2 + 'print("[VSP_KPI_V4] mount failed:", _e)\n')
new_block.append(indent_try + f"# ===================== {MARK} =====================\n")

# Replace region: [try_i, end_i) i.e. keep end marker line untouched
before = "".join(lines[:try_i])
after  = "".join(lines[end_i:])  # includes end marker
s2 = before + "".join(new_block) + after
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] rewrite KPI_V4 mount OK + py_compile OK")
print("[OK] replaced lines", try_i+1, "to", end_i, "(end marker kept at", end_i+1, ")")
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
sudo journalctl -u "$SVC" -n 160 --no-pager | grep -n "VSP_KPI_V4" | tail -n 40 || true
