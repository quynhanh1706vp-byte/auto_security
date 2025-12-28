#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
UNIT="$HOME/.config/systemd/user/vsp-ui-8910.service"
PORT="8910"

cd "$ROOT"

echo "== [1] current port owner =="
ss -ltnp | grep ":$PORT" || echo "[OK] port $PORT is free"

echo "== [2] stop systemd unit (prevent flapping) =="
systemctl --user stop vsp-ui-8910.service 2>/dev/null || true
sleep 1

echo "== [3] kill anything holding :$PORT =="
PIDS="$(ss -ltnp | awk -v p=":$PORT" '$4 ~ p {print $0}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u)"
if [ -n "${PIDS:-}" ]; then
  for pid in $PIDS; do
    echo "[KILL] pid=$pid"
    kill -9 "$pid" 2>/dev/null || true
  done
fi
# best-effort extra cleanup
pkill -9 -f "gunicorn.*:$PORT" 2>/dev/null || true
pkill -9 -f "vsp_demo_app\.py" 2>/dev/null || true
sleep 1

echo "== [4] verify port free =="
ss -ltnp | grep ":$PORT" && { echo "[ERR] port still busy"; exit 1; } || echo "[OK] port free"

echo "== [5] rewrite systemd --user unit to canonical gunicorn =="
mkdir -p "$(dirname "$UNIT")"

GUNICORN_BIN="$(command -v gunicorn || true)"
if [ -z "$GUNICORN_BIN" ]; then
  echo "[ERR] gunicorn not found in PATH (but ss showed gunicorn earlier)."
  echo "      Try: source ../.venv/bin/activate && pip install gunicorn"
  exit 1
fi

cat > "$UNIT" <<EOF
[Unit]
Description=VSP UI Gateway (8910) - canonical gunicorn
After=network.target

[Service]
Type=simple
WorkingDirectory=$ROOT
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONPATH=$ROOT
Environment=VSP_GIT_HASH=unknown
Environment=VSP_BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# 1 worker trước cho ổn định + tránh duplicate initAll storm
ExecStart=/usr/bin/env bash -lc 'cd $ROOT && source ../.venv/bin/activate 2>/dev/null || true; exec $GUNICORN_BIN -w 1 -b 127.0.0.1:$PORT --log-level info --access-logfile - --error-logfile - "vsp_demo_app:app"'
Restart=always
RestartSec=2

# log cố định
StandardOutput=append:$ROOT/out_ci/ui_8910.log
StandardError=append:$ROOT/out_ci/ui_8910.log

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable vsp-ui-8910.service >/dev/null 2>&1 || true
systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== [6] status + port owner =="
systemctl --user status vsp-ui-8910.service --no-pager -n 20 || true
ss -ltnp | grep ":$PORT" || { echo "[ERR] nothing listening on $PORT"; exit 1; }

echo "== [7] verify contract endpoints return JSON =="
echo "--- healthz ---"
curl -sS -i http://127.0.0.1:$PORT/healthz | sed -n '1,12p'; echo

echo "--- version ---"
curl -sS -i http://127.0.0.1:$PORT/api/vsp/version | sed -n '1,12p'; echo

echo "--- settings_v1 (must be application/json) ---"
curl -sS -i http://127.0.0.1:$PORT/api/vsp/settings_v1 | sed -n '1,18p'; echo

echo "--- rule_overrides_v1 (must be application/json) ---"
curl -sS -i http://127.0.0.1:$PORT/api/vsp/rule_overrides_v1 | sed -n '1,18p'; echo
