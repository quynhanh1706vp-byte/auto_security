#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
ELOG="out_ci/ui_8910.error.log"

B="$(ls -1t ${F}.bak_dedupe_mark_* 2>/dev/null | head -n1 || true)"
[ -n "${B:-}" ] || { echo "[ERR] no bak_dedupe_mark backup found"; exit 2; }

echo "[ROLLBACK] $F <= $B"
cp -f "$B" "$F"

echo "== py_compile + import check =="
python3 -m py_compile "$F"
python3 - <<'PY'
import traceback
try:
    import wsgi_vsp_ui_gateway
    print("[OK] import wsgi_vsp_ui_gateway OK")
except Exception as e:
    print("[ERR] import failed:", repr(e))
    traceback.print_exc()
    raise SystemExit(3)
PY

echo "== truncate NEW error log =="
mkdir -p out_ci
sudo truncate -s 0 "$ELOG" || true

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true
sleep 0.8

echo "== ss listen :8910 =="
ss -ltnp | grep -E ':8910\b' || {
  echo "[FAIL] still not listening"
  echo "== status =="
  sudo systemctl --no-pager --full status "$SVC" | sed -n '1,160p' || true
  echo "== journal tail =="
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  echo "== error log tail =="
  tail -n 260 "$ELOG" 2>/dev/null || true
  exit 4
}

echo "== curl =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,25p' || true
echo "[OK] rollback done, 8910 is listening"
