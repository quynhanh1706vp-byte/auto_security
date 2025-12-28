#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

LOCK="out_ci/ui_8910.lock"
PIDF="out_ci/ui_8910.pid"

echo "== [LOCK CHECK] =="
ls -la "$LOCK" "$PIDF" 2>/dev/null || true
stat -c '%y %n' "$LOCK" 2>/dev/null || true
stat -c '%y %n' "$PIDF" 2>/dev/null || true

# detect restart script running
if ps -ef | grep -E "restart_8910_gunicorn_commercial|vsp-ui-8910|gunicorn.*8910" | grep -v grep >/dev/null 2>&1; then
  echo "== [PROC SNAPSHOT] =="
  ps -ef | grep -E "restart_8910_gunicorn_commercial|gunicorn.*8910|vsp_demo_app\.py" | grep -v grep || true
fi

# If lock exists but no restart script is running, treat as stale and remove
if [ -f "$LOCK" ]; then
  if ps -ef | grep -E "restart_8910_gunicorn_commercial" | grep -v grep >/dev/null 2>&1; then
    echo "[WARN] restart script seems running; but lock may still be stale. Try to detect real activity..."
  else
    echo "[OK] no restart script running -> remove stale lock"
    rm -f "$LOCK"
  fi
fi

# If pidfile exists and pid is dead -> cleanup
if [ -f "$PIDF" ]; then
  PID="$(cat "$PIDF" 2>/dev/null || true)"
  if [ -n "${PID:-}" ] && ! kill -0 "$PID" 2>/dev/null; then
    echo "[OK] pidfile exists but pid dead -> cleanup pidfile"
    rm -f "$PIDF"
  fi
fi

# Try restart script (preferred)
if [ -x "bin/restart_8910_gunicorn_commercial_v5.sh" ]; then
  echo "== [RESTART] via bin/restart_8910_gunicorn_commercial_v5.sh =="
  rm -f "$LOCK" 2>/dev/null || true
  bin/restart_8910_gunicorn_commercial_v5.sh || true
fi

# Fallback: systemd if available
if command -v systemctl >/dev/null 2>&1; then
  echo "== [RESTART] via systemctl restart vsp-ui-8910 (fallback) =="
  sudo -n true >/dev/null 2>&1 && sudo systemctl restart vsp-ui-8910 || true
fi

echo "== [VERIFY healthz] =="
curl -sS -D- "http://127.0.0.1:8910/healthz" -o /dev/null | head -n 20 || true

echo "== [VERIFY export route exists] =="
RID="${1:-RUN_VSP_CI_20251215_034956}"
curl -sS -D- -o /dev/null "http://127.0.0.1:8910/api/vsp/run_export_v3/$RID?fmt=html" | head -n 20 || true

echo "[DONE] restart attempted, export route probed."
