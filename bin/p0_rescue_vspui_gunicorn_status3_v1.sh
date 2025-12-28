#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
WSGI="wsgi_vsp_ui_gateway.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need tail; need sed; need grep; need ls; need head
[ -x "$PY" ] || PY="$(command -v python3)"

echo "== [0] Stop & reset-failed (avoid restart loop) =="
sudo systemctl stop "$SVC" 2>/dev/null || true
sudo systemctl reset-failed "$SVC" 2>/dev/null || true

echo "== [1] Show gunicorn error log tail (REAL traceback) =="
if [ -f "$ERRLOG" ]; then
  echo "--- tail $ERRLOG ---"
  tail -n 200 "$ERRLOG" || true
else
  echo "[WARN] missing $ERRLOG"
fi
echo

echo "== [2] py_compile WSGI =="
if [ -f "$WSGI" ]; then
  "$PY" -m py_compile "$WSGI" && echo "[OK] py_compile OK" || echo "[ERR] py_compile FAILED"
else
  echo "[ERR] missing $WSGI"
  exit 2
fi
echo

echo "== [3] Import module + check 'application' symbol =="
set +e
"$PY" - <<'PY'
import importlib, traceback
try:
    m = importlib.import_module("wsgi_vsp_ui_gateway")
    print("[OK] import wsgi_vsp_ui_gateway")
    print("has application =", hasattr(m, "application"))
    if hasattr(m, "application"):
        a = getattr(m, "application")
        print("application type =", type(a))
except Exception:
    print("[ERR] import failed:")
    traceback.print_exc()
PY
rc=$?
set -e
echo

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_rescue_status3_${TS}"
echo "[BACKUP] ${WSGI}.bak_rescue_status3_${TS}"

echo "== [4] If missing 'application' but has 'app', auto-append application=app =="
"$PY" - <<'PY'
from pathlib import Path
import re, py_compile, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

has_application = re.search(r'(?m)^\s*application\s*=', s) is not None
has_app = re.search(r'(?m)^\s*app\s*=', s) is not None

changed=False
if (not has_application) and has_app:
    s = s.rstrip() + "\n\n# [AUTO-RESCUE] gunicorn entry expects 'application'\napplication = app\n"
    changed=True

if changed:
    p.write_text(s, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("[OK] patched application=app and py_compile ok")
else:
    print("[OK] no patch needed (application exists or app missing)")
PY
echo

echo "== [5] If still failing, auto-restore latest backup and retry compile =="
set +e
"$PY" -m py_compile "$WSGI" >/dev/null 2>&1
pc=$?
set -e
if [ "$pc" -ne 0 ]; then
  echo "[WARN] current WSGI still not compilable; trying auto-restore latest backup..."
  latest="$(ls -1t ${WSGI}.bak_* 2>/dev/null | head -n 1 || true)"
  if [ -n "$latest" ]; then
    cp -f "$latest" "$WSGI"
    echo "[RESTORE] $latest -> $WSGI"
    "$PY" -m py_compile "$WSGI" && echo "[OK] restore compile OK" || { echo "[ERR] restore still fails"; exit 3; }
  else
    echo "[ERR] no backup files found to restore"
    exit 3
  fi
fi
echo

echo "== [6] Start service and show status =="
sudo systemctl start "$SVC" || true
sleep 0.5
systemctl status "$SVC" --no-pager -l | tail -n 120 || true

echo
echo "== [7] Tail error log after start =="
if [ -f "$ERRLOG" ]; then tail -n 120 "$ERRLOG" || true; fi

echo
echo "[DONE] If still down: paste the last 120 lines of $ERRLOG."
