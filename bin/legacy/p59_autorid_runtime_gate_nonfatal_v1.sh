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

log "== [P59 NONFATAL] AUTO-RID runtime gate =="
log "BASE=$BASE"
log "EVID=$EVID"

# --- 1) Determine RID (retry, timeout, nonfatal) ---
RID="${RID:-}"
if [ -z "${RID}" ]; then
  for i in 1 2 3 4 5; do
    RID="$(curl -fsS --connect-timeout 1 -m 6 "$BASE/api/vsp/top_findings_v2?limit=1" 2>/dev/null \
      | python3 - <<'PY' 2>/dev/null
import sys, json
try:
  j=json.load(sys.stdin)
  print(j.get("run_id") or "")
except Exception:
  print("")
PY
)"
    [ -n "${RID}" ] && break
    log "[WARN] RID fetch failed try#$i (will retry)"
    sleep 1
  done
fi

if [ -z "${RID}" ]; then
  log "[ERR] Cannot determine RID from API. (You can: RID=VSP_CI_xxx bash $0)"
  # nonfatal exit
  exit 0
fi
echo "$RID" > "$EVID/rid.txt" 2>/dev/null || true
log "[OK] RID=$RID"

# --- 2) Quick HTTP sanity (nonfatal) ---
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  code="$(curl -sS --connect-timeout 1 -m 4 -o /dev/null -w "%{http_code}" "$BASE$p?rid=$RID" 2>/dev/null || echo 000)"
  log "[HTTP] $p?rid=... => $code"
done

# --- 3) Playwright availability check (must resolve inside UI) ---
if ! node -e "require.resolve('playwright')" >/dev/null 2>&1; then
  log "[WARN] Playwright not available in UI node_modules -> skip runtime, only RID+HTTP done."
  log "[DONE] Evidence=$EVID"
  exit 0
fi
log "[OK] Playwright resolvable in UI"

# --- 4) Run headless runtime gate (no hang) ---
PW="$EVID/pw_gate_run.js"
cat > "$PW" <<'JS'
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const BASE = process.env.BASE;
const RID  = process.env.RID;
const EVID = process.env.EVID;

function p(f){ return path.join(EVID, f); }
function now(){ return new Date().toISOString(); }
function append(file, obj){ fs.appendFileSync(p(file), JSON.stringify(obj) + "\n"); }
function write(file, s){ fs.writeFileSync(p(file), s); }

async function safeShot(page, name){
  try{
    await page.screenshot({ path: p(name), fullPage: false, timeout: 5000, animations: 'disabled' });
  }catch(e){
    append('pw_internal.jsonl', {ts: now(), type:'screenshot_error', name, msg:String(e && e.message || e)});
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
  const context = await browser.newContext({
    viewport: { width: 1400, height: 900 },
    ignoreHTTPSErrors: true,
  });
  const page = await context.newPage();
  page.setDefaultTimeout(20000);
  page.setDefaultNavigationTimeout(25000);

  // Logs
  page.on('console', msg => {
    const rec = { ts: now(), type: msg.type(), text: msg.text(), location: msg.location() };
    if (msg.type() === 'error') append('console_error.jsonl', rec);
    else if (msg.type() === 'warning') append('console_warn.jsonl', rec);
  });
  page.on('pageerror', err => append('pageerror.jsonl', { ts: now(), name: err.name, message: err.message, stack: err.stack || null }));
  page.on('requestfailed', req => append('requestfailed.jsonl', { ts: now(), url: req.url(), failure: req.failure() }));

  for (const [pth, tag] of tabs){
    const url = `${BASE}${pth}?rid=${encodeURIComponent(RID)}`;
    append('nav.jsonl', { ts: now(), step:'goto', tag, url });
    try { await gotoFast(page, url); }
    catch(e){ append('pageerror.jsonl', { ts: now(), name:'GotoError', message:String(e && e.message || e), stack: e && e.stack || null }); }

    try { write(`page_${tag}.html`, await page.content()); } catch {}
    await safeShot(page, `page_${tag}.png`);
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

  // strict: console/page errors fail; requestfailed only reported
  const ok = (ce === 0 && pe === 0);

  const verdict = { ok, ts: now(), base: BASE, rid: RID, evidence_dir: EVID,
                    console_error_lines: ce, pageerror_lines: pe, requestfailed_lines: rf };
  write('verdict.json', JSON.stringify(verdict, null, 2));
  process.exit(ok ? 0 : 6);
})();
JS

# Run from UI so module resolution is correct
BASE="$BASE" RID="$RID" EVID="$EVID" node "$PW" >"$EVID/pw_gate.out" 2>"$EVID/pw_gate.err" || true

# Always show summary (nonfatal)
if [ -f "$EVID/verdict.json" ]; then
  log "[OK] verdict.json written"
  cat "$EVID/verdict.json" | tee -a "$EVID/summary.txt" >/dev/null
else
  log "[WARN] verdict.json missing (pw may not run). tail err:"
  tail -n 80 "$EVID/pw_gate.err" 2>/dev/null | tee -a "$EVID/summary.txt" >/dev/null || true
fi

log "[DONE] Evidence=$EVID"
exit 0
JS
