#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

JS="static/js/vsp_dash_only_v1.js"
W="wsgi_vsp_ui_gateway.py"
PYAPP="vsp_demo_app.py"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
[ -f "$W" ]  || { echo "[ERR] missing $W"; exit 2; }
[ -f "$PYAPP" ] || { echo "[ERR] missing $PYAPP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS"   "${JS}.bak_cleanpack_${TS}"
cp -f "$W"    "${W}.bak_cleanpack_${TS}"
cp -f "$PYAPP" "${PYAPP}.bak_cleanpack_${TS}"
echo "[BACKUP] ${JS}.bak_cleanpack_${TS}"
echo "[BACKUP] ${W}.bak_cleanpack_${TS}"
echo "[BACKUP] ${PYAPP}.bak_cleanpack_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

js = Path("static/js/vsp_dash_only_v1.js").read_text(encoding="utf-8", errors="replace")

# 1) Remove known “temporary/experimental” blocks (keep core ones)
#    (Safe: only removes if both start+end markers exist)
DROP_BLOCKS = [
  "VSP_P0_TOPFIND_OVERLAY_AUTOLOAD_V3",
  "VSP_P0_TOPFIND_UI_CAPTURE_PANEL_V2",
  "VSP_P0_TOPFIND_UI_RENDER_V4_SEMGREP_V1",   # we rely on INJECT_V1E renderer
  "VSP_P0_TOPFIND_COUNTS_ONLY_MSG_V1",
  "VSP_P0_DISABLE_RID_RELOAD_LOOP_V1",        # keep if you want; but usually now not needed
]
for m in DROP_BLOCKS:
  pat = re.compile(r"/\*\s*====================\s*"+re.escape(m)+r".*?/\*\s*====================\s*/"+re.escape(m)+r"\s*====================\s*\*/", re.S)
  if pat.search(js):
    js = pat.sub(f"/* {m} (removed by CLEAN_PACK) */", js)
    print("[OK] removed block:", m)

# 2) Make MIN_STABLE debug-only (commercial clean)
#    Robust patch: gate at the early guard line if present.
#    If the file contains __VSP_P0_DASH_MIN_STABLE_V1, make it run only when ?debug=1
def gate_min_stable(s:str)->str:
  # Try several common guard patterns
  reps = 0
  # pattern A: if (window.__VSP_P0_DASH_MIN_STABLE_V1) return;
  pA = re.compile(r'if\s*\(\s*window\.__VSP_P0_DASH_MIN_STABLE_V1\s*\)\s*return\s*;')
  if pA.search(s):
    s = pA.sub('if (window.__VSP_P0_DASH_MIN_STABLE_V1) return; if (new URLSearchParams(location.search).get("debug")!=="1") return;', s, count=1)
    reps += 1

  # pattern B: if (window.__VSP_P0_DASH_MIN_STABLE_V1) return;
  pB = re.compile(r'if\s*\(\s*window\.__VSP_P0_DASH_MIN_STABLE_V1\s*\)\s*return;')
  if reps==0 and pB.search(s):
    s = pB.sub('if (window.__VSP_P0_DASH_MIN_STABLE_V1) return; if (new URLSearchParams(location.search).get("debug")!=="1") return;', s, count=1)
    reps += 1

  return s, reps

js2, reps = gate_min_stable(js)
if reps:
  js = js2
  print("[OK] MIN_STABLE => debug-only (?debug=1)")

# 3) Assert that the required core markers exist (do NOT delete them)
REQUIRED = [
  "VSP_P0_RID_LATEST_ENDWRAP_V4_STRICT",   # in wsgi, checked separately
  "VSP_P0_TOPFIND_INJECT_MAIN_PANEL_V1E",
  "VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1C",
  "VSP_P0_DASH_WIRE_MAIN_TOPFIND_V1D",
]
for r in REQUIRED[1:]:
  if r not in js:
    print("[WARN] required marker not found in JS:", r)

Path("static/js/vsp_dash_only_v1.js").write_text(js, encoding="utf-8")
print("[OK] wrote JS clean pack")
PY

node --check "$JS"
echo "[OK] node --check passed"

# restart
systemctl restart "$SVC" 2>/dev/null || true

echo "== [SELF-CHECK 1] rid_latest_gate_root header ENDWRAP_V4 =="
curl -sS -I "$BASE/api/vsp/rid_latest_gate_root" | egrep -i 'HTTP/|X-VSP-RIDPICK|Content-Type|Cache-Control' || true
RID="$(curl -sS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"

echo "== [SELF-CHECK 2] top_findings_v4 ok + items>0 =="
curl -sS "$BASE/api/vsp/top_findings_v4?rid=$RID&limit=5" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "items=", len(j.get("items") or []), "source=", j.get("source"))
if not j.get("ok"): raise SystemExit(2)
if len(j.get("items") or [])==0: raise SystemExit(3)
PY

echo "== [SELF-CHECK 3] /vsp5 includes vsp_dash_only_v1.js =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dash_only_v1.js" | head -n 3

echo
echo "[DONE] Commercial clean pack OK."
echo " - /vsp5 : bản thương mại sạch (MIN_STABLE ẩn)."
echo " - /vsp5?debug=1 : bật MIN_STABLE panel để debug nhanh."
echo "Next: chốt luôn auto-refresh hợp lý (no loop) + export/report wiring."
