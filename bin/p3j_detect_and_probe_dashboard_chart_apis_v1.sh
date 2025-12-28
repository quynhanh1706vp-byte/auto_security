#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need grep; need sed; need sort; need uniq; need curl; need head; need tr

echo "== [0] pick RID latest =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"

echo "== [1] extract /api/vsp/* endpoints referenced by dashboard JS =="
# scan a bit wider than 2 files to catch trend/topcwe modules
grep -RIn --exclude='*.bak_*' --exclude='*.disabled_*' \
  -E '"/api/vsp/|'\''/api/vsp/|`/api/vsp/' static/js \
| grep -E 'dashboard|trend|topcwe|cwe|tool|bucket|severity|risk|kpi|chart|live' \
| head -n 400 > /tmp/vsp_js_api_hits.txt || true

if [ ! -s /tmp/vsp_js_api_hits.txt ]; then
  echo "[ERR] no api hits found in JS (unexpected)"
  exit 2
fi

# extract urls like /api/vsp/xxxx
cat /tmp/vsp_js_api_hits.txt \
| sed -n 's/.*\(\/*api\/vsp\/[a-zA-Z0-9_\/-]\+\).*/\1/p' \
| sed 's/[\"'\''\`].*$//' \
| sort | uniq > /tmp/vsp_api_list.txt

echo "[FOUND endpoints]"; nl -ba /tmp/vsp_api_list.txt | head -n 120

echo "== [2] probe endpoints (HTTP + ok field) =="
while read -r ep; do
  [ -n "$ep" ] || continue
  url="$BASE$ep"
  # add rid if not present & likely needs rid
  if echo "$ep" | grep -qE 'trend'; then
    url="$url"
  else
    if echo "$url" | grep -q '\?'; then
      url="${url}&rid=${RID}"
    else
      url="${url}?rid=${RID}"
    fi
  fi

  code="$(curl -sS -o /tmp/vsp_probe_body.json -w '%{http_code}' --max-time 4 "$url" || true)"
  okfield="$("$PY" - <<'PY' 2>/dev/null || true
import json
try:
    j=json.load(open("/tmp/vsp_probe_body.json","r",encoding="utf-8"))
    print(j.get("ok", None))
except Exception:
    print("NON_JSON")
PY
)"
  echo "EP=$ep code=$code ok=$okfield"
done < /tmp/vsp_api_list.txt

echo "== [3] hint: endpoints that are 404/500/ok=false are the ones making charts degraded =="
echo "[DONE] p3j_detect_and_probe_dashboard_chart_apis_v1"
