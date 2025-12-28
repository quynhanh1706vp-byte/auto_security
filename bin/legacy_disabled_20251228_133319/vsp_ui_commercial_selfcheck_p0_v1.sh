#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8910}"

echo "== LISTEN =="
ss -lntp | grep ':8910' || { echo "[FAIL] 8910 not listening"; exit 2; }

echo "== CORE ENDPOINTS =="
curl -sS "$BASE/findings_unified.json" | jq -r '.ok' | grep -qx true
curl -sS "$BASE/api/vsp/dashboard_commercial_v2" | jq -r '.ok,.total_findings' | tr '\n' ' '; echo
curl -sS "$BASE/api/vsp/dashboard_commercial_v2_harden" | jq -r '.ok,.items_len' | tr '\n' ' '; echo

echo "== UI PAGES =="
curl -sS "$BASE/vsp4" | head -n 1 | grep -qi '<!DOCTYPE' && echo "[OK] /vsp4 HTML"
curl -sS "$BASE/vsp5" | head -n 1 | grep -qi '<!DOCTYPE' && echo "[OK] /vsp5 HTML" || echo "[WARN] /vsp5 not HTML"

echo "== STATIC 404 CHECK (vsp4) =="
curl -sS "$BASE/vsp4" \
| grep -Eo '(src|href)="\/static\/[^"]+"' \
| sed -E 's/^(src|href)="//; s/"$//' \
| sort -u | while read -r p; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$p" || echo 000)"
    [ "$code" = "200" ] || echo "$code $p"
  done | head -n 50

echo "== DONE =="
