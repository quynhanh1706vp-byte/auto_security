#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56h4_runtime_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need curl; need head; need wc

echo "== [P56H4 v2] Headless runtime console gate (Playwright) ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"

# hard precheck HTTP
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  code="$(curl -fsS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE$p" || true)"
  echo "[HTTP] $p => $code" | tee -a "$EVID/summary.txt"
  [ "$code" = "200" ] || { echo "[FAIL] $p not 200"; exit 3; }
done

# playwright availability MUST be resolved from UI node_modules
if ! node -e "require('playwright'); console.log('playwright_ok')" >/dev/null 2>&1; then
  echo "[ERR] Playwright not installed in UI folder." | tee -a "$EVID/summary.txt"
  echo "      Run: cd /home/test/Data/SECURITY_BUNDLE/ui && npm i -D playwright && npx playwright install chromium" | tee -a "$EVID/summary.txt"
  exit 4
fi
echo "[OK] playwright is available (resolved from UI node_modules)" | tee -a "$EVID/summary.txt"

cat > "$EVID/pw_gate.js" <<'JS'
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const base = process.env.BASE || 'http://127.0.0.1:8910';
const evid = process.env.EVID || process.cwd();

function jline(file, obj){
  fs.appendFileSync(path.join(evid, file), JSON.stringify(obj) + "\n");
}

(async () => {
  const pages = [
    {name:'vsp5', path:'/vsp5'},
    {name:'runs', path:'/runs'},
    {name:'data_source', path:'/data_source'},
    {name:'settings', path:'/settings'},
    {name:'rule_overrides', path:'/rule_overrides'},
  ];

  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();

  page.on('console', msg => {
    const type = msg.type();
    jline('console.jsonl', { ts: new Date().toISOString(), type, text: msg.text() });
  });

  page.on('pageerror', err => {
    jline('pageerror.jsonl', { ts: new Date().toISOString(), message: String(err && err.message || err), stack: String(err && err.stack || '') });
  });

  page.setDefaultTimeout(45000);

  for (const it of pages){
    const url = base + it.path;
    try{
      await page.goto(url, { waitUntil: 'domcontentloaded' });
      await page.waitForTimeout(800); // small settle, avoid networkidle
      const html = await page.content();
      fs.writeFileSync(path.join(evid, `${it.name}.html`), html);
      await page.screenshot({ path: path.join(evid, `${it.name}.png`), fullPage: true });
      jline('nav.jsonl', { ts: new Date().toISOString(), ok:true, name: it.name, url });
    }catch(e){
      jline('nav.jsonl', { ts: new Date().toISOString(), ok:false, name: it.name, url, err: String(e && e.message || e) });
    }
  }

  await browser.close();
})();
JS

echo "== [RUN] playwright headless (module path forced to UI node_modules) ==" | tee -a "$EVID/summary.txt"

# IMPORTANT: run node from UI context so require('playwright') works everywhere
# also export NODE_PATH explicitly for safety
export BASE EVID
export NODE_PATH="/home/test/Data/SECURITY_BUNDLE/ui/node_modules"

set +e
node "$EVID/pw_gate.js"
rc=$?
set -e

echo "[INFO] pw_rc=$rc" | tee -a "$EVID/summary.txt"

# gate: must have artifacts; must not have runtime errors (tunable)
touch "$EVID/console.jsonl" "$EVID/pageerror.jsonl"
ce="$(grep -c '"type":"error"' "$EVID/console.jsonl" 2>/dev/null || echo 0)"
pe="$(wc -l < "$EVID/pageerror.jsonl" 2>/dev/null || echo 0)"
echo "[INFO] console_error=$ce pageerror=$pe" | tee -a "$EVID/summary.txt"

# verdict
python3 - <<PY
import json, os, datetime
evid=os.environ.get("EVID","")
rc=int(os.environ.get("RC","0")) if os.environ.get("RC") else None
PY

# strict: fail if node failed OR missing screenshots OR errors > 0
missing_png=0
for n in vsp5 runs data_source settings rule_overrides; do
  [ -f "$EVID/$n.png" ] || missing_png=$((missing_png+1))
done

ok=true
reason=[]
if [ "$rc" -ne 0 ]; then ok=false; reason+=("playwright_rc_nonzero"); fi
if [ "$missing_png" -ne 0 ]; then ok=false; reason+=("missing_screenshots"); fi
if [ "$ce" -ne 0 ]; then ok=false; reason+=("console_error"); fi
if [ "$pe" -ne 0 ]; then ok=false; reason+=("pageerror"); fi

python3 - <<PY
import json, os, datetime
evid=os.environ["EVID"]
base=os.environ["BASE"]
ce=int(os.environ.get("CE","0")) if os.environ.get("CE") else 0
pe=int(os.environ.get("PE","0")) if os.environ.get("PE") else 0
rc=int(os.environ.get("PWRC","0")) if os.environ.get("PWRC") else 0
missing=int(os.environ.get("MISS","0")) if os.environ.get("MISS") else 0
ok=os.environ.get("OK","true")=="true"
reasons=os.environ.get("REASONS","").split(",") if os.environ.get("REASONS") else []
j={
  "ok": ok,
  "ts": datetime.datetime.now().isoformat(),
  "base": base,
  "evidence_dir": os.path.abspath(evid),
  "playwright_rc": rc,
  "console_error": ce,
  "pageerror": pe,
  "missing_screenshots": missing,
  "reasons": [r for r in reasons if r],
}
open(os.path.join(evid,"verdict.json"),"w").write(json.dumps(j,indent=2,ensure_ascii=False))
print(json.dumps(j,indent=2,ensure_ascii=False))
PY

