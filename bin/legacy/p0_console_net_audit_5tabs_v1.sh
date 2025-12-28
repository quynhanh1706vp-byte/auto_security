#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/CONSOLE_AUDIT_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need mkdir; need date

# prefer local playwright if exists
if [ -f package.json ]; then
  npm -s ls playwright >/dev/null 2>&1 || true
fi

node - <<'JS'
const fs = require('fs');
const path = require('path');

(async () => {
  let pw;
  try { pw = require('playwright'); }
  catch(e){
    console.error("[ERR] playwright not installed in this env.");
    console.error("Hint: npm i -D playwright && npx playwright install firefox");
    process.exit(2);
  }

  const BASE = process.env.BASE;
  const RID  = process.env.RID;
  const OUT  = process.env.OUT;

  const pages = [
    `/vsp5?rid=${encodeURIComponent(RID)}`,
    `/runs?rid=${encodeURIComponent(RID)}`,
    `/data_source?rid=${encodeURIComponent(RID)}`,
    `/settings?rid=${encodeURIComponent(RID)}`,
    `/rule_overrides?rid=${encodeURIComponent(RID)}`,
    `/c/dashboard?rid=${encodeURIComponent(RID)}`,
    `/c/runs?rid=${encodeURIComponent(RID)}`,
    `/c/data_source?rid=${encodeURIComponent(RID)}`,
    `/c/settings?rid=${encodeURIComponent(RID)}`,
    `/c/rule_overrides?rid=${encodeURIComponent(RID)}`
  ];

  const browser = await pw.firefox.launch({ headless: true });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const report = { base: BASE, rid: RID, ts: Date.now(), pages: [], totals: { console_errors:0, page_errors:0, http_4xx5xx:0 } };

  for (const p of pages) {
    const url = BASE + p;
    const page = await ctx.newPage();
    const entry = { path:p, url, console:[], pageErrors:[], badResponses:[], ok:false };

    page.on('console', msg => {
      const t = msg.type();
      if (t === 'error' || t === 'warning') entry.console.push({ type:t, text: msg.text().slice(0, 1000) });
    });
    page.on('pageerror', err => entry.pageErrors.push(String(err).slice(0, 1200)));
    page.on('response', resp => {
      const st = resp.status();
      if (st >= 400) entry.badResponses.push({ status: st, url: resp.url().slice(0, 500) });
    });

    try{
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
      await page.waitForTimeout(800);
      const html = await page.content();
      fs.writeFileSync(path.join(OUT, p.replace(/[\/\?\&\=\:]/g,'_') + ".html"), html, "utf-8");
      entry.ok = true;
    }catch(e){
      entry.console.push({ type:"error", text:"NAV_FAIL: " + String(e) });
    }finally{
      await page.close();
    }

    report.pages.push(entry);
    report.totals.console_errors += entry.console.filter(x=>x.type==='error').length;
    report.totals.page_errors += entry.pageErrors.length;
    report.totals.http_4xx5xx += entry.badResponses.length;
  }

  fs.writeFileSync(path.join(OUT,"audit.json"), JSON.stringify(report, null, 2));
  console.log("[OK] wrote", path.join(OUT,"audit.json"));
  console.log("[SUMMARY] console_errors=", report.totals.console_errors,
              "page_errors=", report.totals.page_errors,
              "http_4xx5xx=", report.totals.http_4xx5xx);
  await browser.close();

  // fail gate if any serious errors
  if (report.totals.page_errors > 0) process.exit(3);
  if (report.totals.http_4xx5xx > 0) process.exit(4);
  // console warnings allowed; errors not allowed
  if (report.totals.console_errors > 0) process.exit(5);
})();
JS
