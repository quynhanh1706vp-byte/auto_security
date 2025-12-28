#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT=out_ci; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_varlog_dropin_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need sudo; need systemctl; need mkdir; need cp; need curl; need head; need tail; need grep; need sed; need ls; need stat; need cat

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }
probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

ok "== [P47.3b] varlog via systemd drop-in ExecStart override =="
ok "svc=$SVC base=$BASE"

ok "== unit paths =="
systemctl show "$SVC" -p FragmentPath -p DropInPaths --no-pager | tee -a "$LOG" >/dev/null || true
ok "== current ExecStart =="
systemctl show "$SVC" -p ExecStart --no-pager | tee -a "$LOG" >/dev/null || true

# Prepare /var/log dir
VLOG="/var/log/vsp-ui-8910"
sudo mkdir -p "$VLOG"
sudo chown test:test "$VLOG"
sudo chmod 0750 "$VLOG"
ok "varlog ready: $VLOG"

# Extract current ExecStart argv after 'argv[]='
cur=$(systemctl show "$SVC" -p ExecStart --no-pager | sed -n 's/^ExecStart=.*argv\[\]=//p' | head -n 1)
[ -n "$cur" ] || fail "cannot parse current ExecStart"

# Rewrite access/error logfile paths to /var/log
new=$(echo "$cur" | sed -E "s#--access-logfile [^ ]+#--access-logfile $VLOG/ui_8910.access.log#g; s#--error-logfile [^ ]+#--error-logfile $VLOG/ui_8910.error.log#g")

OVDIR="/etc/systemd/system/${SVC}.d"
OVCONF="$OVDIR/99-varlog.conf"
sudo mkdir -p "$OVDIR"
if sudo test -f "$OVCONF"; then sudo cp -f "$OVCONF" "${OVCONF}.bak_${TS}"; ok "backup: ${OVCONF}.bak_${TS}"; fi

sudo bash -lc "cat > '$OVCONF' <<CONF
[Service]
# Clear previous ExecStart then set new one
ExecStart=
ExecStart=$new
CONF"

ok "wrote drop-in: $OVCONF"
ok "== drop-in preview =="
sudo cat "$OVCONF" | tee -a "$LOG" >/dev/null || true

ok "daemon-reload + restart"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

# Wait for /vsp5
code=000
for i in $(seq 1 70); do
  code=$(probe "$BASE/vsp5")
  [ "$code" = "200" ] && break
  sleep 0.3
done
ok "probe /vsp5=$code"
[ "$code" = "200" ] || {
  warn "status + journal tail"
  systemctl status "$SVC" --no-pager | tail -n 120 | tee -a "$LOG" >/dev/null || true
  sudo journalctl -u "$SVC" --no-pager -n 220 | tee -a "$LOG" >/dev/null || true
  fail "service not healthy"
}

ok "== ExecStart after =="
systemctl show "$SVC" -p ExecStart --no-pager | tee -a "$LOG" >/dev/null || true

# Touch traffic to force log write
for i in 1 2 3; do curl -fsS "$BASE/vsp5" >/dev/null || true; done

ok "== varlog files =="
ls -lah "$VLOG" 2>&1 | tee -a "$LOG" >/dev/null || true
stat -c '%A %a %U:%G %n' "$VLOG"/ui_8910.*.log 2>/dev/null | tee -a "$LOG" >/dev/null || true

ok "DONE: $LOG"
