#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"   # default RID for warm (you can override)
N="${N:-8}"                            # ~= workers*2

# wait UI ready hard (up to ~45s)
for i in $(seq 1 90); do
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null && break
  sleep 0.5
done

# 1) single long warm (avoid curl28)
curl -fsS --connect-timeout 1 --max-time 25 \
  "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0" >/dev/null || true

# 2) parallel warm short
for i in $(seq 1 "$N"); do
  curl -sS --connect-timeout 1 --max-time 10 \
    "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0" >/dev/null || true &
done
wait

echo "[OK] warmup_findings_after_ready done (RID=$RID N=$N)"
