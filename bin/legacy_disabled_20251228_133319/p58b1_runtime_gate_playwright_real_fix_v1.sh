#!/usr/bin/env bash
set -euo pipefail
UI="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$UI"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="$UI/out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p58b1_runtime_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need curl; need head; need wc

echo "== [P58B1] Runtime gate (Playwright REAL, fail-closed) ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE UI=$UI EVID=$EVID" | tee -a "$EVID/summary.txt"

# reachability with retry
check_tab(){
  local p="$1"
  for i in 1 2 3; do
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 4 "$BASE$p" || true)"
    echo "[HTTP] $p try#$i => $code" | tee -a "$EVID/summary.txt"
    [ "$code" = "200" ] && return 0
    sleep 0.8
  done
  echo "[ERR] tab not 200: $p" | tee -a "$EVID/summary.txt"
  exit 2
}
for p in /vsp5 /runs /data_source /settings /rule_overrides; do check_tab "$p"; done

# hard check: playwright must resolve from UI's node_modules
if ! node -e "require('playwright'); console.log('pw_ok')" >/dev/null 2>&1; then
  echo "[ERR] Playwright not resolvable in $UI." | tee -a "$EVID/summary.txt"
  echo "      Fix: cd $UI && npm i -D playwright && npx playwright install chromium" | tee -a "$EVID/summary.txt"
  exit 2
fi
echo "[OK] playwright is installed in UI folder" | tee -a "$EVID/summary.txt"

cat > "$EVID/pw_gate.js" <<'JS'
const fs = require("fs");
const path = require("path");
const { createRequire } = require("module");

const UI = process.env.UI;
const BASE = process.env.BASE;
const EVID = process.env.EVID;

// Resolve playwright from UI/node_modules regardless of where this script lives
const reqUI = createRequire(path.join(UI, "package.json"));
const { chromium } = reqUI("playwright");

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
    const o = { ts:new Date().toISOString(), type:msg.type(), text:msg.text(), location:msg.location() };
    w(consolePath, JSON.stringify(o));
  });

  page.on("pageerror", err => {
    const o = { ts:new Date().toISOString(), message:String(err?.message || err), stack:String(err?.stack || "") };
    w(pageerrPath, JSON.stringify(o));
  });

  page.on("requestfailed", req => {
    const f = req.failure();
    const o = { ts:new Date().toISOString(), url:req.url(), method:req.method(), failure:f ? f.errorText : "" };
    w(reqfailPath, JSON.stringify(o));
  });

  for (const t of tabs){
    const url = BASE + t.path;
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 25000 });
    await page.waitForTimeout(2000);

    await page.screenshot({ path: path.join(EVID, `page_${t.name}.png`), fullPage: true });
    fs.writeFileSync(path.join(EVID, `page_${t.name}.html`), await page.content(), "utf-8");
  }

  await browser.close();

  const readLines = (p) => fs.existsSync(p) ? fs.readFileSync(p,"utf-8").trim().split("\n").filter(Boolean) : [];
  const consoleErr = readLines(consolePath).filter(l => { try{ return JSON.parse(l).type==="error"; }catch(e){ return false; } }).length;
  const pageErr = readLines(pageerrPath).length;

  const verdict = { ok:(consoleErr===0 && pageErr===0), ts:new Date().toISOString(), console_error:consoleErr, pageerror:pageErr, evidence_dir:EVID, base:BASE };
  fs.writeFileSync(path.join(EVID, "verdict.json"), JSON.stringify(verdict, null, 2));

  if (!verdict.ok) process.exit(2);
})();
JS

echo "== [RUN] playwright ==" | tee -a "$EVID/summary.txt"
set +e
UI="$UI" BASE="$BASE" EVID="$EVID" node "$EVID/pw_gate.js"
rc=$?
set -e

# fail-closed if node failed or verdict missing
if [ "$rc" -ne 0 ]; then
  echo "[ERR] playwright run failed rc=$rc. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  exit 2
fi
[ -f "$EVID/verdict.json" ] || { echo "[ERR] missing verdict.json (fail-closed)"; exit 2; }

ce=$(grep -c '"type":"error"' "$EVID/console.jsonl" 2>/dev/null || echo 0)
pe=$(wc -l < "$EVID/pageerror.jsonl" 2>/dev/null || echo 0)
rf=$(wc -l < "$EVID/requestfailed.jsonl" 2>/dev/null || echo 0)
echo "[INFO] console_error_lines=$ce pageerror_lines=$pe requestfailed_lines=$rf" | tee -a "$EVID/summary.txt"

if [ "$pe" -ne 0 ] || [ "$ce" -ne 0 ]; then
  echo "[FAIL] runtime has errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  exit 2
fi

echo "[PASS] runtime clean. Evidence=$EVID" | tee -a "$EVID/summary.txt"
