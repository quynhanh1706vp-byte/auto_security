#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56_js_rescue_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need ls; need head; need awk; need sed; need grep; need curl

log(){ echo "[$(date +%H:%M:%S)] $*"; }

# 1) Candidates from your screenshots (hard blockers)
CANDS=(
  "static/js/vsp_tabs4_autorid_v1.js"
  "static/js/vsp_dashboard_luxe_v1.js"
  "static/js/vsp_dashboard_consistency_patch_v1.js"
  "static/js/vsp_runs_kpi_compact_v1.js"
  "static/js/vsp_runs_quick_actions_v1.js"
  "static/js/vsp_pin_dataset_badge_v1.js"
  "static/js/vsp_data_source_tab_v3.js"
)

node_check(){
  local f="$1"
  node --check "$f" >/dev/null 2>"$EVID/$(basename "$f").node_check.err" && return 0
  return 1
}

pick_good_backup(){
  local f="$1"
  # backups created by your patch scripts are like: file.js.bak_XXXX_YYYY...
  local pat1="${f}.bak_"*
  local pat2="${f}.bak"*  # broaden
  local b
  for b in $(ls -1t $pat1 $pat2 2>/dev/null || true); do
    if node --check "$b" >/dev/null 2>&1; then
      echo "$b"
      return 0
    fi
  done
  return 1
}

restore_if_bad(){
  local f="$1"
  [ -f "$f" ] || { log "[SKIP] missing $f"; return 0; }

  if node_check "$f"; then
    log "[OK] syntax OK: $f"
    echo "OK $f" >> "$EVID/summary.txt"
    return 0
  fi

  log "[WARN] syntax FAIL: $f"
  tail -n 3 "$EVID/$(basename "$f").node_check.err" || true

  local bak=""
  if bak="$(pick_good_backup "$f")"; then
    cp -f "$f" "$EVID/$(basename "$f").pre_restore"
    cp -f "$bak" "$f"
    log "[FIX] restored from backup: $bak -> $f"
    echo "RESTORED $f <= $bak" >> "$EVID/summary.txt"
  else
    log "[ERR] no usable backup found for $f"
    echo "NO_BACKUP $f" >> "$EVID/summary.txt"
  fi

  # re-check
  if node_check "$f"; then
    log "[OK] now syntax OK: $f"
  else
    log "[ERR] still syntax FAIL after restore: $f"
    tail -n 5 "$EVID/$(basename "$f").node_check.err" || true
    return 1
  fi
}

log "== [P56] JS syntax rescue via rollback =="
for f in "${CANDS[@]}"; do
  restore_if_bad "$f" || true
done

log "== [P56] restart service (safe) =="
sudo systemctl restart "$SVC" >/dev/null 2>&1 || true

log "== [P56] quick health =="
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  code="$(curl -fsS -o /dev/null -w "%{http_code}" --max-time 6 "$BASE$p" || echo 000)"
  echo "$p code=$code" | tee -a "$EVID/health.txt"
done

log "[DONE] Evidence: $EVID"
log "IMPORTANT: Hard refresh browser (Ctrl+Shift+R) after this."
