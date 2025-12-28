#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
UNIT="$HOME/.config/systemd/user/vsp-ui-8910.service"
PORT=8910

cd "$ROOT"

echo "== [A] ensure gunicorn in venv =="
if [ -f "../.venv/bin/activate" ]; then
  source ../.venv/bin/activate
fi
python3 -c "import gunicorn" >/dev/null 2>&1 || {
  echo "[INSTALL] gunicorn -> ../.venv"
  pip -q install gunicorn
}
python3 -c "import gunicorn; print('[OK] gunicorn version', getattr(gunicorn,'__version__','?'))"

echo "== [B] rewrite unit to python -m gunicorn =="
mkdir -p "$(dirname "$UNIT")"
cat > "$UNIT" <<EOF
[Unit]
Description=VSP UI Gateway (8910) - python -m gunicorn
After=network.target

[Service]
Type=simple
WorkingDirectory=$ROOT
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONPATH=$ROOT
Environment=VSP_GIT_HASH=unknown
Environment=VSP_BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

ExecStart=/usr/bin/env bash -lc 'cd $ROOT && source ../.venv/bin/activate 2>/dev/null || true; exec python3 -m gunicorn -w 1 -b 127.0.0.1:$PORT --log-level info --access-logfile - --error-logfile - "vsp_demo_app:app"'
Restart=always
RestartSec=2
StandardOutput=append:$ROOT/out_ci/ui_8910.log
StandardError=append:$ROOT/out_ci/ui_8910.log

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable vsp-ui-8910.service >/dev/null 2>&1 || true
systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== [C] status + port owner =="
systemctl --user status vsp-ui-8910.service --no-pager -n 20 || true
ss -ltnp | grep ":$PORT" || { echo "[ERR] nothing listening on :$PORT"; exit 1; }

echo "== [D] quick health/version =="
curl -sS http://127.0.0.1:$PORT/healthz; echo
curl -sS http://127.0.0.1:$PORT/api/vsp/version; echo
