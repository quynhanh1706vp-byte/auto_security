#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56h2_ui_audit_${TS}"
mkdir -p "$EVID"

echo "== [P56H2] HEADLESS UI AUDIT ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"

# quick reachability (no feel)
paths=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${paths[@]}"; do
  code="$(curl -fsS --connect-timeout 2 --max-time 4 -o /dev/null -w '%{http_code}' "$BASE$p" || echo 000)"
  echo "[HTTP] $p => $code" | tee -a "$EVID/summary.txt"
done

# Prefer Playwright if available (best: catch console/page runtime errors)
if node -e "require('playwright')" >/dev/null 2>&1; then
  echo "[OK] playwright available -> run headless runtime audit" | tee -a "$EVID/summary.txt"
  cat > "$EVID/run.js" <<'JS'
const fs = require("fs");
const path = require("path");

const BASE = process.env.VSP_UI_BASE || "http://127.0.0.1:8910";
const OUT  = process.env.EVID_DIR || ".";
const urls = [
  {name:"vsp5", path:"/vsp5"},
  {name:"runs", path:"/runs"},
  {name:"data_source", path:"/data_source"},
  {name:"settings", path:"/settings"},
  {name:"rule_overrides", path:"/rule_overrides"},
];

function jlog(file, obj){
  fs.appendFileSync(file, JSON.stringify(obj) + "\n");
}

(async () => {
  const { firefox } = require("playwright");
  const browser = await firefox.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });

  const consoleFile = path.join(OUT, "console.jsonl");
  const reqFailFile = path.join(OUT, "request_failed.jsonl");
  const pageErrFile = path.join(OUT, "pageerror.jsonl");
  const verdictFile = path.join(OUT, "verdict.json");

  let hardFail = false;
  let warnings = [];

  for (const u of urls){
    const page = await context.newPage();

    page.on("console", (msg) => {
      const rec = {ts: new Date().toISOString(), tab:u.name, type: msg.type(), text: msg.text()};
      jlog(consoleFile, rec);
      if (["error"].includes(msg.type())) hardFail = true;
      if (/Uncaught|SyntaxError|ReferenceError|TypeError/i.test(msg.text())) hardFail = true;
    });
    page.on("pageerror", (err) => {
      jlog(pageErrFile, {ts:new Date().toISOString(), tab:u.name, error: String(err)});
      hardFail = true;
    });
    page.on("requestfailed", (req) => {
      jlog(reqFailFile, {ts:new Date().toISOString(), tab:u.name, url:req.url(), failure:req.failure()});
      // request failed can be warning unless it is main document
    });

    const full = BASE + u.path;
    let resp = null;
    try{
      resp = await page.goto(full, { waitUntil: "domcontentloaded", timeout: 20000 });
    }catch(e){
      hardFail = true;
      jlog(pageErrFile, {ts:new Date().toISOString(), tab:u.name, error: "GOTO_FAIL: " + String(e)});
    }

    const status = resp ? resp.status() : 0;
    const mainOk = (status >= 200 && status < 400);
    if (!mainOk){
      hardFail = true;
      jlog(pageErrFile, {ts:new Date().toISOString(), tab:u.name, error: "MAIN_HTTP_STATUS=" + status});
    }

    // minimal UI sanity: must have top nav tabs text somewhere
    const content = await page.content().catch(()=> "");
    fs.writeFileSync(path.join(OUT, `${u.name}.html`), content);

    const shot = path.join(OUT, `${u.name}.png`);
    await page.screenshot({ path: shot, fullPage: true }).catch(()=>{});

    const hasNav = await page.evaluate(() => {
      const t = document.body ? document.body.innerText : "";
      return /Dashboard|Runs\s*&\s*Reports|Data\s*Source|Settings|Rule\s*Overrides/.test(t);
    }).catch(()=>false);

    if (!hasNav){
      warnings.push(`missing_nav_text:${u.name}`);
      // if nav missing and body is mostly empty => hard fail
      const bodyLen = await page.evaluate(()=> (document.body && document.body.innerText ? document.body.innerText.trim().length : 0)).catch(()=>0);
      if (bodyLen < 30) hardFail = true;
    }

    const hasDegraded = await page.evaluate(() => {
      return !!document.querySelector(".toast, .vsp-toast, [data-toast], .degraded");
    }).catch(()=>false);
    if (hasDegraded) warnings.push(`degraded_toast_seen:${u.name}`);

    await page.close();
  }

  await browser.close();

  const verdict = {
    ok: !hardFail,
    ts: new Date().toISOString(),
    base: BASE,
    warnings,
    evidence_dir: OUT
  };
  fs.writeFileSync(verdictFile, JSON.stringify(verdict, null, 2));

  console.log(JSON.stringify(verdict, null, 2));
  process.exit(verdict.ok ? 0 : 2);
})();
JS

  export EVID_DIR="$EVID"
  set +e
  node "$EVID/run.js" | tee "$EVID/verdict_stdout.txt"
  rc=$?
  set -e

  echo "[DONE] evidence=$EVID rc=$rc" | tee -a "$EVID/summary.txt"
  echo "[HINT] open screenshots in $EVID/*.png (no UI open needed)" | tee -a "$EVID/summary.txt"
  exit $rc
else
  echo "[WARN] playwright NOT installed -> fallback (static load + loaded-js syntax only)" | tee -a "$EVID/summary.txt"
  # fallback: extract loaded js from HTML, then node --check those files if present locally
  > "$EVID/loaded_js.txt"
  for p in "${paths[@]}"; do
    html="$EVID/$(echo "$p" | tr '/?' '__').html"
    curl -fsS --connect-timeout 2 --max-time 6 "$BASE$p" -o "$html" || true
    grep -oE '/static/js/[^"]+\.js(\?[^"]*)?' "$html" | sed -E 's/\?.*$//' >> "$EVID/loaded_js.txt" || true
  done
  sort -u "$EVID/loaded_js.txt" -o "$EVID/loaded_js.txt"
  echo "[OK] loaded_js_count=$(wc -l < "$EVID/loaded_js.txt")" | tee -a "$EVID/summary.txt"

  bad=0
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    f="${url#/}"
    if [ -f "$f" ]; then
      if ! node --check "$f" >/dev/null 2>&1; then
        echo "[FAIL] syntax: $f" | tee -a "$EVID/summary.txt"
        bad=1
      fi
    else
      echo "[WARN] missing local file: $f" | tee -a "$EVID/summary.txt"
    fi
  done < "$EVID/loaded_js.txt"

  if [ "$bad" = "0" ]; then
    echo "[PASS] loaded-js syntax OK (fallback). For runtime console errors, install playwright." | tee -a "$EVID/summary.txt"
    exit 0
  else
    echo "[FAIL] loaded-js syntax FAIL (fallback)." | tee -a "$EVID/summary.txt"
    exit 2
  fi
fi
