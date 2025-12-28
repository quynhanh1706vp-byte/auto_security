#!/usr/bin/env bash
set -euo pipefail
RID="${RID:?need RID=...}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
N="${N:-8}"   # N ≈ workers*2

sudo systemctl restart "$SVC"

# wait UI ready
for i in $(seq 1 90); do
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null && break
  sleep 0.5
done

# warmup findings in parallel (best-effort)
for i in $(seq 1 "$N"); do
  curl -sS --connect-timeout 1 --max-time 10 \
    "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0" >/dev/null || true &
done
wait

# CIO smoke
RID="$RID" bash bin/vsp_ui_ops_cio_smoke_v1.sh
