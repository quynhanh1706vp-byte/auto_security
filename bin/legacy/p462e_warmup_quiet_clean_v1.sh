#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
DROP="/etc/systemd/system/${SVC}.d/60-p462e-warmup-clean.conf"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/p462e_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need sudo; need systemctl; need date; need tee

echo "[INFO] writing $DROP" | tee -a "$OUT/log.txt"
sudo mkdir -p "$(dirname "$DROP")"
sudo cp -f "$DROP" "$OUT/$(basename "$DROP").bak_${TS}" 2>/dev/null || true

sudo tee "$DROP" >/dev/null <<'CONF'
# P462e: quiet + resilient warmup (never fail service)
[Service]
ExecStartPost=
ExecStartPost=/bin/bash -lc 'BASE=http://127.0.0.1:8910; for i in $(seq 1 30); do curl -fsS --connect-timeout 1 --max-time 2 "$BASE/c/settings" >/dev/null 2>&1 && exit 0; curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1 && exit 0; sleep 0.4; done; exit 0'
CONF

echo "[INFO] daemon-reload + restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

echo "== effective ExecStartPost ==" | tee -a "$OUT/log.txt"
sudo systemctl show "$SVC" -p ExecStartPost --no-pager | tee -a "$OUT/log.txt"

echo "[OK] P462e done: $OUT/log.txt" | tee -a "$OUT/log.txt"
