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

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_kpiskip_v2_${TS}"
echo "[BACKUP] ${F}.bak_kpiskip_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, sys

MARK="VSP_P2_KPI_V4_SKIP_BEFORE_PICK_V2"

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")
if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

lines = s.splitlines(True)

# find anchor line of KPI_V4 mount
anchor = None
for i,l in enumerate(lines):
    if "_app_v4 = _vsp_pick_flask_app_v4()" in l:
        anchor = i
        break
if anchor is None:
    print("[ERR] cannot find anchor: _app_v4 = _vsp_pick_flask_app_v4()")
    sys.exit(2)

# find nearest try: above anchor (within 35 lines)
try_i = None
for j in range(anchor, max(-1, anchor-35), -1):
    if re.match(r'^[ \t]*try:\s*(#.*)?$', lines[j].rstrip("\n")):
        try_i = j
        break
if try_i is None:
    print("[ERR] cannot find try: above KPI_V4 mount near anchor line", anchor+1)
    sys.exit(3)

# find end marker line containing "/VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1"
end_i = None
for k in range(anchor, min(len(lines), anchor+150)):
    if "/VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1" in lines[k]:
        end_i = k
        break
if end_i is None:
    print("[ERR] cannot find end marker '/VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1' after anchor")
    sys.exit(4)

indent_try = re.match(r'^([ \t]*)', lines[try_i]).group(1)
in1 = indent_try + "    "
in2 = in1 + "    "
in3 = in2 + "    "

new_block = []
new_block.append(indent_try + "try:\n")
new_block.append(in1 + "import os as _os\n")
new_block.append(in1 + 'if _os.environ.get("VSP_SAFE_DISABLE_KPI_V4","1") == "1":\n')
new_block.append(in2 + 'print("[VSP_KPI_V4] mount skipped by VSP_SAFE_DISABLE_KPI_V4=1")\n')
new_block.append(in1 + "else:\n")
new_block.append(in2 + "_app_v4 = _vsp_pick_flask_app_v4()\n")
new_block.append(in2 + "if _app_v4 is not None:\n")
new_block.append(in3 + "_app_v4.add_url_rule(\n")
new_block.append(in3 + '    "/api/ui/runs_kpi_v4",\n')
new_block.append(in3 + '    "vsp_ui_runs_kpi_v4",\n')
new_block.append(in3 + "    vsp_ui_runs_kpi_v4,\n")
new_block.append(in3 + '    methods=["GET"],\n')
new_block.append(in3 + ")\n")
new_block.append(in3 + 'print("[VSP_KPI_V4] mounted /api/ui/runs_kpi_v4")\n')
new_block.append(in2 + "else:\n")
new_block.append(in3 + 'print("[VSP_KPI_V4] no Flask app found to mount")\n')
new_block.append(indent_try + "except Exception as _e:\n")
new_block.append(in1 + 'print("[VSP_KPI_V4] mount failed:", _e)\n')
new_block.append(indent_try + f"# ===================== {MARK} =====================\n")

# replace [try_i, end_i) and keep the end marker line intact
out = "".join(lines[:try_i]) + "".join(new_block) + "".join(lines[end_i:])
p.write_text(out, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] patched KPI_V4 guard + py_compile OK:", MARK)
print("[OK] replaced lines", try_i+1, "to", end_i, "(kept end marker line", end_i+1, ")")
PY

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC" || true
sleep 0.6
sudo systemctl status "$SVC" -l --no-pager || true

echo "== quick probe =="
for u in /vsp5 /api/vsp/rid_latest /api/vsp/dash_kpis /api/vsp/dash_charts /api/ui/settings_v2 /api/ui/rule_overrides_v2; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

echo "== KPI_V4 tail (should be skipped, not app_context error) =="
sudo journalctl -u "$SVC" -n 160 --no-pager | grep -n "VSP_KPI_V4" | tail -n 40 || true
