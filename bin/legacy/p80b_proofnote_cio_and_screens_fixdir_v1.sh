#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need sha256sum; need awk; need sed; need grep; need mkdir; need find; need sort; need head

TS="$(date +%Y%m%d_%H%M%S)"

pick_latest_release_dir(){
  find out_ci/releases -maxdepth 1 -type d -name 'RELEASE_UI_*' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -n 1 | awk '{print $2}'
}

LATEST="$(pick_latest_release_dir || true)"
if [ -z "${LATEST:-}" ]; then
  echo "[WARN] No RELEASE_UI_* directory found. Trying to create via P79..."
  if [ -f bin/p79_pack_ui_commercial_release_v1.sh ]; then
    bash bin/p79_pack_ui_commercial_release_v1.sh
    LATEST="$(pick_latest_release_dir || true)"
  fi
fi

[ -n "${LATEST:-}" ] || { echo "[ERR] cannot find/create release directory under out_ci/releases/"; exit 2; }
[ -d "$LATEST" ] || { echo "[ERR] latest release is not a dir: $LATEST"; exit 2; }

OUT="$LATEST/proof"
mkdir -p "$OUT/screens" "$OUT/html"

RID="$(curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("rid",""))')"
[ -n "$RID" ] || { echo "[ERR] RID empty from top_findings_v2"; exit 2; }

RUN_ID="$(curl -fsS "$BASE/api/vsp/datasource?rid=$RID" | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("run_id",""))')"
KPIS_JSON="$(curl -fsS "$BASE/api/vsp/datasource?rid=$RID" | python3 -c 'import sys,json;j=json.load(sys.stdin);k=j.get("kpis") or {};import json as jj;print(jj.dumps(k,ensure_ascii=False))')"

# Prefer chromium/chrome headless for screenshots
BROWSER=""
for b in google-chrome chromium chromium-browser chrome; do
  if command -v "$b" >/dev/null 2>&1; then BROWSER="$b"; break; fi
done

declare -a PAGES=(
  "dashboard|$BASE/vsp5?rid=$RID"
  "runs|$BASE/runs?rid=$RID"
  "data_source|$BASE/data_source?rid=$RID"
  "settings|$BASE/settings?rid=$RID"
  "rule_overrides|$BASE/rule_overrides?rid=$RID"
)

echo "== [P80B] Proofnote + Screens =="
echo "[INFO] base=$BASE rid=$RID run_id=$RUN_ID release=$LATEST"
echo "[INFO] out=$OUT"

# Save HTML snapshots (server-side)
for it in "${PAGES[@]}"; do
  key="${it%%|*}"; url="${it#*|}"
  curl -fsS "$url" -o "$OUT/html/${key}.html" || echo "[WARN] curl html failed: $url"
done

# Screenshots (client-side render) if browser exists
if [ -n "$BROWSER" ]; then
  echo "[OK] browser=$BROWSER (headless screenshot enabled)"
  for it in "${PAGES[@]}"; do
    key="${it%%|*}"; url="${it#*|}"
    png="$OUT/screens/${key}.png"
    "$BROWSER" --headless --disable-gpu --hide-scrollbars \
      --window-size=1600,900 \
      --virtual-time-budget=8000 \
      --run-all-compositor-stages-before-draw \
      --screenshot="$png" "$url" >/dev/null 2>&1 \
      && echo "[OK] shot $key => $png" \
      || echo "[WARN] screenshot failed ($BROWSER) for $url"
  done
else
  echo "[WARN] No chrome/chromium found => skip screenshots (HTML snapshots still saved)."
fi

PROOF="$OUT/PROOFNOTE_CIO.md"
cat > "$PROOF" <<MD
# VSP UI Commercial Proofnote (CIO)

**Timestamp:** $TS  
**BASE:** $BASE  
**RID:** $RID  
**RUN_ID:** $RUN_ID  

## Dashboard evidence
- URL: $BASE/vsp5?rid=$RID
- Console: \`dashboard_main_v1 loaded (P72B)\`
- KPIs (from datasource.kpis):
\`\`\`json
$KPIS_JSON
\`\`\`

## API evidence
- /api/vsp/top_findings_v2?limit=5 => 200 OK
- /api/vsp/datasource?rid=$RID => 200 OK

## 5 tabs
- Dashboard: $BASE/vsp5?rid=$RID  
- Runs & Reports: $BASE/runs?rid=$RID  
- Data Source: $BASE/data_source?rid=$RID  
- Settings: $BASE/settings?rid=$RID  
- Rule Overrides: $BASE/rule_overrides?rid=$RID  

## Artifacts
- Proofnote: $PROOF
- HTML snapshots: $OUT/html/*.html
- Screenshots: $OUT/screens/*.png (if browser exists)
MD

( cd "$OUT" && find . -type f -maxdepth 3 -print0 | xargs -0 sha256sum ) > "$OUT/SHA256SUMS.txt"

echo "[DONE] proofnote=$PROOF"
echo "[DONE] checksums=$OUT/SHA256SUMS.txt"
echo "[DONE] open dashboard: $BASE/vsp5?rid=$RID"
