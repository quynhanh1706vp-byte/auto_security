#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
SNAP="${WSGI}.bak_broken_${TS}"
cp -f "$WSGI" "$SNAP"
echo "[SNAPSHOT BROKEN] $SNAP"

echo "== find latest compiling backup of WSGI =="
BEST="$(python3 - <<'PY'
from pathlib import Path
import py_compile

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(w.parent.glob(w.name + ".bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

for p in baks:
    try:
        py_compile.compile(str(p), doraise=True)
        print(str(p))
        break
    except Exception:
        continue
PY
)"

[ -n "${BEST:-}" ] || { echo "[ERR] no compiling backup found"; exit 3; }
echo "[RESTORE] $BEST -> $WSGI"
cp -f "$BEST" "$WSGI"

echo "== compile check restored =="
python3 -m py_compile "$WSGI"

echo "== restart service =="
systemctl restart "$SVC" 2>/dev/null || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== quick verify =="
curl -fsS -I "$BASE/vsp5" | head -n 3 || true
curl -fsS "$BASE/api/vsp/healthz" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("HEALTHZ ok=",j.get("ok"),"release=",j.get("release_status"),"rid_latest=",j.get("rid_latest_gate_root"))'
echo "[DONE] autorescue wsgi ok."
