#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="./.venv/bin/python"
CURL="curl"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need "$CURL"; need ss
[ -x "$PY" ] || PY="python3"

APP="vsp_demo_app.py"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
SNAP="${APP}.bak_autorescue_snapshot_${TS}"
cp -f "$APP" "$SNAP"
echo "[SNAPSHOT] $SNAP"

TMP="/tmp/vsp_autorescue_${TS}"
mkdir -p "$TMP"

echo "== [0] quick import check CURRENT (to capture real exception) =="
set +e
"$PY" - <<'PY' 2>"$TMP/import_current.err"
import wsgi_vsp_ui_gateway as w
print("OK current wsgi loaded", bool(getattr(w, "application", None)))
PY
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "[ERR] current import fails (this is why gunicorn exits). Top lines:"
  sed -n '1,80p' "$TMP/import_current.err" || true
fi

echo "== [1] stop service hard =="
systemctl stop "$SVC" 2>/dev/null || true
sleep 0.2

echo "== [2] kill listeners on :8910 just in case =="
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910 .*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS 2>/dev/null || true

echo "== [3] iterate backups newest->oldest until import OK + healthz OK =="
BKS=( $(ls -1t vsp_demo_app.py.bak_* 2>/dev/null | head -n 80 || true) )
[ "${#BKS[@]}" -gt 0 ] || { echo "[ERR] no backups found vsp_demo_app.py.bak_*"; exit 2; }

for b in "${BKS[@]}"; do
  echo "--- try $b ---"
  cp -f "$b" "$APP"

  # must compile + import wsgi
  if ! "$PY" -m py_compile "$APP" "$WSGI" 2>"$TMP/pyc.err"; then
    echo "[SKIP] py_compile failed for $b"
    continue
  fi
  if ! "$PY" - <<'PY' 2>"$TMP/import_try.err"
import wsgi_vsp_ui_gateway as w
assert getattr(w, "application", None) is not None
print("OK wsgi import")
PY
  then
    echo "[SKIP] wsgi import failed for $b"
    sed -n '1,40p' "$TMP/import_try.err" || true
    continue
  fi

  # restart and probe
  systemctl start "$SVC" 2>/dev/null || true
  sleep 0.4
  if "$CURL" -fsS "$BASE/api/vsp/healthz" -o "$TMP/healthz.json" 2>/dev/null; then
    echo "[OK] rescued with $b"
    "$PY" - <<'PY' "$TMP/healthz.json"
import json,sys
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
print("HEALTHZ:", "release_status=", j.get("release_status"), "rid_latest=", j.get("rid_latest_gate_root"))
PY
    echo "[DONE] service is up"
    exit 0
  fi

  echo "[WARN] service still not up with $b (continue)"
  systemctl stop "$SVC" 2>/dev/null || true
  sleep 0.2
done

echo "[FAIL] no backup could restore service. Restoring snapshot..."
cp -f "$SNAP" "$APP"
systemctl start "$SVC" 2>/dev/null || true

echo "[ARTIFACTS] $TMP"
echo "[NEXT] paste $TMP/import_current.err (first 80 lines) here."
exit 2
