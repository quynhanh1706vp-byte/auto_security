#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need date

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/vsp_ui_smoke_${TS}"
mkdir -p "$OUT"

JS="$OUT/smoke.js"
cat > "$JS" <<'JS'
const fs = require("fs");
const path = require("path");

function now(){ return new Date().toISOString(); }

async function main(){
  const { chromium } = require("playwright");
  const base = process.env.BASE || "http://127.0.0.1:8910";
  const out = process.env.OUT || "/tmp/vsp_ui_smoke";
  const pages = ["/vsp5","/runs","/data_source","/settings","/rule_overrides"];

  const logPath = path.join(out, "smoke_log.jsonl");
  const log = (obj)=>fs.appendFileSync(logPath, JSON.stringify({t:now(),...obj})+"\n");

  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();

  page.on("console", (m)=>{
    const type = m.type();
    if (type === "error" || type === "warning") {
      log({kind:"console", type, text:m.text()});
    }
  });
  page.on("pageerror", (err)=> log({kind:"pageerror", message:String(err)}));
  page.on("requestfailed", (req)=> log({kind:"requestfailed", url:req.url(), failure:req.failure() && req.failure().errorText}));

  for (const p of pages){
    const url = base + p;
    log({kind:"nav_start", url});
    const resp = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45000 });
    log({kind:"nav_done", url, status: resp ? resp.status() : null});

    // lightweight “main element” waits
    if (p === "/vsp5") await page.waitForSelector("#vsp-dashboard-main", { timeout: 20000 });

    // screenshot
    const shot = path.join(out, `shot_${p.replaceAll("/","_")}.png`);
    await page.screenshot({ path: shot, fullPage: true });
    log({kind:"screenshot", file: shot});
  }

  await ctx.close();
  await browser.close();

  // summarize
  const lines = fs.readFileSync(logPath,"utf-8").trim().split("\n").filter(Boolean).map(JSON.parse);
  const errs = lines.filter(x=>x.kind==="pageerror" || (x.kind==="console" && x.type==="error") || x.kind==="requestfailed");
  fs.writeFileSync(path.join(out,"summary.json"), JSON.stringify({
    base, out,
    total_events: lines.length,
    issues: errs.slice(0,200),
    issue_count: errs.length,
  }, null, 2));

  console.log("[OK] out=", out);
  console.log("[OK] issue_count=", errs.length);
  if (errs.length > 0) process.exitCode = 2;
}

main().catch(e=>{ console.error(e); process.exit(3); });
JS

export BASE="$BASE"
export OUT="$OUT"
node "$JS" || true

echo
echo "== RESULT =="
echo "OUT=$OUT"
echo "cat $OUT/summary.json | head -c 2000; echo"
