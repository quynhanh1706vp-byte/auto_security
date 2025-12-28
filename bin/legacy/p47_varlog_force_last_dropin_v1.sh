#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT=out_ci; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_varlog_force_last_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need sudo; need systemctl; need sed; need head; need curl; need ls; need stat; need date

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }
probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

ok "== [P47.3c] force /var/log via LAST drop-in =="
ok "svc=$SVC base=$BASE"

ok "== current DropInPaths/ExecStart =="
systemctl show "$SVC" -p DropInPaths -p ExecStart --no-pager | tee -a "$LOG" >/dev/null || true

VLOG="/var/log/vsp-ui-8910"
sudo mkdir -p "$VLOG"
sudo chown test:test "$VLOG"
sudo chmod 0750 "$VLOG"
ok "varlog ready: $VLOG"

# parse current ExecStart argv
cur="$(systemctl show "$SVC" -p ExecStart --no-pager | sed -n 's/^ExecStart=.*argv\[\]=//p' | head -n 1)"
[ -n "$cur" ] || fail "cannot parse current ExecStart"

# rewrite to /var/log
new="$(echo "$cur" | sed -E "s#--access-logfile [^ ]+#--access-logfile $VLOG/ui_8910.access.log#g; s#--error-logfile [^ ]+#--error-logfile $VLOG/ui_8910.error.log#g")"

OVDIR="/etc/systemd/system/${SVC}.d"
OVCONF="$OVDIR/zzzz-99999-varlog.conf"
sudo mkdir -p "$OVDIR"
if sudo test -f "$OVCONF"; then sudo cp -f "$OVCONF" "${OVCONF}.bak_${TS}"; ok "backup: ${OVCONF}.bak_${TS}"; fi

# NOTE: clear ExecStart first (systemd override rule)
sudo bash -lc "cat > '$OVCONF' <<CONF
[Service]
UMask=027
ExecStart=
ExecStart=$new
CONF"
ok "wrote LAST drop-in: $OVCONF"

ok "daemon-reload + restart"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

code="000"
for i in $(seq 1 80); do
  code="$(probe "$BASE/vsp5")"
  [ "$code" = "200" ] && break
  sleep 0.25
done
ok "probe /vsp5=$code"
[ "$code" = "200" ] || { systemctl status "$SVC" --no-pager | tail -n 120 | tee -a "$LOG" >/dev/null; fail "service not healthy"; }

ok "== ExecStart after =="
systemctl show "$SVC" -p ExecStart --no-pager | tee -a "$LOG" >/dev/null || true

# generate some traffic to force logfile write
for i in 1 2 3; do curl -fsS "$BASE/vsp5" >/dev/null || true; done

ok "== varlog listing =="
ls -lah "$VLOG" 2>&1 | tee -a "$LOG" >/dev/null || true
stat -c '%A %a %U:%G %n' "$VLOG"/ui_8910.*.log 2>/dev/null | tee -a "$LOG" >/dev/null || true

# final assertion
if systemctl show "$SVC" -p ExecStart --no-pager | grep -q "$VLOG/ui_8910.error.log"; then
  ok "SUCCESS: ExecStart points to /var/log"
else
  warn "NOT applied: ExecStart still not pointing to /var/log (a later drop-in may still override)"
  ok "hint: check systemctl cat $SVC"
  exit 2
fi

ok "DONE: $LOG"
