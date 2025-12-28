#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p452_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need bash; need python3; need curl
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true
command -v journalctl >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true
command -v timeout >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/log.txt"; }
as_root(){ if command -v sudo >/dev/null 2>&1; then sudo "$@"; else "$@"; fi; }

probe(){
  # <= 1s total, no long hang
  curl -fsS --connect-timeout 0.2 --max-time 0.8 "$BASE/c/settings" -o /dev/null
}

log "[INFO] OUT=$OUT BASE=$BASE SVC=$SVC"

log "[INFO] systemctl status + show ExecStart/Environment"
(as_root systemctl status "$SVC" --no-pager -l || true) | tee "$OUT/systemctl_status.txt" >/dev/null
(as_root systemctl show "$SVC" -p ExecStart -p Environment -p FragmentPath -p DropInPaths --no-pager || true) \
  | tee "$OUT/systemctl_show.txt" >/dev/null

log "[INFO] ss :8910"
(ss -lntp 2>/dev/null | grep -E '(:8910\b)' || true) | tee "$OUT/ss_8910.txt" >/dev/null

log "[INFO] restart service"
(as_root systemctl restart "$SVC" || true)

log "[INFO] immediate status after restart"
(as_root systemctl status "$SVC" --no-pager -l || true) | tee "$OUT/systemctl_status_after.txt" >/dev/null

log "[INFO] quick probe (no loop)"
if probe; then
  log "[GREEN] 8910 is reachable"
else
  log "[RED] 8910 still NOT reachable (dump journal tail)"
fi

log "[INFO] journal tail (last 220 lines)"
(as_root journalctl -u "$SVC" -n 220 --no-pager || true) | tee "$OUT/journal_tail.txt" >/dev/null

log "[INFO] compile check entrypoints (common crash reasons)"
for f in wsgi_vsp_ui_gateway.py vsp_demo_app.py; do
  if [ -f "$f" ]; then
    if python3 -m py_compile "$f" 2>"$OUT/py_compile_${f}.err"; then
      log "[OK] py_compile $f"
    else
      log "[FAIL] py_compile $f (see $OUT/py_compile_${f}.err)"
    fi
  else
    log "[WARN] missing $f"
  fi
done

log "[INFO] optional local errlog tails (if exist)"
for f in out_ci/ui_8910.error.log /var/log/vsp-ui-8910.error.log /var/log/vsp-ui-8910.log; do
  if [ -f "$f" ]; then
    log "[INFO] tail -n 120 $f"
    tail -n 120 "$f" > "$OUT/tail_$(echo "$f" | tr '/' '_').txt" || true
  fi
done

log "[DONE] open: $OUT/systemctl_status_after.txt $OUT/journal_tail.txt $OUT/py_compile_*.err"
