#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need tail; need date
command -v systemctl >/dev/null 2>&1 || true
command -v journalctl >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

echo "== [0] compile check =="
if python3 -m py_compile "$WSGI" >/dev/null 2>&1; then
  echo "[OK] wsgi compiles"
else
  echo "[WARN] wsgi broken -> try restore latest bak_fixvsp5"
  BAK="$(ls -1t ${WSGI}.bak_fixvsp5_* 2>/dev/null | head -n1 || true)"
  if [ -n "$BAK" ] && [ -f "$BAK" ]; then
    echo "[RESTORE] $BAK -> $WSGI"
    cp -f "$BAK" "$WSGI"
  else
    echo "[WARN] no bak_fixvsp5 found -> try restore latest compiling backup of any kind"
    # pick newest .bak* that compiles
    GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile
w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak*"), key=lambda p: p.stat().st_mtime, reverse=True)
for p in baks[:80]:
    try:
        py_compile.compile(str(p), doraise=True)
        print(p)
        break
    except Exception:
        pass
PY
)"
    if [ -n "$GOOD" ] && [ -f "$GOOD" ]; then
      echo "[RESTORE] $GOOD -> $WSGI"
      cp -f "$GOOD" "$WSGI"
    else
      echo "[ERR] cannot find a compiling backup to restore"; exit 3
    fi
  fi

  echo "== [0b] compile check after restore =="
  python3 -m py_compile "$WSGI" >/dev/null
  echo "[OK] restored wsgi compiles"
fi

echo "== [1] restart service =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 0.6

echo "== [2] show service status (short) =="
systemctl --no-pager --full status "$SVC" 2>/dev/null | sed -n '1,18p' || true

echo "== [3] check listener :8910 =="
ss -ltnp 2>/dev/null | grep -E ':(8910)\b' || echo "[WARN] not listening on 8910"

echo "== [4] curl /vsp5 head =="
curl -sS -I "$BASE/vsp5" 2>/dev/null | sed -n '1,12p' || echo "[ERR] curl failed"

echo "== [5] last logs (if available) =="
journalctl -u "$SVC" --no-pager -n 40 2>/dev/null || true

echo "[DONE]"
