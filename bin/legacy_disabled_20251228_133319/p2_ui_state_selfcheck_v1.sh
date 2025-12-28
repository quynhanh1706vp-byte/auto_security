#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

say(){ printf "\n== %s ==\n" "$*"; }

say "Pages (HTTP code)"
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$p" || true)"
  echo "$p => $code"
done

say "Anchor check (/vsp5 must contain #vsp-dashboard-main)"
curl -sS "$BASE/vsp5" | grep -n 'id="vsp-dashboard-main"' | head -n 3 || echo "MISSING"

say "Key APIs (expect 200)"
for u in \
  /api/vsp/rid_latest \
  /api/vsp/dash_kpis \
  /api/vsp/dash_charts \
  /api/ui/settings_v2 \
  /api/ui/rule_overrides_v2
do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

say "Assets referenced by /vsp5 (HEAD 200?)"
# lấy danh sách static asset trong html /vsp5 rồi HEAD từng cái
curl -sS "$BASE/vsp5" \
| grep -oE 'static/(js|css)/[^"]+\.(js|css)\?v=[^"]+' \
| sort -u \
| while read -r a; do
    code="$(curl -s -o /dev/null -w "%{http_code}" -I "$BASE/$a" || true)"
    echo "$a => $code"
  done

say "Recent noisy logs (BOOTFIX/READY_STUB/KPI_V4)"
if journalctl -u "$SVC" -n 220 --no-pager >/dev/null 2>&1; then
  journalctl -u "$SVC" -n 220 --no-pager | egrep -n "VSP_BOOTFIX|VSP_READY_STUB|VSP_KPI_V4" | tail -n 30 || true
else
  echo "[SKIP] journalctl not permitted (no sudo)"
fi
