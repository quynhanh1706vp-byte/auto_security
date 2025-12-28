#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
UNIT="$HOME/.config/systemd/user/vsp-ui-8910.service"

echo "== [A] verify patch exists in file =="
grep -n "VSP_OPS_ROUTES_V3" "$ROOT/vsp_demo_app.py" || { echo "[ERR] V3 tag not found in vsp_demo_app.py"; exit 1; }

echo "== [B] who is listening on :8910 =="
ss -ltnp | grep ':8910' || echo "[WARN] nothing listening on 8910 (yet)"

echo "== [C] systemd unit (if exists) =="
if [ -f "$UNIT" ]; then
  echo "[UNIT] $UNIT"
  sed -n '1,200p' "$UNIT"
else
  echo "[WARN] no systemd user unit at $UNIT"
fi

echo "== [D] stop systemd service (ignore errors) =="
systemctl --user stop vsp-ui-8910.service >/dev/null 2>&1 || true
sleep 0.5

echo "== [E] kill anything holding 8910 (best effort) =="
# kill by socket owner
PID="$(ss -ltnp 2>/dev/null | awk '/:8910/{print $NF}' | sed -E 's/.*pid=([0-9]+).*/\1/' | head -n1 || true)"
if [ -n "${PID:-}" ]; then
  echo "[KILL] pid=$PID"
  kill -9 "$PID" || true
fi
# kill common patterns
pkill -9 -f "vsp_demo_app.py" || true
sleep 0.5

echo "== [F] rewrite unit ExecStart to absolute path (to avoid running another file) =="
mkdir -p "$(dirname "$UNIT")"
if [ ! -f "$UNIT" ]; then
  cat > "$UNIT" <<EOF
[Unit]
Description=VSP UI Gateway (8910)
After=network.target

[Service]
Type=simple
WorkingDirectory=$ROOT
ExecStart=/usr/bin/env bash -lc 'cd $ROOT && source ../.venv/bin/activate 2>/dev/null || true; exec python3 -u $ROOT/vsp_demo_app.py'
Restart=always
RestartSec=2
StandardOutput=append:$ROOT/out_ci/ui_8910.log
StandardError=append:$ROOT/out_ci/ui_8910.log

[Install]
WantedBy=default.target
EOF
else
  # patch existing ExecStart + WorkingDirectory safely
  tmp="$(mktemp)"
  awk -v root="$ROOT" '
    BEGIN{wd=0; es=0}
    /^\[Service\]/{print; next}
    /^WorkingDirectory=/{print "WorkingDirectory="root; wd=1; next}
    /^ExecStart=/{print "ExecStart=/usr/bin/env bash -lc \x27cd "root" && source ../.venv/bin/activate 2>/dev/null || true; exec python3 -u "root"/vsp_demo_app.py\x27"; es=1; next}
    {print}
    END{
      if(!wd) print "WorkingDirectory="root
      if(!es) print "ExecStart=/usr/bin/env bash -lc \x27cd "root" && source ../.venv/bin/activate 2>/dev/null || true; exec python3 -u "root"/vsp_demo_app.py\x27"
    }
  ' "$UNIT" > "$tmp"
  mv "$tmp" "$UNIT"
fi

systemctl --user daemon-reload
systemctl --user enable --now vsp-ui-8910.service
sleep 1

echo "== [G] status + port owner =="
systemctl --user status vsp-ui-8910.service --no-pager -n 25 || true
ss -ltnp | grep ':8910' || true

echo "== [H] curl verify (show HTTP status) =="
echo "-- healthz --"
curl -sS -i http://127.0.0.1:8910/healthz | sed -n '1,12p'
echo
echo "-- version --"
curl -sS -i http://127.0.0.1:8910/api/vsp/version | sed -n '1,20p'
echo
