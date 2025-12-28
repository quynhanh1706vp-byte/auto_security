#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_RESCUE_AND_REWRITE_KPI_V4_BLOCK_V3"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [0] find newest backup that py_compile OK =="
BEST="$(python3 - <<'PY'
import glob, os, py_compile, sys

F="wsgi_vsp_ui_gateway.py"
cands = sorted(glob.glob(F+".bak_*"), key=os.path.getmtime, reverse=True)
def ok(p):
    try:
        py_compile.compile(p, doraise=True)
        return True
    except Exception:
        return False

for p in cands:
    if ok(p):
        print(p); sys.exit(0)
print("")
sys.exit(3)
PY
)"

if [ -z "${BEST:-}" ]; then
  echo "[ERR] No compiling backup found. Listing newest 12 backups:"
  ls -1t "${F}.bak_"* 2>/dev/null | head -n 12 || true
  exit 3
fi
echo "[OK] BEST=$BEST"

echo "== [1] restore BEST -> $F (save current as .bad) =="
cp -f "$F" "${F}.bad_${TS}"
cp -f "$BEST" "$F"
echo "[OK] saved old as ${F}.bad_${TS}"

echo "== [2] rewrite KPI_V4 mount block cleanly (pattern-based) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile, sys

MARK="VSP_P2_RESCUE_AND_REWRITE_KPI_V4_BLOCK_V3"
p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

# match the KPI_V4 mount block:
# start: try: + _app_v4 = _vsp_pick_flask_app_v4()
# must contain: "/api/ui/runs_kpi_v4"
# end: marker "/VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1"
pat = re.compile(
    r'(?ms)^try:\s*\n'
    r'[ \t]+_app_v4\s*=\s*_vsp_pick_flask_app_v4\(\)\s*\n'
    r'.*?/api/ui/runs_kpi_v4.*?\n'
    r'^#\s*====================\s*/VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1\s*====================\s*\n'
)

m = pat.search(s)
if not m:
    print("[ERR] cannot find KPI_V4 block by pattern. Aborting to avoid damaging file.")
    # print hint around possible occurrences
    for key in ("_vsp_pick_flask_app_v4", "/api/ui/runs_kpi_v4", "VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1"):
        idx = s.find(key)
        print("hint", key, "pos", idx)
    sys.exit(2)

replacement = textwrap.dedent(f"""\
try:
    _app_v4 = _vsp_pick_flask_app_v4()
    if _app_v4 is not None:
        _app_v4.add_url_rule(
            "/api/ui/runs_kpi_v4",
            "vsp_ui_runs_kpi_v4",
            vsp_ui_runs_kpi_v4,
            methods=["GET"],
        )
        print("[VSP_KPI_V4] mounted /api/ui/runs_kpi_v4")
    else:
        print("[VSP_KPI_V4] no Flask app found to mount")
except Exception as _e:
    try:
        import os as _os
        if _os.environ.get("VSP_SAFE_DISABLE_KPI_V4", "1") == "1":
            print("[VSP_KPI_V4] mount skipped by VSP_SAFE_DISABLE_KPI_V4=1")
        else:
            print("[VSP_KPI_V4] mount failed:", _e)
    except Exception:
        print("[VSP_KPI_V4] mount failed:", _e)

# ===================== {MARK} =====================
# ===================== /VSP_P0_RUNS_KPI_V4_TREND_SERVER_SIDE_V1 =====================
""")

s2 = s[:m.start()] + replacement + s[m.end():]
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] rewrite OK + py_compile OK:", MARK)
PY

echo "== [3] restart service =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC"
sleep 0.6
sudo systemctl status "$SVC" -l --no-pager || true

echo "== [4] quick probe (expect 200) =="
for u in /vsp5 /api/vsp/rid_latest /api/ui/settings_v2 /api/ui/rule_overrides_v2 /api/vsp/dash_kpis /api/vsp/dash_charts; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

echo "== [5] KPI_V4 log tail =="
sudo journalctl -u "$SVC" -n 160 --no-pager | grep -n "VSP_KPI_V4" | tail -n 40 || true
