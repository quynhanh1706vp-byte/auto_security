#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_move_logs_varlog_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need sudo; need systemctl; need grep; need sed; need head; need tail; need curl; need cp; need mkdir; need chmod; need chown; need logrotate

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

UNIT="/etc/systemd/system/${SVC}"
[ -f "$UNIT" ] || fail "missing unit: $UNIT"

ok "== [P47.3] move logs to /var/log (POSIX perms) =="
ok "svc=$SVC base=$BASE"
ok "unit=$UNIT"

# 1) create varlog dir
VLOG="/var/log/vsp-ui-8910"
sudo mkdir -p "$VLOG"
sudo chown test:test "$VLOG"
sudo chmod 0750 "$VLOG"
ok "varlog ready: $VLOG (owner test:test mode 0750)"

# 2) backup unit
sudo cp -f "$UNIT" "${UNIT}.bak_varlog_${TS}"
ok "backup: ${UNIT}.bak_varlog_${TS}"

# 3) patch ExecStart log paths
# Replace --access-logfile and --error-logfile arguments
sudo sed -i \
  -e "s#--access-logfile [^ ]\\+#--access-logfile ${VLOG}/ui_8910.access.log#g" \
  -e "s#--error-logfile [^ ]\\+#--error-logfile ${VLOG}/ui_8910.error.log#g" \
  "$UNIT"

# sanity: show ExecStart line
ok "== ExecStart (patched) =="
sudo systemctl show "$SVC" -p FragmentPath --no-pager | tee -a "$LOG" >/dev/null || true
sudo grep -n "ExecStart" "$UNIT" | head -n 3 | tee -a "$LOG" >/dev/null || true

# 4) logrotate rule for varlog
RULE="/etc/logrotate.d/vsp-ui-8910"
if sudo test -f "$RULE"; then
  sudo cp -f "$RULE" "${RULE}.bak_varlog_${TS}"
  ok "backup rule: ${RULE}.bak_varlog_${TS}"
fi

sudo bash -lc "cat > '$RULE' <<'CONF'
/var/log/vsp-ui-8910/ui_8910.error.log
/var/log/vsp-ui-8910/ui_8910.access.log
{
  daily
  rotate 14
  size 20M
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
  dateext
  dateformat -%Y%m%d_%H%M%S
  maxage 30
  create 0640 test test
}
CONF"
sudo chmod 0644 "$RULE"
ok "wrote logrotate: $RULE"

# 5) reload + restart
ok "daemon-reload + restart"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

code="$(probe "$BASE/vsp5")"
ok "probe /vsp5=$code"
[ "$code" = "200" ] || {
  warn "status + journal tail"
  systemctl status "$SVC" --no-pager | tail -n 120 | tee -a "$LOG" >/dev/null || true
  sudo journalctl -u "$SVC" --no-pager -n 220 | tee -a "$LOG" >/dev/null || true
  fail "service not healthy after patch"
}

# 6) verify new logs exist + perms
ok "== varlog files =="
ls -lh "$VLOG" 2>/dev/null | tee -a "$LOG" >/dev/null || true
stat -c '%A %a %U:%G %n' "$VLOG"/ui_8910.*.log 2>/dev/null | tee -a "$LOG" >/dev/null || true

# 7) dry-run logrotate
ok "== logrotate dry-run (varlog) =="
sudo logrotate -d "$RULE" 2>&1 | tail -n 80 | tee -a "$LOG" >/dev/null || true

ok "DONE. log=$LOG"
