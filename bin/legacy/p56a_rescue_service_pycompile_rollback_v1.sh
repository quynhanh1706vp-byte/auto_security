#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56a_service_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need journalctl; need curl; need awk; need ls; need head

log(){ echo "[$(date +%H:%M:%S)] $*"; }

PYFILES=( "vsp_demo_app.py" "wsgi_vsp_ui_gateway.py" )

pick_good_py_bak(){
  local f="$1"
  # find backups, newest first
  local b
  while IFS= read -r b; do
    python3 -m py_compile "$b" >/dev/null 2>&1 && { echo "$b"; return 0; }
  done < <(find . -maxdepth 1 -type f \( -name "$(basename "$f").bak_*" -o -name "$(basename "$f").bak*" \) -printf "%T@ %p\n" 2>/dev/null | sort -nr | awk '{print $2}')
  return 1
}

compile_or_rollback(){
  local f="$1"
  [ -f "$f" ] || { log "[SKIP] missing $f"; return 0; }
  if python3 -m py_compile "$f" >"$EVID/py_compile_$(basename "$f").ok" 2>"$EVID/py_compile_$(basename "$f").err"; then
    log "[OK] py_compile OK: $f"
    return 0
  fi
  log "[WARN] py_compile FAIL: $f"
  tail -n 30 "$EVID/py_compile_$(basename "$f").err" || true

  local bak=""
  if bak="$(pick_good_py_bak "$f")"; then
    cp -f "$f" "$EVID/$(basename "$f").pre_restore"
    cp -f "$bak" "$f"
    log "[FIX] restored $f <= $bak"
    python3 -m py_compile "$f" >/dev/null 2>&1 || { log "[ERR] still fail after restore: $f"; return 1; }
    return 0
  fi

  log "[ERR] no good backup found for $f"
  return 1
}

log "== [P56A/1] pre status =="
sudo systemctl status "$SVC" --no-pager > "$EVID/systemctl_status_before.txt" 2>&1 || true

log "== [P56A/2] py_compile gate + auto rollback if needed =="
ok=1
for f in "${PYFILES[@]}"; do
  compile_or_rollback "$f" || ok=0
done

log "== [P56A/3] restart service =="
sudo systemctl restart "$SVC" || true

log "== [P56A/4] wait /vsp5 200 (max 60s) =="
up=0
for i in $(seq 1 30); do
  code="$(curl -fsS -o /dev/null -w "%{http_code}" --max-time 3 "$BASE/vsp5" || echo 000)"
  echo "try=$i code=$code" >> "$EVID/health_wait.txt"
  if [ "$code" = "200" ]; then up=1; break; fi
  sleep 2
done

log "== [P56A/5] capture logs =="
sudo systemctl status "$SVC" --no-pager > "$EVID/systemctl_status_after.txt" 2>&1 || true
sudo journalctl -u "$SVC" -n 120 --no-pager > "$EVID/journal_tail.txt" 2>&1 || true

if [ "$up" = "1" ]; then
  log "[PASS] service is UP (200)"
else
  log "[FAIL] service still DOWN. See $EVID/journal_tail.txt"
  exit 1
fi

log "[DONE] Evidence: $EVID"
