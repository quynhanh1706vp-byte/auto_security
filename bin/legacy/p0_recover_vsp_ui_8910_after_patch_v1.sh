#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need systemctl; need bash; need ls; need tail; need sed; need grep

echo "== [0] quick status =="
systemctl --no-pager status "$SVC" -n 25 || true

echo "== [1] py_compile current wsgi =="
if python3 -m py_compile "$WSGI" 2>/tmp/vsp_wsgicheck.err; then
  echo "[OK] wsgi py_compile OK"
else
  echo "[ERR] wsgi py_compile FAILED (show tail):"
  tail -n 40 /tmp/vsp_wsgicheck.err || true

  echo "== [1b] find latest backup to rollback =="
  # pick newest backup (mtime) among ridlatest backups; fallback to any .bak_*
  bak="$(ls -1t ${WSGI}.bak_ridlatest_v1b_* 2>/dev/null | head -n 1 || true)"
  [ -n "$bak" ] || bak="$(ls -1t ${WSGI}.bak_ridlatest_* 2>/dev/null | head -n 1 || true)"
  [ -n "$bak" ] || bak="$(ls -1t ${WSGI}.bak_* 2>/dev/null | head -n 1 || true)"

  if [ -z "$bak" ]; then
    echo "[FATAL] no backup found to rollback."
    exit 2
  fi

  echo "[ROLLBACK] restore $bak -> $WSGI"
  cp -f "$bak" "$WSGI"

  echo "== [1c] py_compile after rollback =="
  python3 -m py_compile "$WSGI"
  echo "[OK] rollback py_compile OK"
fi

echo "== [2] restart service =="
systemctl restart "$SVC" || true

echo "== [3] wait a moment and re-check =="
sleep 0.5
systemctl --no-pager status "$SVC" -n 25 || true

echo "== [4] port check (:8910) =="
if command -v ss >/dev/null 2>&1; then
  ss -ltnp | grep -E '(:8910)\b' || true
elif command -v netstat >/dev/null 2>&1; then
  netstat -ltnp 2>/dev/null | grep -E '(:8910)\b' || true
fi

echo "== [5] curl smoke =="
curl -fsS --connect-timeout 1 "$BASE/vsp5" >/dev/null && echo "[OK] /vsp5 reachable" || echo "[ERR] /vsp5 still not reachable"
curl -fsS --connect-timeout 1 "$BASE/api/vsp/runs?limit=1&offset=0" >/dev/null && echo "[OK] /api/vsp/runs reachable" || echo "[WARN] /api/vsp/runs not reachable"

echo "== [6] if still failing, show last logs =="
if ! curl -fsS --connect-timeout 1 "$BASE/vsp5" >/dev/null 2>&1; then
  echo "--- journalctl -u $SVC (last 120 lines) ---"
  journalctl -u "$SVC" --no-pager -n 120 || true
fi
