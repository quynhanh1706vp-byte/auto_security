#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT="${VSP_UI_PORT:-8910}"
HOST="${VSP_UI_HOST:-0.0.0.0}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:${PORT}}"
UNIT_PATH="/etc/systemd/system/${SVC}"
LOG_DIR="/var/log/vsp-ui"
ROT_PATH="/etc/logrotate.d/vsp-ui"
ENV_DIR="/home/test/Data/SECURITY_BUNDLE/ui/config"
ENV_FILE="${ENV_DIR}/production.env"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need awk; need sed; need grep
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo"; exit 2; }

echo "[P522] svc=$SVC base=$BASE port=$PORT"

mkdir -p "$ENV_DIR"

# 1) Patch health endpoints into vsp_demo_app.py (idempotent)
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p522_${TS}"
echo "[OK] backup: ${APP}.bak_p522_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "/api/healthz" in s and "/api/readyz" in s:
    print("[OK] healthz/readyz already present")
    raise SystemExit(0)

snippet = r'''

# === VSP P522 health endpoints (commercial) ===
@app.route("/api/healthz", methods=["GET"])
def api_healthz_v1():
    # Liveness: process up
    try:
        return jsonify({"ok": True, "service": "vsp-ui", "liveness": True, "ver": "p522"}), 200
    except Exception as e:
        return jsonify({"ok": False, "service": "vsp-ui", "err": str(e)}), 500

@app.route("/api/readyz", methods=["GET"])
def api_readyz_v1():
    # Readiness: filesystem + permissions + basic runtime deps
    from pathlib import Path
    import os, time

    root = Path(__file__).resolve().parent
    out_ci = root / "out_ci"
    checks = {}
    ok = True

    try:
        out_ci.mkdir(parents=True, exist_ok=True)
        t = out_ci / f".readyz_touch_{int(time.time())}"
        t.write_text("ok", encoding="utf-8")
        t.unlink(missing_ok=True)
        checks["out_ci_writable"] = True
    except Exception as e:
        ok = False
        checks["out_ci_writable"] = False
        checks["out_ci_err"] = str(e)

    # cache dir (P504)
    try:
        cdir = out_ci / "p504_fcache"
        cdir.mkdir(parents=True, exist_ok=True)
        checks["p504_cache_dir_ok"] = True
    except Exception as e:
        ok = False
        checks["p504_cache_dir_ok"] = False
        checks["p504_cache_err"] = str(e)

    # CSP report persist file
    try:
        csp = out_ci / "csp_reports.log"
        with csp.open("a", encoding="utf-8") as f:
            f.write("")
        checks["csp_reports_append_ok"] = True
    except Exception as e:
        ok = False
        checks["csp_reports_append_ok"] = False
        checks["csp_reports_err"] = str(e)

    # basic binaries presence (soft signals)
    checks["python3_ok"] = True
    checks["gunicorn_path"] = os.environ.get("VSP_GUNICORN", "")

    return jsonify({"ok": ok, "service": "vsp-ui", "readiness": ok, "checks": checks, "ver": "p522"}), (200 if ok else 503)

# === end P522 health ===
'''

# Insert before __main__ block if exists, else append
m = re.search(r'\nif\s+__name__\s*==\s*["\']__main__["\']\s*:', s)
if m:
    s2 = s[:m.start()] + snippet + "\n" + s[m.start():]
else:
    s2 = s + "\n" + snippet + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched healthz/readyz into vsp_demo_app.py")
PY

# 2) Create default production.env if missing (user edits only this)
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<EOF
# VSP UI Production Env (edit this file only)
VSP_UI_BASE=${BASE}
VSP_UI_PORT=${PORT}
VSP_UI_HOST=${HOST}

# Optional: point UI to your scan/out root
# VSP_DATA_ROOT=/home/test/Data/SECURITY_BUNDLE/out

# Cache knobs (P504)
VSP_P504_TTL_SEC=30
VSP_P504_MAX_MB=256

# CSP knobs
VSP_CSP_ENFORCE=1
VSP_CSP_REPORT=1

# Optional: override gunicorn path
# VSP_GUNICORN=/home/test/Data/SECURITY_BUNDLE/.venv/bin/gunicorn
EOF
  echo "[OK] wrote $ENV_FILE"
else
  echo "[OK] exists $ENV_FILE"
fi

# 3) Determine app module for gunicorn
APP_MODULE="vsp_demo_app:app"
if [ -f "wsgi_vsp_ui_gateway.py" ]; then
  APP_MODULE="wsgi_vsp_ui_gateway:app"
fi

# 4) Create log dir
sudo mkdir -p "$LOG_DIR"
sudo chown root:root "$LOG_DIR"
sudo chmod 0755 "$LOG_DIR"

# 5) Create systemd unit (commercial)
VENV="/home/test/Data/SECURITY_BUNDLE/.venv"
GUNICORN_BIN="${VENV}/bin/gunicorn"
if [ -n "${VSP_GUNICORN:-}" ]; then GUNICORN_BIN="$VSP_GUNICORN"; fi
if [ ! -x "$GUNICORN_BIN" ]; then
  if command -v gunicorn >/dev/null 2>&1; then
    GUNICORN_BIN="$(command -v gunicorn)"
  else
    echo "[ERR] gunicorn not found (install in venv or PATH)"; exit 2
  fi
fi

TMP_UNIT="/tmp/${SVC}.p522.unit"
cat > "$TMP_UNIT" <<EOF
[Unit]
Description=VSP UI Gateway (commercial)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
EnvironmentFile=${ENV_FILE}

# Hardening
UMask=0027
Restart=always
RestartSec=2
TimeoutStartSec=25
TimeoutStopSec=15
LimitNOFILE=65535

# Optional resource limits (safe defaults - can edit later)
# MemoryMax=1024M
# CPUQuota=200%

# Logs
StandardOutput=append:${LOG_DIR}/vsp-ui.out.log
StandardError=append:${LOG_DIR}/vsp-ui.err.log

ExecStart=${GUNICORN_BIN} -w 2 -b ${HOST}:${PORT} --access-logfile ${LOG_DIR}/access.log --error-logfile ${LOG_DIR}/gunicorn.log ${APP_MODULE}

[Install]
WantedBy=multi-user.target
EOF

echo "[INFO] installing unit => $UNIT_PATH"
sudo cp -f "$TMP_UNIT" "$UNIT_PATH"
sudo chmod 0644 "$UNIT_PATH"

# 6) Logrotate
TMP_ROT="/tmp/vsp-ui.p522.logrotate"
cat > "$TMP_ROT" <<EOF
/var/log/vsp-ui/*.log /var/log/vsp-ui/access.log /var/log/vsp-ui/gunicorn.log {
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}
EOF
sudo cp -f "$TMP_ROT" "$ROT_PATH"
sudo chmod 0644 "$ROT_PATH"
echo "[OK] logrotate => $ROT_PATH"

# 7) Reload + enable + restart
sudo systemctl daemon-reload
sudo systemctl enable "$SVC" >/dev/null 2>&1 || true
sudo systemctl restart "$SVC"

echo "[OK] systemd status:"
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,18p'

# 8) Quick health check
echo "== health checks =="
curl -fsS "$BASE/api/healthz" | python3 -c 'import sys,json; print(json.load(sys.stdin))'
curl -fsS "$BASE/api/readyz"  | python3 -c 'import sys,json; print(json.load(sys.stdin))'

echo "[DONE] P522 applied. Edit $ENV_FILE then restart: sudo systemctl restart $SVC"
