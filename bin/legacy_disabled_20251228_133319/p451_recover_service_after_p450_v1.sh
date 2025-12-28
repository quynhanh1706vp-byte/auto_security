#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p451_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need python3
command -v sudo >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true
command -v journalctl >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/log.txt"; }

wait_port(){
  local tries="${1:-80}"
  for i in $(seq 1 "$tries"); do
    if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/c/settings" -o /dev/null; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

dump_status(){
  log "[INFO] systemctl status (short)"
  if command -v systemctl >/dev/null 2>&1; then
    (systemctl status "$SVC" --no-pager -l || true) | tee "$OUT/systemctl_status.txt" >/dev/null
  fi
  if command -v ss >/dev/null 2>&1; then
    (ss -lntp 2>/dev/null | grep -E '(:8910\b)' || true) | tee "$OUT/ss_8910.txt" >/dev/null
  fi
}

py_compile_or_restore(){
  local f="$1"
  [ -f "$f" ] || { log "[WARN] missing $f"; return 0; }

  if python3 -m py_compile "$f" 2>"$OUT/py_compile_$(basename "$f").err"; then
    log "[OK] py_compile $f"
    return 0
  fi

  log "[FAIL] py_compile $f (see $OUT/py_compile_$(basename "$f").err)"
  # auto-restore newest backup if exists
  local bak
  bak="$(ls -1t "${f}".bak_* 2>/dev/null | head -n1 || true)"
  if [ -n "$bak" ]; then
    log "[INFO] restoring $f from newest backup: $bak"
    cp -f "$bak" "$f"
    if python3 -m py_compile "$f" 2>>"$OUT/py_compile_$(basename "$f").err"; then
      log "[OK] py_compile after restore: $f"
      return 0
    fi
    log "[FAIL] still cannot compile after restore: $f"
    return 1
  else
    log "[WARN] no backup found for $f (pattern: ${f}.bak_*)"
    return 1
  fi
}

log "[INFO] OUT=$OUT BASE=$BASE SVC=$SVC"
dump_status

log "[INFO] restarting $SVC"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
else
  systemctl restart "$SVC" || true
fi

log "[INFO] wait port 8910 by probing $BASE/c/settings"
if wait_port 80; then
  log "[GREEN] service is up"
else
  log "[RED] still cannot reach $BASE after restart"
  dump_status

  # Try to diagnose/auto-fix python entrypoints
  log "[INFO] compile check + auto-restore if needed"
  ok=1
  py_compile_or_restore "wsgi_vsp_ui_gateway.py" || ok=0
  py_compile_or_restore "vsp_demo_app.py" || ok=0

  if [ "$ok" -eq 1 ]; then
    log "[INFO] compile OK now, restarting again"
    if command -v sudo >/dev/null 2>&1; then
      sudo systemctl restart "$SVC" || true
    else
      systemctl restart "$SVC" || true
    fi
    if wait_port 80; then
      log "[GREEN] recovered: service is up"
    else
      log "[RED] service still down after compile OK"
    fi
  fi

  log "[INFO] last journal lines"
  if command -v journalctl >/dev/null 2>&1; then
    (journalctl -u "$SVC" -n 160 --no-pager || true) | tee "$OUT/journal_tail.txt" >/dev/null
  fi

  log "[AMBER] see: $OUT/systemctl_status.txt $OUT/journal_tail.txt $OUT/py_compile_*.err"
  exit 1
fi

# Final quick smoke
log "[INFO] quick smoke /c/*"
pages=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${pages[@]}"; do
  if curl -fsS --connect-timeout 2 --max-time 6 "$BASE$p" -o "$OUT/$(echo "$p" | tr '/' '_').html"; then
    log "[OK] $p"
  else
    log "[FAIL] $p"
  fi
done

log "[DONE] p451 complete"
