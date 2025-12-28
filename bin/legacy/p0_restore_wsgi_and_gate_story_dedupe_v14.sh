#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

WSGI="wsgi_vsp_ui_gateway.py"
GS="static/js/vsp_dashboard_gate_story_v1.js"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
[ -f "$GS" ]   || { echo "[ERR] missing $GS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_before_v14_${TS}"
echo "[BACKUP] ${WSGI}.bak_before_v14_${TS}"

echo "== restore latest compiling backup of WSGI =="
python3 - <<'PY'
from pathlib import Path
import py_compile, os, sys, time

w = Path("wsgi_vsp_ui_gateway.py")
baks = [p for p in Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*") if p.is_file()]
baks = sorted(baks, key=lambda p: p.stat().st_mtime, reverse=True)

def ok(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

good = None
for p in baks:
    if ok(p):
        good = p
        break

if not good:
    print("[ERR] cannot find any compiling backup for wsgi_vsp_ui_gateway.py")
    sys.exit(2)

src = good.read_text(encoding="utf-8", errors="replace")
w.write_text(src, encoding="utf-8")
py_compile.compile(str(w), doraise=True)
print("[OK] restored from:", good.name)
PY

echo "== patch GateStory: dedupe guard (even if loaded twice) =="
cp -f "$GS" "${GS}.bak_dedupe_${TS}"
echo "[BACKUP] ${GS}.bak_dedupe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_GATE_STORY_DEDUPE_GUARD_V14"
if marker in s:
    print("[SKIP] already patched:", marker)
else:
    # Wrap whole file in "if not loaded" guard
    head = (
        f"/* {marker} : prevent double execution when script is included twice */\n"
        "if (window.__vsp_gate_story_v1_loaded) {\n"
        "  console.debug('[VSP][GateStory] dedupe: already loaded, skip');\n"
        "} else {\n"
        "  window.__vsp_gate_story_v1_loaded = true;\n"
    )
    tail = "\n}\n"
    p.write_text(head + s + tail, encoding="utf-8")
    print("[OK] injected gate-story dedupe guard")
PY

echo "== py_compile WSGI =="
python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

echo "== restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /vsp5 scripts (duplicates OK; GateStory now deduped at runtime) =="
curl -fsS "$BASE/vsp5" | egrep -n "vsp_bundle_commercial_v2|vsp_dashboard_gate_story_v1|vsp_dashboard_containers_fix_v1|vsp_dashboard_luxe_v1" | head -n 50

echo "[DONE] Ctrl+Shift+R /vsp5"
