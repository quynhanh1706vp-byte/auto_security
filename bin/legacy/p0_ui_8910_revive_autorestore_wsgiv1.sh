#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need systemctl; need ss; need curl; need date

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"

echo "== quick status =="
systemctl is-enabled "$SVC" >/dev/null 2>&1 && echo "[OK] enabled $SVC" || echo "[WARN] not enabled $SVC"
systemctl is-active  "$SVC" >/dev/null 2>&1 && echo "[OK] active  $SVC" || echo "[WARN] not active $SVC"

echo "== free port 8910 (kill stale listeners if any) =="
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[WARN] kill stale 8910 pids: $PIDS"
  kill -9 $PIDS 2>/dev/null || true
fi
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

echo "== compile check WSGI (current) =="
python3 - <<'PY'
import py_compile, sys
try:
  py_compile.compile("wsgi_vsp_ui_gateway.py", doraise=True)
  print("[OK] py_compile WSGI OK")
except Exception as e:
  print("[ERR] py_compile WSGI FAIL:", e)
  sys.exit(3)
PY

echo "== restart service =="
systemctl restart "$SVC" || true

echo "== probe /vsp5 =="
if curl -fsS "$BASE/vsp5" >/dev/null 2>&1; then
  echo "[OK] $BASE/vsp5 is reachable"
  ss -ltnp 2>/dev/null | awk '/:8910/ {print}' || true
  exit 0
fi

echo "[WARN] still not reachable -> dump status/logs"
systemctl status "$SVC" --no-pager -n 80 || true
journalctl -u "$SVC" --no-pager -n 200 || true

echo "== auto-restore latest compiling backup of WSGI then restart =="
python3 - <<'PY'
from pathlib import Path
import py_compile, sys

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

def ok(p: Path)->bool:
  try:
    py_compile.compile(str(p), doraise=True)
    return True
  except Exception:
    return False

good = None
for p in baks[:120]:
  if ok(p):
    good = p
    break

if not good:
  print("[ERR] no compiling backup found for WSGI")
  sys.exit(5)

cur = w.read_text(encoding="utf-8", errors="replace")
Path(str(w)+".bak_autorestore_failed_current").write_text(cur, encoding="utf-8")
w.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored WSGI from:", good.name)
PY

echo "== restart after restore =="
systemctl restart "$SVC" || true

echo "== probe again =="
if curl -fsS "$BASE/vsp5" >/dev/null 2>&1; then
  echo "[OK] revived: $BASE/vsp5 reachable"
  ss -ltnp 2>/dev/null | awk '/:8910/ {print}' || true
  exit 0
fi

echo "[ERR] still down. show final logs:"
systemctl status "$SVC" --no-pager -n 120 || true
journalctl -u "$SVC" --no-pager -n 260 || true
exit 9
