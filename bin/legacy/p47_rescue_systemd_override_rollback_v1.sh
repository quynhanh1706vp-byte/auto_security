#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_rescue_override_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need sudo; need systemctl; need ls; need head; need cp; need curl; need tail

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

OVDIR="/etc/systemd/system/${SVC}.d"
OVCONF="${OVDIR}/override.conf"

ok "== [P47 RESCUE] rollback override =="
ok "svc=$SVC base=$BASE"

# pick latest backup (umask backups you created)
bak="$(ls -1t ${OVCONF}.bak_umask_* 2>/dev/null | head -n 1 || true)"
[ -n "$bak" ] || bak="$(ls -1t ${OVCONF}.bak_* 2>/dev/null | head -n 1 || true)"
[ -n "$bak" ] || fail "no override backup found: ${OVCONF}.bak_*"

if sudo test -f "$OVCONF"; then
  sudo cp -f "$OVCONF" "${OVCONF}.bad_${TS}"
  ok "saved current override -> ${OVCONF}.bad_${TS}"
fi

sudo cp -f "$bak" "$OVCONF"
ok "restored override from: $bak"

ok "daemon-reload + restart"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

code="$(probe "$BASE/vsp5")"
ok "probe /vsp5=$code"

if [ "$code" != "200" ]; then
  warn "not healthy -> status + journal tail"
  systemctl status "$SVC" --no-pager | tail -n 80 | tee -a "$LOG" >/dev/null || true
  sudo journalctl -u "$SVC" --no-pager -n 160 | tee -a "$LOG" >/dev/null || true
  fail "still down (see $LOG)"
fi

ok "UP (200). log=$LOG"
