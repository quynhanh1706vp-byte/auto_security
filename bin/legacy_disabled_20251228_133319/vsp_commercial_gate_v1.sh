#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8910}"
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
FAIL=0

need() { command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing cmd: $1"; FAIL=1; }; }

need curl
need jq
need python3

echo "== [1] health/version =="
curl -fsS "$BASE/healthz" | jq -e '.ok==true' >/dev/null || { echo "[FAIL] /healthz"; FAIL=1; }
curl -fsS "$BASE/api/vsp/version" | jq -e '.ok==true and (.info.git_hash|length>0)' >/dev/null || { echo "[FAIL] /api/vsp/version"; FAIL=1; }

echo "== [2] contract: dashboard_v3 =="
curl -fsS "$BASE/api/vsp/dashboard_v3" | jq -e '.ok==true and (.by_severity!=null)' >/dev/null \
  || { echo "[FAIL] /api/vsp/dashboard_v3 missing by_severity"; FAIL=1; }

echo "== [3] contract: runs index resolved =="
curl -fsS "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=5&hide_empty=0&filter=1" | jq -e '.items!=null' >/dev/null \
  || { echo "[FAIL] runs_index_v3_fs_resolved"; FAIL=1; }

echo "== [4] contract: datasource/settings/rule_overrides =="
curl -fsS "$BASE/api/vsp/datasource_v2?limit=10" | jq -e '.ok==true' >/dev/null \
  || { echo "[FAIL] datasource_v2"; FAIL=1; }
curl -fsS "$BASE/api/vsp/settings_v1" | jq -e '.ok==true' >/dev/null \
  || { echo "[FAIL] settings_v1"; FAIL=1; }
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | jq -e '.ok==true' >/dev/null \
  || { echo "[FAIL] rule_overrides_v1"; FAIL=1; }

echo "== [5] latest status endpoint =="
curl -fsS "$BASE/api/vsp/run_status_latest" | jq -e '.ok==true' >/dev/null \
  || { echo "[FAIL] run_status_latest"; FAIL=1; }

echo "== [6] template sanity checks =="
TPL="$ROOT/templates/vsp_dashboard_2025.html"
if [ -f "$TPL" ]; then
  # duplicate script src
  dup_src="$(grep -oE '<script[^>]+src="[^"]+"' "$TPL" | sed -E 's/.*src="([^"]+)".*/\1/' | sort | uniq -d | head -n 1 || true)"
  [ -z "$dup_src" ] || { echo "[FAIL] duplicate <script src>: $dup_src"; FAIL=1; }

  # duplicate id (thô, best effort)
  dup_id="$(grep -oE 'id="[^"]+"' "$TPL" | sed -E 's/id="([^"]+)"/\1/' | sort | uniq -d | head -n 1 || true)"
  [ -z "$dup_id" ] || { echo "[WARN] duplicate id in template (check): $dup_id"; }
else
  echo "[WARN] template not found: $TPL"
fi

echo "== [7] optional UI smoke (Playwright) =="
if command -v node >/dev/null 2>&1 && node -e 'require("playwright")' >/dev/null 2>&1; then
  node - <<'JS'
const { firefox } = require('playwright');
(async () => {
  const base = process.env.BASE || 'http://127.0.0.1:8910';
  const browser = await firefox.launch({ headless: true });
  const page = await browser.newPage();
  const bad = [];
  page.on('console', m => {
    const t = m.type();
    const s = m.text();
    if (t === 'error') bad.push('[error] ' + s);
    // warning đỏ kiểu race condition bạn muốn triệt:
    if (t === 'warning' && /No charts engine|will retry/i.test(s)) bad.push('[warn] ' + s);
  });
  await page.goto(base + '/#dashboard', { waitUntil: 'domcontentloaded' });
  const tabs = ['dashboard','runs','datasource','settings','rule-overrides'];
  for (const t of tabs) {
    await page.goto(base + '/#' + t, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(300);
  }
  await browser.close();
  if (bad.length) {
    console.error('UI_SMOKE_FAIL:\n' + bad.join('\n'));
    process.exit(2);
  }
  console.log('UI_SMOKE_OK');
})();
JS
else
  echo "[SKIP] playwright not available -> skip UI smoke"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "[GATE] FAIL"
  exit 1
fi
echo "[GATE] PASS"
