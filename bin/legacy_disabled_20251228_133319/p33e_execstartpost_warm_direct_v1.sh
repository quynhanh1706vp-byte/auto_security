#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE_IPV4="http://127.0.0.1:8910"
LOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/warm_cache.log"
DROP="/etc/systemd/system/${SVC}.d/40-warm-cache.conf"
WARM_BIN="/usr/local/bin/vsp_warm_cache.sh"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need bash; need timeout

sudo mkdir -p "/etc/systemd/system/${SVC}.d"

# Overwrite drop-in: run warm directly, bounded time, never fail service
sudo tee "$DROP" >/dev/null <<EOF
[Service]
ExecStartPost=
# P33e: deterministic warm (bounded 70s), do not fail service even if warm fails
ExecStartPost=/bin/bash -lc 'timeout 70s ${WARM_BIN} ${BASE_IPV4} ${LOG} || true'
EOF

echo "[OK] wrote $DROP"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "== [STATUS] =="
sudo systemctl --no-pager --full status "$SVC" | head -n 18 || true

echo "== [TAIL warm_cache.log] =="
sleep 1
tail -n 40 "$LOG" || true

echo "== [SMOKE] /vsp5 2 calls =="
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "${BASE_IPV4}/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "${BASE_IPV4}/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
