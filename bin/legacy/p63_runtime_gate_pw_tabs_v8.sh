#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$UI"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="$UI/out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p63_runtime_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need curl; need python3; need wc; need head

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$EVID/summary.txt" >/dev/null; }

log "== [P63 v8] Runtime gate (PW, clean, evidence, retry) =="
log "UI=$UI"
log "BASE=$BASE"
log "EVID=$EVID"

# 1) warm tabs (retry + longer timeout)
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  ok=0
  for i in 1 2 3 4 5; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 10 "$BASE$p" || true)"
    log "[HTTP] $p try#$i => $code"
    [ "$code" = "200" ] && ok=1 && break
    sleep 0.5
  done
  [ "$ok" = "1" ] || { log "[ERR] tab not 200: $p"; exit 2; }
done

# 2) RID probe (never crash on empty)
RID_JSON="$EVID/rid_probe_top_findings.json"
curl -sS --connect-timeout 2 --max-time 10 --retry 3 --retry-all-errors \
  "$BASE/api/vsp/top_findings_v2?limit=1" -o "$RID_JSON" || true

RID="$(
python3 - "$RID_JSON" <<'PY'
import sys, json
p=sys.argv[1]
try:
  raw=open(p,"rb").read()
  if not raw.strip(): 
    print(""); raise SystemExit(0)
  j=json.loads(raw.decode("utf-8","replace"))
except Exception:
  print(""); raise SystemExit(0)

rid = (j.get("rid") or j.get("run_id") or "")
if not rid and isinstance(j.get("items"), list) and j["items"]:
  rid = j["items"][0].get("rid") or j["items"][0].get("run_id") or ""
print(rid or "")
PY
)"
log "RID=$RID"
[ -n "$RID" ] || { log "[ERR] RID empty (see $RID_JSON)"; exit 2; }

# 3) quick check playwright resolvable from UI
export NODE_PATH="$UI/node_modules"
if node -e "require('playwright'); console.log('OK_PLAYWRIGHT')" >"$EVID/pw_require.out" 2>"$EVID/pw_require.err"; then
  log "[OK] playwright require works"
else
  log "[FAIL] playwright require failed (see pw_require.err)"
  python3 - <<PY >"$EVID/verdict.json"
import json, datetime
print(json.dumps({
  "ok": False,
  "ts": datetime.datetime.utcnow().isoformat()+"Z",
  "base": "$BASE",
  "rid": "$RID",
  "evidence_dir": "$EVID",
  "reason": "PLAYWRIGHT_MODULE_NOT_FOUND"
}, indent=2))
PY
  cat "$EVID/verdict.json"
  exit 0
fi

# 4) write pw gate
cat > "$EVID/pw_gate.js" <<'JS'
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const BASE = process.env.VSP_UI_BASE;
const RID  = process.env.VSP_RID;
const EVID = process.env.VSP_EVID;

function jlog(file, obj){
  fs.appendFileSync(path.join(EVID, file), JSON.stringify(obj) + "\n");
}
function writeJson(file, obj){
  fs.writeFileSync(path.join(EVID, file), JSON.stringify(obj, null, 2));
}
const sleep = ms => new Promise(r=>setTimeout(r, ms));

(async () => {
  const started = new Date().toISOString();
  let consoleErr=0, pageErr=0, reqFail=0;

  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();

  page.on('console', msg => {
    const type = msg.type();
    const rec = { ts: new Date().toISOString(), type, text: msg.text(), location: msg.location() };
    if (type === 'error') { consoleErr++; jlog('console_error.jsonl', rec); }
    else if (type === 'warning') jlog('console_warn.jsonl', rec);
    else jlog('console_log.jsonl', rec);
  });

  page.on('pageerror', err => {
    pageErr++;
    jlog('pageerror.jsonl', { ts: new Date().toISOString(), message: String(err) });
  });

  page.on('requestfailed', req => {
    const f = req.failure() || {};
    const errText = String(f.errorText || '');
    if (errText.includes('net::ERR_ABORTED')) return; // ignore common aborts
    reqFail++;
    jlog('requestfailed.jsonl', { ts: new Date().toISOString(), url: req.url(), errorText: errText, method: req.method(), resourceType: req.resourceType() });
  });

  const paths = [
    `/vsp5?rid=${encodeURIComponent(RID)}`,
    `/runs?rid=${encodeURIComponent(RID)}`,
    `/data_source?rid=${encodeURIComponent(RID)}`,
    `/settings?rid=${encodeURIComponent(RID)}`,
    `/rule_overrides?rid=${encodeURIComponent(RID)}`
  ];

  for (let i=0;i<paths.length;i++){
    const p = paths[i];
    const url = BASE + p;
    const tag = `tab${i+1}`;
    try{
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
      await sleep(1200);
      fs.writeFileSync(path.join(EVID, `page_${tag}.html`), await page.content());

      // screenshot: never hang
      const shot = page.screenshot({ path: path.join(EVID, `page_${tag}.png`), timeout: 12000 });
      await Promise.race([
        shot,
        new Promise((_,rej)=>setTimeout(()=>rej(new Error('screenshot_timeout')), 15000))
      ]).catch(e => jlog('screenshot_warn.jsonl', { ts: new Date().toISOString(), tab: p, warn: String(e) }));
    }catch(e){
      pageErr++;
      jlog('pageerror.jsonl', { ts: new Date().toISOString(), tab: p, message: String(e) });
    }
  }

  await browser.close();

  const ok = (consoleErr===0 && pageErr===0 && reqFail===0);
  writeJson('verdict.json', {
    ok, ts: new Date().toISOString(), started,
    base: BASE, rid: RID, evidence_dir: EVID,
    console_error_lines: consoleErr,
    pageerror_lines: pageErr,
    requestfailed_lines: reqFail
  });
  process.exit(ok ? 0 : 2);
})();
JS

export VSP_UI_BASE="$BASE"
export VSP_RID="$RID"
export VSP_EVID="$EVID"

log "== [RUN] playwright =="
node "$EVID/pw_gate.js" >"$EVID/pw_gate.out" 2>"$EVID/pw_gate.err" || true

# 5) summarize + always show verdict
if [ -f "$EVID/verdict.json" ]; then
  log "[OK] verdict.json written"
else
  log "[FAIL] verdict.json missing (see pw_gate.err)"
fi

ce=$(wc -l <"$EVID/console_error.jsonl" 2>/dev/null || echo 0)
pe=$(wc -l <"$EVID/pageerror.jsonl" 2>/dev/null || echo 0)
rf=$(wc -l <"$EVID/requestfailed.jsonl" 2>/dev/null || echo 0)
log "[INFO] console_error_lines=$ce pageerror_lines=$pe requestfailed_lines=$rf"
log "[DONE] Evidence=$EVID"

cat "$EVID/verdict.json" 2>/dev/null || true
