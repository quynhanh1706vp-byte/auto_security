#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY=".venv/bin/python"
WSGI="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need date; need sed; need tail; need curl
[ -x "$PY" ] || { echo "[ERR] missing venv python: $PY"; exit 2; }
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

echo "== [0] stop service =="
systemctl stop "$SVC" 2>/dev/null || true

echo "== [1] import diag (runtime) =="
set +e
"$PY" - <<'PY'
import traceback, sys
try:
    import wsgi_vsp_ui_gateway as m
    keys = [k for k in ("application","app") if hasattr(m,k)]
    print("[OK] imported module; has:", keys)
    for k in keys:
        obj = getattr(m,k)
        print(f"  - {k}: type={type(obj)} callable={callable(obj)} repr={repr(obj)[:120]}")
    if not hasattr(m,"application") and hasattr(m,"app"):
        print("[WARN] missing 'application' but has 'app' (gunicorn expects :application)")
    if hasattr(m,"application") and not callable(getattr(m,"application")):
        print("[WARN] 'application' exists but not callable")
except Exception as e:
    print("[ERR] import failed:", repr(e))
    traceback.print_exc()
    sys.exit(7)
PY
RC=$?
set -e

echo "== [2] show error log tail if exists =="
tail -n 120 out_ci/ui_8910.error.log 2>/dev/null || true

MARK="VSP_P0_WSGI_ENTRYPOINT_FIX_V1"
if [ "$RC" -ne 0 ]; then
  echo "[WARN] import failed -> apply safe entrypoint fix block (idempotent)"
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
  echo "[BACKUP] ${WSGI}.bak_${MARK}_${TS}"

  "$PY" - <<PY
from pathlib import Path
import re, textwrap, py_compile
p = Path("$WSGI")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "$MARK"
if mark in s:
    print("[OK] marker exists, skip patch")
else:
    block = textwrap.dedent(f"""
    # ===================== {mark} =====================
    # Ensure Gunicorn entrypoint symbol exists and is stable.
    try:
        application  # noqa: F821
    except Exception:
        try:
            application = app  # type: ignore[name-defined]
        except Exception:
            pass
    try:
        app  # noqa: F821
    except Exception:
        try:
            app = application  # type: ignore[name-defined]
        except Exception:
            pass
    # ===================== /{mark} =====================
    """).strip() + "\\n"
    s = s.rstrip() + "\\n\\n" + block
    p.write_text(s, encoding="utf-8")
    print("[OK] appended", mark)
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile after patch")
PY
fi

echo "== [3] restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [4] wait readiness (max 25s) =="
UP=0
for i in $(seq 1 25); do
  if curl -fsS -o /dev/null --connect-timeout 2 "$BASE/runs"; then UP=1; break; fi
  sleep 1
done

echo "== [5] status + tail error log =="
systemctl status "$SVC" --no-pager -l || true
tail -n 120 out_ci/ui_8910.error.log 2>/dev/null || true

if [ "$UP" -eq 1 ]; then
  echo "[OK] UP: $BASE/runs reachable"
  exit 0
fi

echo "[FAIL] still down: $BASE/runs"
exit 1
