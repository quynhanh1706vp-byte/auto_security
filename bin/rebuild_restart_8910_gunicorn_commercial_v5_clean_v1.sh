#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

S="bin/restart_8910_gunicorn_commercial_v5.sh"
TS="$(date +%Y%m%d_%H%M%S)"
if [ -f "$S" ]; then
  cp -f "$S" "$S.bak_rebuild_${TS}"
  echo "[BACKUP] $S.bak_rebuild_${TS}"
fi

cat > "$S" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

LOCK="out_ci/ui_8910.lock"
PIDFILE="out_ci/ui_8910.pid"
NOHUP="out_ci/ui_8910.nohup.log"
ACCESS="out_ci/ui_8910.access.log"
ERROR="out_ci/ui_8910.error.log"

HOST="127.0.0.1"
PORT="8910"

APP_MODULE="wsgi_vsp_ui_gateway_exportpdf_only:application"

# lock (simple)
if [ -f "$LOCK" ]; then
  echo "[WARN] lock exists: $LOCK (removing stale)"
  rm -f "$LOCK" || true
fi
: > "$LOCK"

mkdir -p out_ci

# stop old
if [ -f "$PIDFILE" ]; then
  OLD_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "${OLD_PID:-}" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[STOP] pid=$OLD_PID"
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$PIDFILE" || true
fi

# free port (best-effort)
if command -v lsof >/dev/null 2>&1; then
  P="$(lsof -ti tcp:${PORT} 2>/dev/null || true)"
  if [ -n "${P:-}" ]; then
    echo "[KILL] port ${PORT} pid=$P"
    kill -9 $P 2>/dev/null || true
  fi
fi

# clean pycache so new module is imported
rm -rf __pycache__ 2>/dev/null || true
rm -rf "$ROOT"/__pycache__ 2>/dev/null || true

echo "== start gunicorn ${APP_MODULE} ${PORT} =="

# NOTE: only ONE app module allowed
nohup gunicorn "${APP_MODULE}" \
  --workers 2 \
  --worker-class gthread \
  --threads 4 \
  --timeout 60 \
  --graceful-timeout 15 \
  --chdir "$ROOT" \
  --pythonpath "$ROOT" \
  --bind "${HOST}:${PORT}" \
  --pid "$PIDFILE" \
  --access-logfile "$ROOT/$ACCESS" \
  --error-logfile "$ROOT/$ERROR" \
  >> "$ROOT/$NOHUP" 2>&1 &

sleep 1

# verify listening
if command -v ss >/dev/null 2>&1; then
  ss -lntp | grep -q ":${PORT}" && echo "[OK] ${PORT} listening" || {
    echo "[ERR] ${PORT} not listening"
    echo "== last nohup =="; tail -n 80 "$ROOT/$NOHUP" || true
    echo "== last error =="; tail -n 80 "$ROOT/$ERROR" || true
    rm -f "$LOCK" || true
    exit 1
  }
fi

# quick health probe (non-fatal)
curl -sS "http://${HOST}:${PORT}/healthz" >/dev/null 2>&1 && echo "[OK] healthz reachable" || echo "[WARN] healthz not reachable yet"

rm -f "$LOCK" || true
BASH

chmod +x "$S"
echo "[OK] rebuilt $S"

# run it
rm -f out_ci/ui_8910.lock
"$S"
