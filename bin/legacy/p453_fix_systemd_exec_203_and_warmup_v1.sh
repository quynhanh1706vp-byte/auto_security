#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p453_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need date; need bash; need curl
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo for systemd drop-in" | tee -a "$OUT/log.txt"; exit 2; }
need systemctl

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/log.txt"; }

DROP_DIR="/etc/systemd/system/${SVC}.d"
DROP_FILE="${DROP_DIR}/50-p453-safe-stop-and-warmup.conf"

log "[INFO] OUT=$OUT SVC=$SVC BASE=$BASE"
log "[INFO] writing drop-in: $DROP_FILE"

sudo mkdir -p "$DROP_DIR"

# Override potentially broken ExecStop/Reload (cause of 203/EXEC) + add warmup post-start.
sudo bash -lc "cat > '$DROP_FILE' <<'CONF'
[Service]
# If old unit/drop-in has a broken ExecStop/ExecReload => 203/EXEC, wipe then set safe ones.
ExecStop=
ExecStop=/bin/kill -TERM \$MAINPID
ExecReload=
ExecReload=/bin/kill -HUP \$MAINPID

# Warmup: wait until /c/settings returns 200-ish before declaring service usable.
# Keep it short and resilient; never fail the service just because warmup curl failed.
ExecStartPost=/bin/bash -lc 'BASE=${VSP_UI_BASE:-http://127.0.0.1:8910}; \
  for i in \$(seq 1 40); do \
    curl -fsS --connect-timeout 0.2 --max-time 0.8 \"\$BASE/c/settings\" >/dev/null && exit 0; \
    sleep 0.25; \
  done; exit 0'
CONF"

log "[INFO] daemon-reload + restart"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

log "[INFO] status after restart"
(systemctl status "$SVC" --no-pager -l || true) | tee "$OUT/systemctl_status_after.txt" >/dev/null

log "[INFO] smoke with retry-connrefused"
pages=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${pages[@]}"; do
  if curl -fsS --retry 20 --retry-connrefused --retry-delay 0.2 --max-time 2 \
        --connect-timeout 0.3 "$BASE$p" -o "$OUT/$(echo "$p" | tr '/' '_').html"; then
    log "[OK] $p"
  else
    log "[FAIL] $p"
  fi
done

log "[INFO] journal tail"
(journalctl -u "$SVC" -n 120 --no-pager || true) | tee "$OUT/journal_tail.txt" >/dev/null

log "[DONE] check: $OUT/*"
