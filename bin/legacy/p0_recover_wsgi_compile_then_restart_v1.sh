#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

echo "== [0] compile current wsgi =="
if python3 -m py_compile "$WSGI" >/dev/null 2>&1; then
  echo "[OK] wsgi compiles: $WSGI"
else
  echo "[WARN] wsgi broken -> recovering from latest compiling backup"
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$WSGI" "${WSGI}.broken_${TS}" || true
  echo "[BACKUP] ${WSGI}.broken_${TS}"

  GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile

w = Path("wsgi_vsp_ui_gateway.py")
cands = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"),
               key=lambda p: p.stat().st_mtime, reverse=True)
for p in cands:
    try:
        py_compile.compile(str(p), doraise=True)
        print(str(p))
        raise SystemExit(0)
    except Exception:
        pass
print("")
raise SystemExit(1)
PY
)" || true

  if [ -z "${GOOD:-}" ] || [ ! -f "$GOOD" ]; then
    echo "[ERR] cannot find compiling backup (wsgi_vsp_ui_gateway.py.bak_*)"
    echo "      Tip: you have a known good one: wsgi_vsp_ui_gateway.py.bak_relid_20251222_075023"
    exit 2
  fi

  cp -f "$GOOD" "$WSGI"
  echo "[OK] restored: $WSGI <= $GOOD"

  python3 -m py_compile "$WSGI"
  echo "[OK] compile restored wsgi: PASS"
fi

echo "== [1] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [2] quick check /vsp5 =="
curl -sS -I "$BASE/vsp5" | sed -n '1,10p' || true
echo "[DONE]"
