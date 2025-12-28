#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$UI"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="$UI/out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p59_runtime_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need curl; need head; need awk; need sed

echo "== [P59 v2] Runtime gate (Playwright) ==" | tee "$EVID/summary.txt"
echo "[INFO] UI=$UI" | tee -a "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"
echo "[INFO] EVID=$EVID" | tee -a "$EVID/summary.txt"

# A) HTTP 200 retry
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  ok=0
  for i in 1 2 3 4 5; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 6 --connect-timeout 2 "$BASE$p" || true)"
    echo "[HTTP] $p try#$i => $code" | tee -a "$EVID/summary.txt"
    if [ "$code" = "200" ]; then ok=1; break; fi
    sleep 1
  done
  if [ "$ok" != "1" ]; then
    echo "[FAIL] tab not 200: $p" | tee -a "$EVID/summary.txt"
    exit 1
  fi
done

# B) Ensure Playwright resolvable from UI
# (1) normal require
if node -e "require('playwright'); console.log('pw_ok')" >/dev/null 2>&1; then
  echo "[OK] playwright resolvable (normal require) in UI" | tee -a "$EVID/summary.txt"
else
  echo "[WARN] normal require failed; try NODE_PATH fallback" | tee -a "$EVID/summary.txt"
  if NODE_PATH="$UI/node_modules" node -e "require('playwright'); console.log('pw_ok')" >/dev/null 2>&1; then
    echo "[OK] playwright resolvable via NODE_PATH=$UI/node_modules" | tee -a "$EVID/summary.txt"
  else
    echo "[ERR] Playwright not installed/visible for Node in UI." | tee -a "$EVID/summary.txt"
    echo "      Fix:" | tee -a "$EVID/summary.txt"
    echo "      cd $UI && npm i -D playwright && npx playwright install chromium" | tee -a "$EVID/summary.txt"
    exit 2
  fi
fi

# C) Write pw_gate.js INSIDE EVID (absolute)
cat > "$EVID/pw_gate.js" <<'JS'
const fs = require('fs');
const path = require('path');

function ensureFile(fp){ if(!fs.existsSync(fp)) fs.writeFileSync(fp, "", "utf-8"); }
function jline(fp, obj){ fs.appendFileSync(fp, JSON.stringify(obj) + "\n"); }

process.on("unhandledRejection", (e) => {
  try { console.error("unhandledRejection:", e); } catch(_){}
});
process.on("uncaughtException", (e) => {
  try { console.error("uncaughtException:", e); } catch(_){}
  process.exit(1);
});

(async () => {
  const evid = process.env.EVID;
  const base = process.env.BASE;
  const nodePath = process.env.NODE_PATH || "";

  // require playwright (respect NODE_PATH)
  const { chromium } = require('playwright');

  const pages = [
    {name:"vsp5", path:"/vsp5"},
    {name:"runs", path:"/runs"},
    {name:"data_source", path:"/data_source"},
    {name:"settings", path:"/settings"},
    {name:"rule_overrides", path:"/rule_overrides"},
  ];

  const consoleFp = path.join(evid, "console.jsonl");
  const pageerrFp = path.join(evid, "pageerror.jsonl");
  const reqfailFp = path.join(evid, "requestfailed.jsonl");
  ensureFile(consoleFp); ensureFile(pageerrFp); ensureFile(reqfailFp);

  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 820 } });
  const page = await ctx.newPage();

  page.on('console', msg => {
    const type = msg.type();
    jline(consoleFp, { ts: new Date().toISOString(), type, text: msg.text(), url: page.url() });
  });
  page.on('pageerror', err => {
    jline(pageerrFp, { ts: new Date().toISOString(), name: err.name, message: err.message, url: page.url() });
  });
  page.on('requestfailed', req => {
    const f = req.failure();
    jline(reqfailFp, { ts: new Date().toISOString(), url: req.url(), method: req.method(), failure: f ? f.errorText : "unknown" });
  });

  async function gotoRetry(url, tries=3){
    let lastErr = null;
    for(let i=1;i<=tries;i++){
      try{
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
        await page.waitForTimeout(600);
        return;
      }catch(e){
        lastErr = e;
        jline(pageerrFp, { ts: new Date().toISOString(), name:"GotoError", message:String(e), url });
        await page.waitForTimeout(800);
      }
    }
    throw lastErr;
  }

  for (const it of pages) {
    const url = base + it.path;
    await gotoRetry(url, 3);
    const html = await page.content();
    fs.writeFileSync(path.join(evid, `page_${it.name}.html`), html, 'utf-8');
    await page.screenshot({ path: path.join(evid, `page_${it.name}.png`), fullPage: true });
  }

  await browser.close();

  const consoleErr = fs.readFileSync(consoleFp,'utf-8')
    .split("\n").filter(l => l.includes('"type":"error"')).length;

  const pageErr = fs.readFileSync(pageerrFp,'utf-8')
    .trim().split("\n").filter(Boolean).length;

  const reqFail = fs.readFileSync(reqfailFp,'utf-8')
    .trim().split("\n").filter(Boolean).length;

  const verdict = {
    ok: (consoleErr === 0 && pageErr === 0),
    ts: new Date().toISOString(),
    base,
    evidence_dir: evid,
    node_path: nodePath,
    counts: { console_error: consoleErr, pageerror: pageErr, requestfailed: reqFail }
  };
  fs.writeFileSync(path.join(evid, "verdict.json"), JSON.stringify(verdict, null, 2));

  if (!verdict.ok) process.exit(1);
})();
JS

echo "== [RUN] playwright ==" | tee -a "$EVID/summary.txt"

# IMPORTANT: force NODE_PATH so pw_gate.js can always resolve playwright
NODE_PATH="$UI/node_modules" BASE="$BASE" EVID="$EVID" node "$EVID/pw_gate.js" || {
  echo "[FAIL] runtime has errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  # show quick heads
  echo "--- pageerror head ---" | tee -a "$EVID/summary.txt"
  head -n 30 "$EVID/pageerror.jsonl" 2>/dev/null | tee -a "$EVID/summary.txt" || true
  echo "--- console error head ---" | tee -a "$EVID/summary.txt"
  grep -n '"type":"error"' "$EVID/console.jsonl" 2>/dev/null | head -n 30 | tee -a "$EVID/summary.txt" || true
  exit 1
}

echo "[PASS] runtime clean. Evidence=$EVID" | tee -a "$EVID/summary.txt"
cat "$EVID/verdict.json"
