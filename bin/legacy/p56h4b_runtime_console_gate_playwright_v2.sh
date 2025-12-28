#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56h4b_runtime_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need curl; need head; need wc

echo "== [P56H4B] Runtime console/pageerror gate (Playwright, REAL) ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"

# quick http check
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 "$BASE$p" || true)"
  echo "[HTTP] $p => $code" | tee -a "$EVID/summary.txt"
  [ "$code" = "200" ] || { echo "[ERR] tab not 200: $p"; exit 3; }
done

# ensure playwright available (local install)
node -e "require('playwright'); console.log('ok')" >/dev/null 2>&1 || {
  echo "[ERR] playwright not available in $(pwd). Install first:" | tee -a "$EVID/summary.txt"
  echo "      npm i -D playwright && npx playwright install chromium" | tee -a "$EVID/summary.txt"
  exit 4
}

cat > "$EVID/pw_gate.js" <<'JS'
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const base = process.env.BASE || 'http://127.0.0.1:8910';
const evid = process.env.EVID || '.';
const pages = ['/vsp5','/runs','/data_source','/settings','/rule_overrides'];

function jline(file, obj){
  fs.appendFileSync(path.join(evid,file), JSON.stringify(obj) + "\n");
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const page = await context.newPage();

  page.on('console', msg => {
    jline('console.jsonl', { ts: new Date().toISOString(), type: msg.type(), text: msg.text() });
  });
  page.on('pageerror', err => {
    jline('pageerror.jsonl', { ts: new Date().toISOString(), name: err.name, message: err.message, stack: String(err.stack||'') });
  });
  page.on('requestfailed', req => {
    jline('requestfailed.jsonl', { ts: new Date().toISOString(), url: req.url(), failure: (req.failure()||{}).errorText });
  });

  let ok = true;
  for (const p of pages){
    const url = base + p;
    try{
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(800); // allow scripts run a bit
      await page.screenshot({ path: path.join(evid, p.replace(/\W+/g,'_') + '.png'), fullPage: true });
    }catch(e){
      ok = false;
      jline('navfail.jsonl', { ts: new Date().toISOString(), url, error: String(e) });
    }
  }

  await browser.close();

  const consoleTxt = fs.existsSync(path.join(evid,'console.jsonl')) ? fs.readFileSync(path.join(evid,'console.jsonl'),'utf8') : '';
  const pageerrTxt  = fs.existsSync(path.join(evid,'pageerror.jsonl')) ? fs.readFileSync(path.join(evid,'pageerror.jsonl'),'utf8') : '';

  const hasConsoleError = /"type":"error"/i.test(consoleTxt) || /"type":"assert"/i.test(consoleTxt);
  const hasPageError = pageerrTxt.trim().length > 0;

  const verdict = {
    ok: ok && !hasConsoleError && !hasPageError,
    ts: new Date().toISOString(),
    base,
    checks: { nav_ok: ok, console_error: hasConsoleError, pageerror: hasPageError },
  };
  fs.writeFileSync(path.join(evid,'verdict.json'), JSON.stringify(verdict,null,2));
  process.exit(verdict.ok ? 0 : 2);
})();
JS

echo "== [RUN] playwright gate ==" | tee -a "$EVID/summary.txt"
BASE="$BASE" EVID="$EVID" node "$EVID/pw_gate.js" || true

# summarize
ce="$(grep -c '"type":"error"' "$EVID/console.jsonl" 2>/dev/null || echo 0)"
pe="$(wc -l < "$EVID/pageerror.jsonl" 2>/dev/null || echo 0)"
echo "[INFO] console_error_lines=$ce pageerror_lines=$pe" | tee -a "$EVID/summary.txt"

if [ -f "$EVID/verdict.json" ] && grep -q '"ok": true' "$EVID/verdict.json"; then
  echo "[PASS] runtime clean. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  exit 0
fi

echo "[FAIL] runtime has errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
exit 2
