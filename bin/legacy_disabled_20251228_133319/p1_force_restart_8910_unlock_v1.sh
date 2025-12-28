#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ss; need sed; need awk; need kill; need rm; need sleep; need curl; need head

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "[BASE] $BASE"

echo "== remove stale locks =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

echo "== kill listeners on :8910 (hard) =="
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[INFO] killing pids: $PIDS"
  kill -9 $PIDS 2>/dev/null || true
fi

echo "== wait port free =="
for i in {1..25}; do
  if ss -ltn 2>/dev/null | grep -q ':8910'; then
    sleep 0.15
  else
    echo "[OK] port free"
    break
  fi
done

echo "== start single-owner =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify runs_v3 =="
curl -fsS -i "$BASE/api/ui/runs_v3?limit=1" | sed -n '1,15p'
echo
curl -fsS "$BASE/api/ui/runs_v3?limit=1" | head -c 260; echo

echo "[DONE] If browser cached, hard-refresh (Ctrl+Shift+R)."
