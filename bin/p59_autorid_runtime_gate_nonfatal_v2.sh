#!/usr/bin/env bash
set -u

UI="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$UI" 2>/dev/null || { echo "[ERR] missing UI dir"; exit 0; }

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="$UI/out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p59_autorid_${TS}"
mkdir -p "$EVID" 2>/dev/null || true

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$EVID/summary.txt" >/dev/null; }

log "== [P59 v2 NONFATAL] AUTO-RID + runtime gate =="
log "BASE=$BASE"
log "EVID=$EVID"

# --- RID probe helpers ---
probe(){
  local url="$1" out="$2"
  curl -fsS --connect-timeout 1 -m 6 "$url" -o "$out" 2>/dev/null || return 1
  return 0
}

extract_rid_py='
import sys,json
def pick(j):
  # common candidates
  for k in ("run_id","rid","latest_run_id","latestRid","latestRID"):
    v=j.get(k)
    if isinstance(v,str) and v.strip(): return v.strip()
  # nested candidates
  items=j.get("items")
  if isinstance(items,list) and items:
    it=items[0]
    if isinstance(it,dict):
      for k in ("run_id","rid","runId","RID"):
        v=it.get(k)
        if isinstance(v,str) and v.strip(): return v.strip()
  points=j.get("points")
  if isinstance(points,list) and points:
    pt=points[0]
    if isinstance(pt,dict):
      for k in ("run_id","rid","runId","RID"):
        v=pt.get(k)
        if isinstance(v,str) and v.strip(): return v.strip()
  data=j.get("data")
  if isinstance(data,dict):
    for k in ("run_id","rid"):
      v=data.get(k)
      if isinstance(v,str) and v.strip(): return v.strip()
  return ""
try:
  j=json.load(sys.stdin)
  print(pick(j))
except Exception:
  print("")
'

RID="${RID:-}"

if [ -z "${RID}" ]; then
  log "== [1] determine RID (multi-endpoint, retry) =="

  urls=(
    "$BASE/api/vsp/top_findings_v2?limit=1"
    "$BASE/api/vsp/top_findings_v1?limit=1"
    "$BASE/api/vsp/trend_v1"
    "$BASE/api/vsp/top_findings_v2?limit=5"
    "$BASE/api/vsp/top_findings_v1?limit=5"
  )

  for u in "${urls[@]}"; do
    fn="$EVID/rid_probe_$(echo "$u" | sed 's/[^a-zA-Z0-9]/_/g').json"
    for i in 1 2 3; do
      if probe "$u" "$fn"; then
        RID="$(python3 -c "$extract_rid_py" <"$fn" 2>/dev/null || true)"
        if [ -n "${RID}" ]; then
          log "[OK] RID=$RID (from: $u)"
          break 2
        else
          log "[WARN] no RID found in response: $u (saved $fn)"
        fi
      else
        log "[WARN] curl fail: $u try#$i"
      fi
      sleep 1
    done
  done
fi

if [ -z "${RID}" ]; then
  log "[ERR] Cannot determine RID from available endpoints."
  log "[HINT] Inspect saved probes in $EVID/rid_probe_*.json to see actual keys."
  log "[DONE] Evidence=$EVID (nonfatal)"
  exit 0
fi

echo "$RID" > "$EVID/rid.txt" 2>/dev/null || true
log "RID fixed => $RID"

# --- 2) quick HTTP sanity with RID ---
log "== [2] HTTP sanity (with rid) =="
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  code="$(curl -sS --connect-timeout 1 -m 5 -o /dev/null -w "%{http_code}" "$BASE$p?rid=$RID" 2>/dev/null || echo 000)"
  log "[HTTP] $p?rid=... => $code"
done

# --- 3) Playwright availability check (must resolve inside UI) ---
log "== [3] playwright check =="
if ! node -e "require.resolve('playwright')" >/dev/null 2>&1; then
  log "[WARN] Playwright not available in UI/node_modules -> skip runtime gate."
  log "[DONE] Evidence=$EVID (nonfatal)"
  exit 0
fi
log "[OK] Playwright resolvable in UI"

