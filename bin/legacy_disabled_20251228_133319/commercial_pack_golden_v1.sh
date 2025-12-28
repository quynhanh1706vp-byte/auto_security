#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="COMMERCIAL_${RID}_${TS}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need mkdir; need cp; need tar; need curl; need python3; need bash; need head; need sed; need sha256sum; need ls

mkdir -p "$OUT"

echo "== [1] selfcheck =="
bash bin/commercial_selfcheck_v1.sh "$RID" | tee "$OUT/SELFHECK.txt"

echo "== [2] audit =="
bash bin/commercial_ui_audit_v1.sh | tee "$OUT/COMMERCIAL_UI_AUDIT.txt"

echo "== [3] specs =="
cat > "$OUT/COMMERCIAL_SPECS.md" <<'EOF'
# VSP Commercial UI — Design & Contract Specs (CIO-level)

## 1) Design philosophy
### 1.1 CIO-level visibility
Dashboard is landing page:
- Total findings, severity distribution (6 buckets), trend, top risk, top module, top CWE.
- No config, no debug/dev content.
- Less text, more insights; clear “what to do next”.

### 1.2 BE → API → FE mapping (stateless)
Golden rule: FE never reads internal files/paths.
Each tab uses its own API contract; state comes from BE JSON:
- Dashboard: dashboard_v3 (prefer single-contract)
- Runs: runs_v3 + report links
- Releases: release_latest + release_download/audit
- Data Source: paging/filter/search API (no run_file_allow path)
- Settings/Rule Overrides: dedicated APIs

### 1.3 Component-based UI
Each component:
- 1 HTML section with stable id
- 1 API provides data
- 1 JS module: loadXxx() / renderXxx(data)

Core components:
KPI cards, donut, trendline, tool bars, top tables, filter/search.

### 1.4 Dark enterprise theme
Font: Inter (fallback system-ui)
Palette: #020617/#0f172a background, #111827 panels, borders #1f2937/#334155
Text: #e5e7eb primary, #9ca3af secondary
Severity colors:
CRITICAL #f97373; HIGH #fb923c; MEDIUM #facc15; LOW #22c55e; INFO #38bdf8; TRACE #a855f7
EOF

echo "== [4] attach docs =="
cp -f README_COMMERCIAL.md RUNBOOK.md "$OUT/" 2>/dev/null || true
cp -f COMMERCIAL_GATE.txt "$OUT/" 2>/dev/null || true

echo "== [5] attach release artifacts =="
curl -fSL "$BASE/api/vsp/release_download?rid=$RID" -o "$OUT/VSP_RELEASE_${RID}.zip"
curl -fsS "$BASE/api/vsp/release_audit?rid=$RID" -o "$OUT/release_audit_${RID}.json"
sha256sum "$OUT/VSP_RELEASE_${RID}.zip" | tee "$OUT/sha256.txt"
ls -lh "$OUT/VSP_RELEASE_${RID}.zip" | tee "$OUT/size.txt"

echo "== [6] pack =="
tar -czf "${OUT}.tgz" "$OUT"
echo "[OK] packed: ${OUT}.tgz"
ls -lah "$OUT" "${OUT}.tgz"
