#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need tail; need grep; need sed

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
ELOG="out_ci/ui_8910.error.log"

RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("items",[{}])[0].get("run_id",""))')"
echo "[RID]=$RID"

echo "== hit findings_v2 (expect 200; currently 500) =="
curl -sS -i "$BASE/api/ui/findings_v2?rid=$RID&limit=5&offset=0&q=" | sed -n '1,20p' || true

echo
echo "== tail error log (last 120) =="
tail -n 120 "$ELOG" || true

echo
echo "== grep findings_v2 stack (last 80 matching lines) =="
grep -n "findings_v2" "$ELOG" | tail -n 80 || true
