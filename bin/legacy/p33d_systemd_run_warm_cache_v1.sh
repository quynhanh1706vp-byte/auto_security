#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE_IPV4="http://127.0.0.1:8910"
LOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/warm_cache.log"
DROP="/etc/systemd/system/${SVC}.d/40-warm-cache.conf"
WARM_BIN="/usr/local/bin/vsp_warm_cache.sh"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need systemd-run; need bash; need curl

sudo mkdir -p "/etc/systemd/system/${SVC}.d"

# Reset old ExecStartPost lines then add a deterministic one
sudo tee "$DROP" >/dev/null <<EOF
[Service]
ExecStartPost=
ExecStartPost=/bin/bash -lc 'systemd-run --unit=vsp-ui-warm-cache --collect --no-block ${WARM_BIN} ${BASE_IPV4} ${LOG}'
EOF

echo "[OK] wrote $DROP"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "== [CHECK] warm unit status =="
sleep 1
sudo systemctl --no-pager --full status vsp-ui-warm-cache | head -n 30 || true

echo "== [CHECK] warm journal =="
sudo journalctl -u vsp-ui-warm-cache --no-pager -n 80 || true

echo "== [SMOKE] /vsp5 2 calls (expect fast + HIT-RAM/HIT-DISK) =="
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "$BASE_IPV4/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "$BASE_IPV4/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
