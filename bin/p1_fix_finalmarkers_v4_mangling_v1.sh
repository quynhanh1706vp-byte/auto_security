#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need tail; need curl; need grep

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_mangle_${TS}"
echo "[BACKUP] ${F}.bak_fix_mangle_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import sys, re

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

start = s.find("# --- VSP_P1_FINAL_MARKERS_FORCE_V4 ---")
end   = s.find("# --- end VSP_P1_FINAL_MARKERS_FORCE_V4 ---", start)
if start == -1 or end == -1:
    print("[ERR] V4 block not found")
    raise SystemExit(2)

blk = s[start:end]

# Fix name-mangling: __vsp_* inside class becomes _Class__vsp_* => NameError.
# Rename helpers to single-underscore.
blk2 = blk
blk2 = blk2.replace("def __vsp_v4_insert_before_body_end", "def _vsp_v4_insert_before_body_end")
blk2 = blk2.replace("def __vsp_v4_force_markers", "def _vsp_v4_force_markers")
blk2 = blk2.replace("__vsp_v4_insert_before_body_end(", "_vsp_v4_insert_before_body_end(")
blk2 = blk2.replace("__vsp_v4_force_markers(", "_vsp_v4_force_markers(")

# Safety: if class method got mangled reference already, fix that too (just in case)
blk2 = re.sub(r'\b_VspFinalMarkersMwV4__vsp_v4_force_markers\b', "_vsp_v4_force_markers", blk2)

if blk2 == blk:
    print("[WARN] no changes made (already fixed?)")
else:
    s2 = s[:start] + blk2 + s[end:]
    p.write_text(s2, encoding="utf-8")
    print("[OK] fixed V4 name-mangling (__vsp_* -> _vsp_*)")

PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

echo "== restart =="
systemctl restart "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 45 || true

echo "== smoke: must not be 500 now =="
BASE="http://127.0.0.1:8910"
curl -fsSI "$BASE/runs" | head -n 1
curl -fsSI "$BASE/vsp5" | head -n 1

echo "== smoke markers =="
curl -fsS "$BASE/vsp5" | grep -q 'data-testid="kpi_total"' && echo "[OK] vsp5 kpi_total present" || echo "[WARN] vsp5 kpi_total still missing"
curl -fsS "$BASE/runs" | grep -q 'id="vsp-runs-main"' && echo "[OK] runs main present" || echo "[WARN] runs main still missing"

echo "== tail error log =="
[ -f "$ERRLOG" ] && tail -n 40 "$ERRLOG" || true

echo "[NEXT] run gate: bash bin/p1_ui_spec_gate_v1.sh"
