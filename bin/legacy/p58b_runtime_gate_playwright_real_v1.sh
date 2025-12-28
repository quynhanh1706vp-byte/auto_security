#!/usr/bin/env bash
set -euo pipefail
UI="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$UI"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="$UI/out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p58b_runtime_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need curl; need head; need wc

echo "== [P58B] Runtime console/pageerror gate (Playwright REAL) ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE UI=$UI EVID=$EVID" | tee -a "$EVID/summary.txt"

# quick reachability with retry
check_tab(){
  local p="$1"
  local ok=0
  for i in 1 2 3; do
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 4 "$BASE$p" || true)"
    echo "[HTTP] $p try#$i => $code" | tee -a "$EVID/summary.txt"
    [ "$code" = "200" ] && ok=1 && break
    sleep 0.8
  done
  [ "$ok" = "1" ] || { echo "[ERR] tab not 200: $p" | tee -a "$EVID/summary.txt"; exit 2; }
}
for p in /vsp5 /runs /data_source /settings /rule_overrides; do check_tab "$p"; done

# ensure playwright is resolvable from THIS folder
if ! node -e "require('playwright'); console.log('playwright_ok')" >/dev/null 2>&1; then
  echo "[ERR] Playwright not resolvable from $UI." | tee -a "$EVID/summary.txt"
  echo "      Fix: cd $UI && npm i -D playwright && npx playwright install chromium" | tee -a "$EVID/summary.txt"
  exit 2
fi
echo "[OK] playwright require works in UI folder" | tee -a "$EVID/summary.txt"

cat > "$EVID/pw_gate.js" <<'JS'
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const BASE = process.env.BASE;
const EVID = process.env.EVID;

const tabs = [
  {name:"vsp5", path:"/vsp5"},
  {name:"runs", path:"/runs"},
  {name:"data_source", path:"/data_source"},
  {name:"settings", path:"/settings"},
  {name:"rule_overrides", path:"/rule_overrides"},
];

function w(p, s){ fs.appendFileSync(p, s + "\n"); }

(async () => {
  const consolePath = path.join(EVID, "console.jsonl");
  const pageerrPath = path.join(EVID, "pageerror.jsonl");
  const reqfailPath = path.join(EVID, "requestfailed.jsonl");

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }});
  const page = await context.newPage();

  page.on("console", msg => {
    const o = {
      ts: new Date().toISOString(),
      type: msg.type(),
      text: msg.text(),
      location: msg.location(),
    };
    w(consolePath, JSON.stringify(o));
  });

  page.on("pageerror", err => {
    const o = { ts: new Date().toISOString(), message: String(err?.message || err), stack: String(err?.stack || "") };
    w(pageerrPath, JSON.stringify(o));
  });

  page.on("requestfailed", req => {
    const f = req.failure();
    const o = { ts: new Date().toISOString(), url: req.url(), method: req.method(), failure: f ? f.errorText : "" };
    w(reqfailPath, JSON.stringify(o));
  });

  for (const t of tabs){
    const url = BASE + t.path;
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 20000 });
    await page.waitForTimeout(1800);

    const png = path.join(EVID, `page_${t.name}.png`);
    await page.screenshot({ path: png, fullPage: true });

    const html = await page.content();
    fs.writeFileSync(path.join(EVID, `page_${t.name}.html`), html, "utf-8");
  }

  await browser.close();

  const readLines = (p) => fs.existsSync(p) ? fs.readFileSync(p,"utf-8").trim().split("\n").filter(Boolean) : [];
  const consoleErr = readLines(consolePath).filter(l => {
    try{ const o=JSON.parse(l); return o.type==="error"; }catch(e){ return false; }
  }).length;
  const pageErr = readLines(pageerrPath).length;

  const verdict = {
    ok: (consoleErr===0 && pageErr===0),
    ts: new Date().toISOString(),
    console_error: consoleErr,
    pageerror: pageErr,
    evidence_dir: EVID,
    base: BASE
  };
  fs.writeFileSync(path.join(EVID, "verdict.json"), JSON.stringify(verdict, null, 2));

  if (!verdict.ok){
    process.exitCode = 2;
  }
})();
JS

echo "== [RUN] playwright ==" | tee -a "$EVID/summary.txt"
BASE="$BASE" EVID="$EVID" node "$EVID/pw_gate.js" || true

ce=$(grep -c '"type":"error"' "$EVID/console.jsonl" 2>/dev/null || echo 0)
pe=$(wc -l < "$EVID/pageerror.jsonl" 2>/dev/null || echo 0)
rf=$(wc -l < "$EVID/requestfailed.jsonl" 2>/dev/null || echo 0)

echo "[INFO] console_error_lines=$ce pageerror_lines=$pe requestfailed_lines=$rf" | tee -a "$EVID/summary.txt"

if [ "$pe" -ne 0 ] || [ "$ce" -ne 0 ]; then
  echo "[FAIL] runtime has errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  exit 2
fi

echo "[PASS] runtime clean. Evidence=$EVID" | tee -a "$EVID/summary.txt"
