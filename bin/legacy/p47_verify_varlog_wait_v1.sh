#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT=out_ci; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_verify_varlog_wait_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need systemctl; need curl; need ls; need stat; need head; need tail

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

ok "== [P47 VERIFY] wait-loop health + varlog check =="
ok "svc=$SVC base=$BASE"

ok "== ExecStart =="
systemctl show "$SVC" -p ExecStart --no-pager | tee -a "$LOG" >/dev/null || true

ok "== wait /vsp5 up to 15s =="
code="000"
for i in $(seq 1 50); do
  code="$(probe "$BASE/vsp5")"
  [ "$code" = "200" ] && break
  sleep 0.3
done
echo "vsp5=$code" | tee -a "$LOG"
[ "$code" = "200" ] || { warn "still not 200, see $LOG"; exit 2; }

ok "== varlog listing (if exists) =="
ls -lah /var/log/vsp-ui-8910 2>&1 | tee -a "$LOG" >/dev/null || true
stat -c '%A %a %U:%G %n' /var/log/vsp-ui-8910/ui_8910.*.log 2>/dev/null | tee -a "$LOG" >/dev/null || true

ok "DONE: $LOG"
