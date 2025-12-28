#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p57c_runtime_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need curl; need head; need wc

echo "== [P57C] Runtime gate (Playwright REAL) ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE EVID=$EVID" | tee -a "$EVID/summary.txt"

# quick HTTP sanity (retry)
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  ok=0
  for i in 1 2 3 4 5; do
    code="$(curl -fsS -o /dev/null -w "%{http_code}" --max-time 4 "$BASE$p" || true)"
    echo "[HTTP] $p try#$i => $code" | tee -a "$EVID/summary.txt"
    [ "$code" = "200" ] && ok=1 && break
    sleep 1
  done
  [ "$ok" = "1" ] || { echo "[ERR] tab not 200: $p" | tee -a "$EVID/summary.txt"; exit 2; }
done

# require playwright must work (in UI folder)
node -e "require('playwright'); console.log('playwright_ok')" | tee -a "$EVID/summary.txt"

cat > "$EVID/pw_gate.js" <<'JS'
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const BASE = process.env.VSP_UI_BASE || 'http://127.0.0.1:8910';
const EVID = process.env.EVID || process.cwd();

const tabs = [
  ['/vsp5','dash'],
  ['/runs','runs'],
  ['/data_source','data_source'],
  ['/settings','settings'],
  ['/rule_overrides','rule_overrides'],
];

function writeJSONL(file, obj){
  fs.appendFileSync(file, JSON.stringify(obj) + "\n");
}

(async () => {
  const consoleFile = path.join(EVID, 'console.jsonl');
  const pageerrFile = path.join(EVID, 'pageerror.jsonl');

  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1366, height: 768 } });

  for (const [p, tag] of tabs){
    const page = await ctx.newPage();

    page.on('console', (msg) => {
      const type = msg.type();
      writeJSONL(consoleFile, { ts: Date.now(), tag, type, text: msg.text() });
    });
    page.on('pageerror', (err) => {
      writeJSONL(pageerrFile, { ts: Date.now(), tag, name: err?.name, message: String(err?.message||err), stack: String(err?.stack||"") });
    });

    const url = BASE + p;
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 25000 });
    await page.waitForTimeout(800); // let scripts run
    await page.screenshot({ path: path.join(EVID, `page_${tag}.png`), fullPage: true });
    await page.close();
  }

  await ctx.close();
  await browser.close();

  // verdict
  const consoleText = fs.existsSync(consoleFile) ? fs.readFileSync(consoleFile,'utf8') : '';
  const pageerrText  = fs.existsSync(pageerrFile) ? fs.readFileSync(pageerrFile,'utf8') : '';

  const consoleErr = consoleText.split("\n").filter(Boolean).filter(l => {
    try { const j=JSON.parse(l); return j.type === 'error'; } catch { return false; }
  }).length;

  const pageErr = pageerrText.split("\n").filter(Boolean).length;

  fs.writeFileSync(path.join(EVID,'verdict.json'), JSON.stringify({
    ok: (consoleErr === 0 && pageErr === 0),
    console_error_lines: consoleErr,
    pageerror_lines: pageErr,
    base: BASE,
    evidence_dir: EVID,
    ts: new Date().toISOString()
  }, null, 2));
})();
JS

echo "== [RUN] playwright ==" | tee -a "$EVID/summary.txt"
EVID="$EVID" VSP_UI_BASE="$BASE" node "$EVID/pw_gate.js" || true

echo "== [RESULT] ==" | tee -a "$EVID/summary.txt"
cat "$EVID/verdict.json" | tee -a "$EVID/summary.txt"

echo "[FILES]" | tee -a "$EVID/summary.txt"
ls -1 "$EVID" | head -n 40 | tee -a "$EVID/summary.txt"

ok="$(python3 - <<PY
import json
p="$EVID/verdict.json"
j=json.load(open(p))
print("1" if j.get("ok") else "0")
PY
)"
if [ "$ok" = "1" ]; then
  echo "[PASS] runtime clean. Evidence=$EVID" | tee -a "$EVID/summary.txt"
else
  echo "[FAIL] runtime has errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  echo "--- console errors (first 50) ---" | tee -a "$EVID/summary.txt"
  grep -n '"type":"error"' "$EVID/console.jsonl" 2>/dev/null | head -n 50 | tee -a "$EVID/summary.txt" || true
  echo "--- pageerrors (first 20) ---" | tee -a "$EVID/summary.txt"
  head -n 20 "$EVID/pageerror.jsonl" 2>/dev/null | tee -a "$EVID/summary.txt" || true
  exit 1
fi
