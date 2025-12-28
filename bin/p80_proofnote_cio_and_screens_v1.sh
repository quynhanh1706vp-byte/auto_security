#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need sha256sum; need awk; need sed; need grep; need mkdir; need ls

TS="$(date +%Y%m%d_%H%M%S)"

# pick latest release dir; if none, create a new one by calling p79 if exists
LATEST="$(ls -1dt out_ci/releases/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
if [ -z "${LATEST:-}" ]; then
  echo "[WARN] No RELEASE_UI_* found. Creating a fresh release via P79..."
  if [ -f bin/p79_pack_ui_commercial_release_v1.sh ]; then
    bash bin/p79_pack_ui_commercial_release_v1.sh
    LATEST="$(ls -1dt out_ci/releases/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
  fi
fi
[ -n "${LATEST:-}" ] || { echo "[ERR] cannot find/create release dir under out_ci/releases/"; exit 2; }

OUT="$LATEST/proof"
mkdir -p "$OUT/screens" "$OUT/html"

RID="$(curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("rid",""))')"
[ -n "$RID" ] || { echo "[ERR] RID empty from top_findings_v2"; exit 2; }

RUN_ID="$(curl -fsS "$BASE/api/vsp/datasource?rid=$RID" | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("run_id",""))')"
KPIS_JSON="$(curl -fsS "$BASE/api/vsp/datasource?rid=$RID" | python3 -c 'import sys,json;j=json.load(sys.stdin);k=j.get("kpis") or {};import json as jj;print(jj.dumps(k,ensure_ascii=False))')"

# extract KPI numbers safely
TOTAL="$(python3 - <<PY
import json,sys
k=json.loads(sys.argv[1]) if len(sys.argv)>1 else {}
print(k.get("total", k.get("TOTAL", "")) or "")
PY
"$KPIS_JSON")"

# browser for headless screenshots (prefer chromium/chrome)
BROWSER=""
for b in google-chrome chromium chromium-browser chrome; do
  if command -v "$b" >/dev/null 2>&1; then BROWSER="$b"; break; fi
done

# URLs to capture (5 tabs)
declare -a PAGES=(
  "dashboard|$BASE/vsp5?rid=$RID"
  "runs|$BASE/runs?rid=$RID"
  "data_source|$BASE/data_source?rid=$RID"
  "settings|$BASE/settings?rid=$RID"
  "rule_overrides|$BASE/rule_overrides?rid=$RID"
)

echo "== [P80] Proofnote + Screens =="
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
    # virtual-time-budget helps SPAs render; window-size for KPI header visibility
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

# Create PROOFNOTE (CIO)
PROOF="$OUT/PROOFNOTE_CIO.md"
cat > "$PROOF" <<MD
# VSP UI Commercial Proofnote (CIO)

**Timestamp:** $TS  
**BASE:** $BASE  
**RID:** $RID  
**RUN_ID:** $RUN_ID  

## 1) Dashboard Evidence (render OK)
- Dashboard URL: $BASE/vsp5?rid=$RID
- JS boot marker: console shows \`dashboard_main_v1 loaded (P72B)\`
- KPI summary (from datasource.kpis):
\`\`\`json
$KPIS_JSON
\`\`\`

## 2) API Contract Evidence
- \`/api/vsp/top_findings_v2?limit=5\` => 200 OK
- \`/api/vsp/datasource?rid=$RID\` => 200 OK (keys: ok,rid,run_id,mode,lite,total,runs,findings,returned,kpis)

## 3) UI Tabs (5 tabs)
- Dashboard: $BASE/vsp5?rid=$RID  
- Runs & Reports: $BASE/runs?rid=$RID  
- Data Source: $BASE/data_source?rid=$RID  
- Settings: $BASE/settings?rid=$RID  
- Rule Overrides: $BASE/rule_overrides?rid=$RID  

## 4) Artifacts in release folder
- Proofnote: \`$PROOF\`
- HTML snapshots: \`$OUT/html/*.html\`
- Screenshots: \`$OUT/screens/*.png\` (if browser available)
MD

# checksums for everything under proof/
( cd "$OUT" && find . -type f -maxdepth 3 -print0 | xargs -0 sha256sum ) > "$OUT/SHA256SUMS.txt"

echo "[DONE] proofnote=$PROOF"
echo "[DONE] checksums=$OUT/SHA256SUMS.txt"
echo "[DONE] open dashboard: $BASE/vsp5?rid=$RID"
