#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56h4_runtime_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need curl; need head; need wc

echo "== [P56H4] Headless runtime console gate (Playwright) ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"

# quick health (do not trust feelings)
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  code="$(curl -sS --connect-timeout 2 -m 5 -o /dev/null -w "%{http_code}" "$BASE$p" || true)"
  echo "[HTTP] $p => $code" | tee -a "$EVID/summary.txt"
done

# require playwright
if node -e "require('playwright'); console.log('ok')" >/dev/null 2>&1; then
  echo "[OK] playwright is available (node require)." | tee -a "$EVID/summary.txt"
else
  echo "[ERR] Playwright not installed for Node." | tee -a "$EVID/summary.txt"
  echo "      Install (local) example:" | tee -a "$EVID/summary.txt"
  echo "      cd /home/test/Data/SECURITY_BUNDLE/ui && npm i -D playwright && npx playwright install chromium" | tee -a "$EVID/summary.txt"
  echo "[DONE] Evidence=$EVID" | tee -a "$EVID/summary.txt"
  exit 2
fi

cat > "$EVID/pw_gate.js" <<'JS'
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const EVID = process.env.EVID;
const BASE = process.env.BASE;

const tabs = [
  { name: "vsp5", p: "/vsp5" },
  { name: "runs", p: "/runs" },
  { name: "data_source", p: "/data_source" },
  { name: "settings", p: "/settings" },
  { name: "rule_overrides", p: "/rule_overrides" },
];

function jline(fp, obj){
  fs.appendFileSync(fp, JSON.stringify(obj) + "\n");
}

(async () => {
  const consoleFp = path.join(EVID, "console.jsonl");
  const pageerrFp = path.join(EVID, "pageerror.jsonl");
  const metaFp = path.join(EVID, "meta.json");

  fs.writeFileSync(consoleFp, "");
  fs.writeFileSync(pageerrFp, "");

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await context.newPage();

  let consoleErr = 0;
  let pageErr = 0;

  page.on("console", (msg) => {
    const t = msg.type(); // log, info, warning, error, debug
    const rec = { ts: new Date().toISOString(), type: t, text: msg.text() };
    jline(consoleFp, rec);
    if (t === "error") consoleErr++;
  });

  page.on("pageerror", (err) => {
    const rec = { ts: new Date().toISOString(), name: err.name, message: err.message, stack: String(err.stack || "") };
    jline(pageerrFp, rec);
    pageErr++;
  });

  const results = [];
  for (const t of tabs){
    const url = BASE + t.p;
    const start = Date.now();
    let ok = true, status = null;

    try{
      const resp = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 25000 });
      status = resp ? resp.status() : null;

      // small settle (avoid networkidle)
      await page.waitForTimeout(800);

      const html = await page.content();
      fs.writeFileSync(path.join(EVID, `${t.name}.html`), html, "utf-8");
      await page.screenshot({ path: path.join(EVID, `${t.name}.png`), fullPage: true });

      // minimal sanity: top nav tabs exist by text
      const navOk = await page.evaluate(() => {
        const txt = (document.body && document.body.innerText) ? document.body.innerText : "";
        const need = ["Dashboard","Runs","Data Source","Settings","Rule Overrides"];
        let hit = 0;
        for (const n of need) if (txt.includes(n)) hit++;
        return { hit, need: need.length };
      });

      results.push({ tab: t.name, url, status, ms: Date.now() - start, nav_hit: navOk.hit, nav_need: navOk.need });
    }catch(e){
      ok = false;
      results.push({ tab: t.name, url, status, ms: Date.now() - start, error: String(e && e.message ? e.message : e) });
    }
  }

  await browser.close();

  const meta = {
    ok: (consoleErr === 0 && pageErr === 0),
    ts: new Date().toISOString(),
    base: BASE,
    console_error_count: consoleErr,
    pageerror_count: pageErr,
    tabs: results,
  };
  fs.writeFileSync(metaFp, JSON.stringify(meta, null, 2), "utf-8");

  // print verdict to stdout
  console.log(JSON.stringify(meta, null, 2));
  process.exit(meta.ok ? 0 : 1);
})();
JS

echo "== [RUN] playwright headless ==" | tee -a "$EVID/summary.txt"
BASE="$BASE" EVID="$EVID" node "$EVID/pw_gate.js" | tee "$EVID/verdict.json" || true

ce="$(grep -c '"type":"error"' "$EVID/console.jsonl" 2>/dev/null || echo 0)"
pe="$(wc -l < "$EVID/pageerror.jsonl" 2>/dev/null || echo 0)"
echo "[INFO] console_error=$ce pageerror=$pe" | tee -a "$EVID/summary.txt"

if [ "$ce" -gt 0 ] || [ "$pe" -gt 0 ]; then
  echo "[FAIL] runtime console/page errors detected. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  echo "  - see: $EVID/console.jsonl , $EVID/pageerror.jsonl , $EVID/*.png , $EVID/*.html" | tee -a "$EVID/summary.txt"
  exit 1
fi

echo "[PASS] no runtime console/page errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
