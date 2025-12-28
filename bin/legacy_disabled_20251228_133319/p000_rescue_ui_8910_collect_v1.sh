#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/rescue/RESCUE_${TS}"
mkdir -p "$OUT"

echo "[INFO] SVC=$SVC BASE=$BASE OUT=$OUT" | tee "$OUT/rescue.log"

# snapshot before
{
  echo "== systemctl status (before) ==";
  systemctl status "$SVC" --no-pager || true;
  echo;
  echo "== ss -ltnp | grep 8910 (before) ==";
  ss -ltnp | grep -E ':8910\b' || true;
  echo;
  echo "== journalctl -u (last 200, before) ==";
  journalctl -u "$SVC" -n 200 --no-pager || true;
} > "$OUT/before.txt" 2>&1 || true

# restart
echo "[INFO] restarting $SVC" | tee -a "$OUT/rescue.log"
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC" || true

# wait up
ok=0
for i in $(seq 1 60); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1; then
    ok=1; break
  fi
  sleep 1
done

# snapshot after
{
  echo "== systemctl status (after) ==";
  systemctl status "$SVC" --no-pager || true;
  echo;
  echo "== ss -ltnp | grep 8910 (after) ==";
  ss -ltnp | grep -E ':8910\b' || true;
  echo;
  echo "== journalctl -u (last 250, after) ==";
  journalctl -u "$SVC" -n 250 --no-pager || true;
} > "$OUT/after.txt" 2>&1 || true

if [ "$ok" -ne 1 ]; then
  echo "[FAIL] UI not reachable on $BASE/vsp5 (see $OUT/after.txt)" | tee -a "$OUT/rescue.log"
  echo "$OUT" > "$OUT/LATEST_PATH.txt"
  exit 1
fi

echo "[OK] UI is up: $BASE/vsp5" | tee -a "$OUT/rescue.log"
echo "$OUT" > "$OUT/LATEST_PATH.txt"
