#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
echo "[RID]=$RID"

U="$BASE/api/vsp/findings_page?rid=$RID&offset=0&limit=3&debug=1"
H="/tmp/vsp_fp_hdr.$$"
B="/tmp/vsp_fp_body.$$"
HTTP="$(curl -sS -D "$H" -o "$B" -w "%{http_code}" "$U" || true)"
echo "[HTTP]=$HTTP bytes=$(wc -c <"$B" 2>/dev/null || echo 0)"
echo "---- HEAD (first 25 lines) ----"; sed -n '1,25p' "$H" || true
echo "---- BODY (first 240 chars) ----"; head -c 240 "$B" || true; echo
rm -f "$H" "$B" || true
