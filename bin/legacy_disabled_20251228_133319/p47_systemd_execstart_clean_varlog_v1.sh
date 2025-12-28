#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
VLOG="/var/log/vsp-ui-8910"
OUT=out_ci; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_clean_varlog_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need sudo; need systemctl; need grep; need sed; need head; need tail; need curl; need ls; need date; need cat

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }
probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

ok "== [P47.3d] systemd drop-in cleanup + clean varlog ExecStart =="
ok "svc=$SVC base=$BASE"

D="/etc/systemd/system/${SVC}.d"
sudo mkdir -p "$D"

# Ensure varlog dir exists with POSIX perms
sudo mkdir -p "$VLOG"
sudo chown test:test "$VLOG"
sudo chmod 0750 "$VLOG"
ok "varlog ready: $VLOG"

ok "== before: drop-ins + ExecStart =="
systemctl show "$SVC" -p DropInPaths -p ExecStart --no-pager | tee -a "$LOG" >/dev/null || true

# Disable known conflicting/bad drop-ins (keep 40-warm-cache.conf)
to_disable=(
  "$D/99-varlog.conf"
  "$D/zzzz-99999-varlog.conf"
  "$D/zzzz-9999-bindv4.conf"
)

for f in "${to_disable[@]}"; do
  if sudo test -f "$f"; then
    sudo cp -f "$f" "${f}.bak_${TS}"
    sudo mv -f "$f" "${f}.disabled_${TS}"
    ok "disabled: $f -> ${f}.disabled_${TS}"
  fi
done

# Create ONE final clean drop-in that wins last (but is VALID)
FINAL="$D/zzzz-99999-execstart-varlog.conf"
if sudo test -f "$FINAL"; then
  sudo cp -f "$FINAL" "${FINAL}.bak_${TS}"
  ok "backup: ${FINAL}.bak_${TS}"
fi

GUNICORN="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn"
APP="wsgi_vsp_ui_gateway:application"

# IMPORTANT: pure ExecStart line, no "ignore_errors/start_time/pid/status" garbage
sudo bash -lc "cat > '$FINAL' <<CONF
[Service]
UMask=027
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
Environment=VSP_UI_BASE=$BASE
ReadWritePaths=/home/test/Data/SECURITY_BUNDLE/ui/out_ci $VLOG

ExecStart=
ExecStart=$GUNICORN $APP --workers 2 --log-level info --worker-class gthread --threads 8 --timeout 120 --graceful-timeout 15 --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid --access-logfile $VLOG/ui_8910.access.log --error-logfile $VLOG/ui_8910.error.log --keep-alive 5
CONF"
ok "wrote FINAL drop-in: $FINAL"

ok "daemon-reload"
sudo systemctl daemon-reload

# Stop/start (avoid '200 giả' từ process cũ)
ok "stop service"
sudo systemctl stop "$SVC" || true
sleep 0.4
ok "start service"
sudo systemctl start "$SVC" || true

# Wait /vsp5
code="000"
for i in $(seq 1 80); do
  code="$(probe "$BASE/vsp5")"
  [ "$code" = "200" ] && break
  sleep 0.25
done
ok "probe /vsp5=$code"
[ "$code" = "200" ] || {
  warn "status + journal tail"
  systemctl status "$SVC" --no-pager | tail -n 160 | tee -a "$LOG" >/dev/null || true
  sudo journalctl -u "$SVC" --no-pager -n 220 | tee -a "$LOG" >/dev/null || true
  fail "service not healthy"
}

ok "== after: ExecStart =="
systemctl show "$SVC" -p ExecStart -p DropInPaths --no-pager | tee -a "$LOG" >/dev/null || true

# Force some requests to write logs
for i in 1 2 3; do curl -fsS "$BASE/vsp5" >/dev/null || true; done

ok "== varlog listing =="
ls -lah "$VLOG" 2>&1 | tee -a "$LOG" >/dev/null || true

# Assertion
if systemctl show "$SVC" -p ExecStart --no-pager | grep -q "$VLOG/ui_8910.error.log"; then
  ok "SUCCESS: ExecStart now points to /var/log"
else
  fail "ExecStart still not pointing to /var/log (check later drop-ins)"
fi

ok "DONE: $LOG"
