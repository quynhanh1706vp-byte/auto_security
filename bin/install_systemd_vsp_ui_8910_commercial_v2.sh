#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
VENV="$ROOT/.venv"
SERVICE="vsp-ui-8910"
USER_NAME="$(id -un)"
GROUP_NAME="$(id -gn)"

cd "$UI"

# 0) Ensure venv + gunicorn
if [ ! -x "$VENV/bin/python3" ]; then
  echo "[ERR] missing venv python at $VENV/bin/python3"
  echo "      (expected .venv at /home/test/Data/SECURITY_BUNDLE/.venv)"
  exit 1
fi

if ! "$VENV/bin/python3" -c "import gunicorn" >/dev/null 2>&1; then
  echo "[INFO] gunicorn not found -> installing..."
  "$VENV/bin/pip" install -U gunicorn >/dev/null
fi

# 1) Add healthz endpoint (patch vsp_demo_app.py)
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $UI/$APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_healthz_${TS}"
echo "[BACKUP] $APP.bak_healthz_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Try detect Flask app object name: commonly "app"
# We'll inject route after app creation or near end, guarded by marker.
MARK_BEG = "# === VSP COMMERCIAL HEALTHZ V1 ==="
MARK_END = "# === END VSP COMMERCIAL HEALTHZ V1 ==="

if MARK_BEG in txt:
    print("[OK] healthz block already present")
    sys.exit(0)

block = f"""
{MARK_BEG}
try:
    from flask import jsonify
    @app.get("/healthz")
    def vsp_healthz_v1():
        return jsonify({{"ok": True, "service": "vsp-ui-8910"}}), 200
except Exception:
    pass
{MARK_END}
"""

# place near bottom (after app defined)
txt2 = txt.rstrip() + "\n" + block + "\n"
p.write_text(txt2, encoding="utf-8")
print("[OK] injected /healthz")
PY

# 2) Create WSGI entrypoint
WSGI="wsgi_8910.py"
cat > "$WSGI" <<'PY'
"""
WSGI entrypoint for gunicorn.
We keep it robust: try import `app` from vsp_demo_app.py.
"""
import os
os.environ.setdefault("VSP_UI_MODE", "PROD")

try:
    from vsp_demo_app import app  # type: ignore
except Exception as e:
    raise RuntimeError("Cannot import Flask app from vsp_demo_app.py") from e

application = app
PY
echo "[OK] wrote $UI/$WSGI"

# 3) systemd unit
UNIT="/etc/systemd/system/${SERVICE}.service"
sudo bash -c "cat > '$UNIT' <<'UNIT'
[Unit]
Description=VSP UI Gateway (Gunicorn) on :8910
After=network.target

[Service]
Type=simple
User=${USER_NAME}
Group=${GROUP_NAME}
WorkingDirectory=${UI}
Environment=PYTHONUNBUFFERED=1
Environment=VSP_UI_PORT=8910
Environment=VSP_UI_BIND=127.0.0.1
ExecStart=${VENV}/bin/gunicorn -w 2 -k gthread --threads 8 --timeout 60 --graceful-timeout 15 \\
  --bind 127.0.0.1:8910 \\
  --access-logfile ${UI}/out_ci/ui_8910_access.log \\
  --error-logfile  ${UI}/out_ci/ui_8910_error.log \\
  wsgi_8910:application
Restart=always
RestartSec=2
KillSignal=SIGTERM
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
UNIT"
echo "[OK] wrote $UNIT"

# 4) logrotate
sudo bash -c "cat > /etc/logrotate.d/${SERVICE} <<'LR'
/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910_*.log /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910*log {
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}
LR"
echo "[OK] wrote /etc/logrotate.d/${SERVICE}"

# 5) enable & start
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE}.service"
sudo systemctl restart "${SERVICE}.service"

echo "[OK] systemd started: ${SERVICE}"
echo "== quick check =="
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1:8910/healthz || true
echo "== logs =="
echo "  journalctl -u ${SERVICE} -n 80 --no-pager"
