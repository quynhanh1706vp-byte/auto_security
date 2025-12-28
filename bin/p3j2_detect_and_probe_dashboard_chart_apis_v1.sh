#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need grep; need sed; need sort; need uniq; need curl; need head

echo "== [0] pick RID latest =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"

echo "== [1] extract /api/vsp/* endpoints referenced by JS (broad scan) =="
grep -RIn --exclude='*.bak_*' --exclude='*.disabled_*' \
  -E '"/api/vsp/|'\''/api/vsp/|`/api/vsp/|"/api\/vsp\/|'\''/api\/vsp\/' static/js \
| head -n 1200 > /tmp/vsp_js_api_hits.txt || true

if [ ! -s /tmp/vsp_js_api_hits.txt ]; then
  echo "[ERR] no api hits found in JS"
  exit 2
fi

# Extract paths like /api/vsp/xxx (and also api/vsp/xxx), normalize to start with /
cat /tmp/vsp_js_api_hits.txt \
| sed -n 's/.*\(\/*api\/vsp\/[a-zA-Z0-9_\/-]\+\).*/\1/p' \
| sed 's/[\"'\''\`].*$//' \
| sed 's#^api/#/api/#' \
| awk 'NF' \
| sort | uniq > /tmp/vsp_api_list_norm.txt

echo "[FOUND endpoints]"; nl -ba /tmp/vsp_api_list_norm.txt | head -n 120

echo "== [2] probe endpoints (HTTP + ok + short body for failures) =="
while read -r ep; do
  [ -n "$ep" ] || continue

  # skip endpoints that obviously require path param (ending with /)
  if [[ "$ep" == */ ]]; then
    echo "EP=$ep SKIP(trailing-slash likely needs param)"
    continue
  fi

  url="$BASE$ep"
  if [[ "$url" == *"?"* ]]; then
    url="${url}&rid=${RID}"
  else
    url="${url}?rid=${RID}"
  fi

  body="/tmp/vsp_probe_body.json"
  code="$(curl -sS -o "$body" -w '%{http_code}' --max-time 5 "$url" || true)"

  okfield="$("$PY" - <<'PY' 2>/dev/null || true
import json
try:
    j=json.load(open("/tmp/vsp_probe_body.json","r",encoding="utf-8"))
    print(j.get("ok", None))
except Exception:
    print("NON_JSON")
PY
)"

  if [ "$code" != "200" ] || [ "$okfield" = "False" ] || [ "$okfield" = "NON_JSON" ]; then
    echo "EP=$ep code=$code ok=$okfield url=$url"
    echo "  body_head:"
    head -c 240 "$body" 2>/dev/null | sed 's/[^[:print:]\t]/?/g'
    echo
  else
    echo "EP=$ep code=$code ok=$okfield"
  fi
done < /tmp/vsp_api_list_norm.txt

echo "[DONE] p3j2_detect_and_probe_dashboard_chart_apis_v1"
