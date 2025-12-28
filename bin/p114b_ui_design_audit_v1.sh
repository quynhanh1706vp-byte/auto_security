#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need head

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

RID="$(curl -fsS "$BASE/api/ui/runs_v3?limit=1&include_ci=1" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["rid"])')"

echo "[INFO] BASE=$BASE"
echo "[INFO] RID=$RID"
echo

fetch_html(){
  local p="$1"
  local out="/tmp/vsp_${p//\//_}.html"
  curl -fsS --connect-timeout 2 --max-time 15 "$BASE$p?rid=$RID" -o "$out"
  echo "$out"
}

list_scripts(){
  local f="$1"
  grep -oE '<script[^>]+src="[^"]+"' "$f" \
    | sed -E 's/.*src="([^"]+)".*/\1/' \
    | sed 's/&amp;/\&/g' \
    | head -n 200
}

echo "== [A] routes exist? =="
for p in /vsp5 /c/dashboard /runs /data_source /settings /rule_overrides; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 8 "$BASE$p?rid=$RID" || echo 000)"
  echo "$p => $code"
done

echo
echo "== [B] HTML script inventory (vsp5) =="
F1="$(fetch_html /vsp5)"
list_scripts "$F1" | sed 's/^/  /'

echo
echo "== [C] HTML script inventory (c/dashboard) =="
F2="$(fetch_html /c/dashboard)"
list_scripts "$F2" | sed 's/^/  /'

echo
echo "== [D] Look for chart-ish JS names =="
for name in trend chart topcwe donut kpi live charts; do
  echo "-- '$name' in vsp5 --"
  list_scripts "$F1" | grep -i "$name" || echo "  none"
  echo "-- '$name' in c/dashboard --"
  list_scripts "$F2" | grep -i "$name" || echo "  none"
done

echo
echo "== [E] Quick DOM hints (containers) =="
for f in "$F1" "$F2"; do
  echo "-- file=$f --"
  grep -Eo 'id="[^"]+"' "$f" | head -n 40 | sed 's/^/  /'
done

echo
echo "== [F] Probe common chart APIs (best-effort) =="
apis=(
  "/api/vsp/trend_v1"
  "/api/vsp/topcwe_v1"
  "/api/vsp/dashboard_kpis_v4"
  "/api/vsp/top_findings_v2?limit=5&rid=$RID"
)
for a in "${apis[@]}"; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 10 "$BASE$a" || echo 000)"
  echo "$a => $code"
done

echo
echo "== [G] VERDICT hint =="
if list_scripts "$F2" | grep -Ei 'trend|chart|topcwe|donut|charts' >/dev/null; then
  echo "[HINT] /c/dashboard is the real designed dashboard (has chart-ish JS)."
else
  echo "[HINT] /c/dashboard also looks minimal => missing template includes / JS bundle."
fi

if list_scripts "$F1" | grep -Ei 'trend|chart|topcwe|donut|charts' >/dev/null; then
  echo "[HINT] /vsp5 has chart-ish JS embedded."
else
  echo "[HINT] /vsp5 is a minimal shell (no chart JS embedded) => design is likely on /c/dashboard."
fi
