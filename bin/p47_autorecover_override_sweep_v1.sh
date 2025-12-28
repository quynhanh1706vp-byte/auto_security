#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT=out_ci; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_autorecover_override_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need sudo; need systemctl; need ls; need head; need tail; need cp; need curl; need sed

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }

OVDIR="/etc/systemd/system/${SVC}.d"
OVCONF="${OVDIR}/override.conf"

probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

ok "== [P47 AUTO-RECOVER] sweep overrides =="
ok "svc=$SVC base=$BASE"

sudo mkdir -p "$OVDIR"

# collect candidates
mapfile -t cands < <(ls -1t ${OVCONF}.bak_* ${OVCONF}.bad_* 2>/dev/null || true)
ok "candidates=${#cands[@]}"

try_apply(){
  local mode="$1"; shift
  local src="${1:-}"
  ok "-- try: $mode ${src}"
  if [ "$mode" = "NO_OVERRIDE" ]; then
    if sudo test -f "$OVCONF"; then sudo cp -f "$OVCONF" "${OVCONF}.last_${TS}" || true; fi
    sudo rm -f "$OVCONF" || true
  else
    [ -n "$src" ] || return 1
    sudo test -f "$src" || return 1
    if sudo test -f "$OVCONF"; then sudo cp -f "$OVCONF" "${OVCONF}.last_${TS}" || true; fi
    sudo cp -f "$src" "$OVCONF"
  fi

  sudo systemctl daemon-reload
  sudo systemctl restart "$SVC" || true

  # small wait loop
  for i in $(seq 1 30); do
    c=$(probe "$BASE/vsp5")
    if [ "$c" = "200" ]; then
      ok "UP: /vsp5=200 (mode=$mode src=$src)"
      return 0
    fi
    sleep 0.3
  done
  warn "still not 200 after restart (mode=$mode src=$src)"
  return 1
}

# 0) try without override first
if try_apply NO_OVERRIDE; then
  ok "SUCCESS: running without override.conf"
  exit 0
fi

# 1) sweep backups
for src in "${cands[@]}"; do
  if try_apply FROM_BACKUP "$src"; then
    ok "SUCCESS: restored override from $src"
    exit 0
  fi
done

warn "ALL CANDIDATES FAILED"
warn "== systemctl status =="
systemctl status "$SVC" --no-pager | tail -n 120 | tee -a "$LOG" >/dev/null || true
warn "== journal tail =="
sudo journalctl -u "$SVC" --no-pager -n 220 | tee -a "$LOG" >/dev/null || true

exit 2