# --- 4) Runtime gate (always writes verdict.json, never hangs CLI) ---
PW="$EVID/pw_gate_run.js"
cat > "$PW" <<'JS'
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE;
const RID  = process.env.RID;
const EVID = process.env.EVID;

function p(f){ return path.join(EVID, f); }
function now(){ return new Date().toISOString(); }
function append(file, obj){ fs.appendFileSync(p(file), JSON.stringify(obj) + "\n"); }
function write(file, obj){ fs.writeFileSync(p(file), JSON.stringify(obj, null, 2)); }

(async () => {
  let chromium;
  try{
    ({ chromium } = require('playwright'));
  }catch(e){
    const verdict = { ok:false, ts: now(), base: BASE, rid: RID, evidence_dir: EVID,
      reason: "PLAYWRIGHT_MODULE_NOT_FOUND", message: String(e && e.message || e) };
    write('verdict.json', verdict);
    process.exit(6);
  }

  const tabs = [
    ['/vsp5', 'vsp5'],
    ['/runs', 'runs'],
    ['/data_source', 'data_source'],
    ['/settings', 'settings'],
    ['/rule_overrides', 'rule_overrides'],
  ];

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport:{width:1400,height:900}, ignoreHTTPSErrors:true });
  const page = await context.newPage();
  page.setDefaultTimeout(20000);
  page.setDefaultNavigationTimeout(25000);

  page.on('console', msg => {
    const rec = { ts: now(), type: msg.type(), text: msg.text(), location: msg.location() };
    if (msg.type() === 'error') append('console_error.jsonl', rec);
    else if (msg.type() === 'warning') append('console_warn.jsonl', rec);
  });
  page.on('pageerror', err => append('pageerror.jsonl', { ts: now(), name: err.name, message: err.message, stack: err.stack || null }));
  page.on('requestfailed', req => append('requestfailed.jsonl', { ts: now(), url: req.url(), failure: req.failure() }));

  async function safeShot(name){
    try{
      await page.screenshot({ path: p(name), timeout: 5000, fullPage: false, animations: 'disabled' });
    }catch(e){
      append('pw_internal.jsonl', { ts: now(), type:'screenshot_error', name, msg:String(e && e.message || e) });
    }
  }

  async function gotoFast(url){
    await page.goto(url, { waitUntil: 'commit', timeout: 25000 });
    await page.waitForTimeout(700);
  }

  for (const [pth, tag] of tabs){
    const url = `${BASE}${pth}?rid=${encodeURIComponent(RID)}`;
    append('nav.jsonl', { ts: now(), step:'goto', tag, url });
    try{
      await gotoFast(url);
      try{ fs.writeFileSync(p(`page_${tag}.html`), await page.content()); } catch {}
      await safeShot(`page_${tag}.png`);
    }catch(e){
      append('pageerror.jsonl', { ts: now(), name:'GotoError', message:String(e && e.message || e), stack: e && e.stack || null });
    }
  }

  await context.close();
  await browser.close();

  const count = (f) => {
    try {
      const s = fs.readFileSync(p(f),'utf-8').trim();
      if (!s) return 0;
      return s.split('\n').filter(Boolean).length;
    } catch { return 0; }
  };

  const ce = count('console_error.jsonl');
  const pe = count('pageerror.jsonl');
  const rf = count('requestfailed.jsonl');

  const ok = (ce === 0 && pe === 0);
  write('verdict.json', {
    ok, ts: now(), base: BASE, rid: RID, evidence_dir: EVID,
    console_error_lines: ce, pageerror_lines: pe, requestfailed_lines: rf
  });
  process.exit(ok ? 0 : 6);
})();
JS

BASE="$BASE" RID="$RID" EVID="$EVID" node "$PW" >"$EVID/pw_gate.out" 2>"$EVID/pw_gate.err" || true

if [ -f "$EVID/verdict.json" ]; then
  log "== [4] verdict =="
  cat "$EVID/verdict.json" | tee -a "$EVID/summary.txt" >/dev/null
else
  log "[ERR] verdict.json missing (unexpected). tail err:"
  tail -n 80 "$EVID/pw_gate.err" 2>/dev/null | tee -a "$EVID/summary.txt" >/dev/null || true
fi

log "[DONE] Evidence=$EVID"
exit 0
