#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56h4c_runtime_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need curl; need head; need wc; need sed

echo "== [P56H4C] Runtime console/pageerror gate (Playwright REAL) ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"

# quick HTTP sanity (retry)
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  ok=0
  for i in 1 2 3 4 5; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 4 "$BASE$p" || true)"
    echo "[HTTP] $p try#$i => $code" | tee -a "$EVID/summary.txt"
    [ "$code" = "200" ] && ok=1 && break
    sleep 1
  done
  [ "$ok" = "1" ] || { echo "[ERR] tab not 200: $p" | tee -a "$EVID/summary.txt"; exit 2; }
done

# ensure playwright resolvable from this repo
if ! node -e "require('playwright'); console.log('ok')" >/dev/null 2>&1; then
  echo "[ERR] playwright not installed in /ui. Run: bash bin/p56h4a_install_playwright_local_v1.sh" | tee -a "$EVID/summary.txt"
  exit 2
fi
echo "[OK] playwright available" | tee -a "$EVID/summary.txt"

cat > "$EVID/pw_gate.js" <<'NODE'
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const base = process.env.BASE;
const evid = process.env.EVID;

const tabs = [
  {name:'vsp5', path:'/vsp5'},
  {name:'runs', path:'/runs'},
  {name:'data_source', path:'/data_source'},
  {name:'settings', path:'/settings'},
  {name:'rule_overrides', path:'/rule_overrides'},
];

function jlog(file, obj){
  fs.appendFileSync(path.join(evid, file), JSON.stringify(obj) + "\n");
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();

  let consoleErrors = 0;
  let pageErrors = 0;
  let reqFails = 0;

  page.on('console', msg => {
    const o = {ts: Date.now(), type: msg.type(), text: msg.text()};
    jlog('console.jsonl', o);
    if (msg.type() === 'error') consoleErrors++;
  });
  page.on('pageerror', err => {
    const o = {ts: Date.now(), message: String(err && err.message || err), stack: String(err && err.stack || '')};
    jlog('pageerror.jsonl', o);
    pageErrors++;
  });
  page.on('requestfailed', req => {
    const o = {ts: Date.now(), url: req.url(), method: req.method(), failure: req.failure()};
    jlog('requestfailed.jsonl', o);
    reqFails++;
  });

  for (const t of tabs){
    const url = base + t.path;
    jlog('nav.jsonl', {ts: Date.now(), tab: t.name, url});
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    // avoid networkidle; give JS time to render
    await page.waitForTimeout(1500);

    // snapshot evidence per tab
    await page.screenshot({ path: path.join(evid, `shot_${t.name}.png`), fullPage: true });
    const html = await page.content();
    fs.writeFileSync(path.join(evid, `page_${t.name}.html`), html, 'utf-8');
  }

  await browser.close();

  const verdict = {
    ok: (consoleErrors===0 && pageErrors===0),
    ts: new Date().toISOString(),
    base,
    console_error_lines: consoleErrors,
    pageerror_lines: pageErrors,
    requestfailed_lines: reqFails
  };
  fs.writeFileSync(path.join(evid, 'verdict.json'), JSON.stringify(verdict, null, 2));
  console.log(JSON.stringify(verdict));
  process.exit(verdict.ok ? 0 : 3);
})();
NODE

echo "== [RUN] playwright gate ==" | tee -a "$EVID/summary.txt"
# critical: make playwright resolvable for pw_gate.js in out_ci by NODE_PATH
export BASE="$BASE"
export EVID="$(pwd)/$EVID"
export NODE_PATH="$(pwd)/node_modules"

set +e
node "$EVID/pw_gate.js" | tee -a "$EVID/summary.txt"
rc=$?
set -e

# summarize evidence
ce="$(grep -c '"type":"error"' "$EVID/console.jsonl" 2>/dev/null || echo 0)"
pe="$(wc -l < "$EVID/pageerror.jsonl" 2>/dev/null || echo 0)"
rf="$(wc -l < "$EVID/requestfailed.jsonl" 2>/dev/null || echo 0)"
echo "[INFO] console_error_lines=$ce pageerror_lines=$pe requestfailed_lines=$rf" | tee -a "$EVID/summary.txt"

if [ "$rc" -ne 0 ]; then
  echo "[FAIL] runtime has errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  echo "---- pageerror head ----" | tee -a "$EVID/summary.txt"
  head -n 30 "$EVID/pageerror.jsonl" 2>/dev/null | tee -a "$EVID/summary.txt" || true
  echo "---- console error head ----" | tee -a "$EVID/summary.txt"
  grep -n '"type":"error"' "$EVID/console.jsonl" 2>/dev/null | head -n 30 | tee -a "$EVID/summary.txt" || true
  exit 3
fi

echo "[PASS] no runtime console/page errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
