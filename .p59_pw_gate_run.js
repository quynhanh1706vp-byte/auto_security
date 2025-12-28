const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const BASE = process.env.BASE || 'http://127.0.0.1:8910';
const EVID = process.env.EVID || process.cwd();

function pjoin(f){ return path.join(EVID, f); }
function now(){ return new Date().toISOString(); }
function jline(file, obj){ fs.appendFileSync(pjoin(file), JSON.stringify(obj) + "\n"); }

async function safeShot(page, file){
  try{
    await page.screenshot({ path: pjoin(file), fullPage: false, timeout: 5000 });
  }catch(e){
    jline('pw_internal.jsonl', {ts: now(), type:'screenshot_error', file, msg: String(e?.message || e)});
  }
}

async function gotoFast(page, url){
  await page.goto(url, { waitUntil: 'commit', timeout: 25000 });
  await page.waitForTimeout(800);
}

(async () => {
  const tabs = [
    ['/vsp5', 'vsp5'],
    ['/runs', 'runs'],
    ['/data_source', 'data_source'],
    ['/settings', 'settings'],
    ['/rule_overrides', 'rule_overrides'],
  ];

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 }, ignoreHTTPSErrors: true });
  const page = await context.newPage();
  page.setDefaultTimeout(20000);
  page.setDefaultNavigationTimeout(25000);

  page.on('console', (msg) => {
    const type = msg.type();
    if (type === 'error' || type === 'warning'){
      jline('console.jsonl', { ts: now(), type, text: msg.text(), location: msg.location() });
    }
  });
  page.on('pageerror', (err) => jline('pageerror.jsonl', { ts: now(), name: err.name, message: err.message, stack: err.stack || null }));
  page.on('requestfailed', (req) => jline('requestfailed.jsonl', { ts: now(), url: req.url(), failure: req.failure() }));

  for (const [p, tag] of tabs){
    const url = BASE + p;
    jline('nav.jsonl', { ts: now(), step: 'goto', url, tag });

    try{ await gotoFast(page, url); }
    catch(e){ jline('pageerror.jsonl', { ts: now(), name:'GotoError', message:String(e?.message || e), stack:e?.stack || null }); }

    try{
      const html = await page.content();
      fs.writeFileSync(pjoin(`page_${tag}.html`), html);
    }catch(e){
      jline('pw_internal.jsonl', {ts: now(), type:'content_error', tag, msg:String(e?.message || e)});
    }

    await safeShot(page, `page_${tag}.png`);
  }

  await context.close();
  await browser.close();

  const countLines = (f) => {
    try {
      const s = fs.readFileSync(pjoin(f),'utf-8').trim();
      if (!s) return 0;
      return s.split('\n').filter(Boolean).length;
    } catch { return 0; }
  };

  const consoleErr = countLines('console.jsonl');
  const pageErr = countLines('pageerror.jsonl');
  const reqFail = countLines('requestfailed.jsonl');
  const ok = (consoleErr === 0 && pageErr === 0);

  const verdict = { ok, ts: now(), base: BASE, evidence_dir: EVID, console_error_lines: consoleErr, pageerror_lines: pageErr, requestfailed_lines: reqFail };
  fs.writeFileSync(pjoin('verdict.json'), JSON.stringify(verdict, null, 2));
  process.exit(ok ? 0 : 6);
})();
