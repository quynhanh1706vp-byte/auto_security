#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$UI"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="$UI/out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p60_runtime_${TS}"
mkdir -p "$EVID"

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$EVID/summary.txt" >/dev/null; }

log "== [P60 v3 CLEAN] Runtime gate (Playwright, strict evidence) =="
log "UI=$UI"
log "BASE=$BASE"
log "EVID=$EVID"

# --- RID robust (top_findings_v2 returns 'rid') ---
RID="${RID:-}"
if [ -z "${RID:-}" ]; then
  for i in 1 2 3 4 5; do
    RID="$(
      curl -fsS --connect-timeout 1 -m 6 "$BASE/api/vsp/top_findings_v2?limit=1" \
      | python3 - <<'PY2'
import sys, json
try:
  j=json.load(sys.stdin)
  rid=(j.get("rid") or j.get("run_id") or "").strip()
  if not rid and isinstance(j.get("items"), list) and j["items"]:
    rid=(j["items"][0].get("rid") or j["items"][0].get("run_id") or "").strip()
  print(rid)
except Exception:
  print("")
PY2
    )" || true
    [ -n "${RID:-}" ] && break
    sleep 1
  done
fi
log "RID=${RID:-}"
[ -n "${RID:-}" ] || { log "[ERR] cannot get RID"; echo "EVID=$EVID"; exit 2; }

# --- ensure tabs 200 ---
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  code="000"
  for t in 1 2 3; do
    code="$(curl -sS --connect-timeout 1 -m 6 -o /dev/null -w "%{http_code}" "$BASE$p?rid=$RID" 2>/dev/null || echo 000)"
    [ "$code" != "000" ] && break
    sleep 1
  done
  log "[HTTP] $p => $code"
  [ "$code" = "200" ] || { log "[ERR] tab not 200: $p"; echo "EVID=$EVID"; exit 2; }
done

# --- playwright must be resolvable from UI folder ---
node -e "require.resolve('playwright', {paths:[process.cwd()]});" >/dev/null 2>&1 || {
  log "[ERR] playwright not resolvable from UI. Fix: cd $UI && npm i -D playwright && npx playwright install chromium"
  python3 - <<PY3 > "$EVID/verdict.json"
import json,datetime
print(json.dumps({"ok":False,"ts":datetime.datetime.utcnow().isoformat()+"Z","base":"$BASE","rid":"$RID","evidence_dir":"$EVID","reason":"PLAYWRIGHT_NOT_FOUND"},indent=2))
PY3
  echo "EVID=$EVID"; cat "$EVID/verdict.json"; exit 6
}
log "[OK] playwright resolvable in UI"

PW="$EVID/pw_gate.js"
cat > "$PW" <<'JS'
const fs=require('fs'); const path=require('path');
const BASE=process.env.BASE, RID=process.env.RID, EVID=process.env.EVID;
const p=(f)=>path.join(EVID,f);
const now=()=>new Date().toISOString();
const append=(f,o)=>fs.appendFileSync(p(f), JSON.stringify(o)+"\n");
const write=(f,o)=>fs.writeFileSync(p(f), JSON.stringify(o,null,2));
(async()=>{
  const pw=require(require.resolve('playwright',{paths:[process.cwd()]}));
  const browser=await pw.chromium.launch({headless:true});
  const ctx=await browser.newContext({viewport:{width:1400,height:900}, ignoreHTTPSErrors:true});
  const page=await ctx.newPage();
  page.setDefaultTimeout(20000);
  page.setDefaultNavigationTimeout(25000);

  page.on('console', (msg)=>{
    const rec={ts:now(),type:msg.type(),text:msg.text(),location:msg.location()};
    if(msg.type()==='error') append('console_error.jsonl',rec);
    else if(msg.type()==='warning') append('console_warn.jsonl',rec);
  });
  page.on('pageerror', (err)=>append('pageerror.jsonl',{ts:now(),name:err.name,message:err.message,stack:err.stack||null}));
  page.on('requestfailed',(req)=>append('requestfailed.jsonl',{ts:now(),url:req.url(),failure:req.failure()}));

  async function safeShot(name){
    try{
      await page.screenshot({path:p(name), timeout:5000, fullPage:false, animations:'disabled'});
    }catch(e){
      append('pw_internal.jsonl',{ts:now(),type:'screenshot_error',name,msg:String(e&&e.message||e)});
    }
  }
  async function gotoFast(url){
    await page.goto(url,{waitUntil:'domcontentloaded', timeout:25000});
    await page.waitForTimeout(600);
  }

  const tabs=[['/vsp5','vsp5'],['/runs','runs'],['/data_source','data_source'],['/settings','settings'],['/rule_overrides','rule_overrides']];
  for(const [pth,tag] of tabs){
    const url=`${BASE}${pth}?rid=${encodeURIComponent(RID)}`;
    append('nav.jsonl',{ts:now(),step:'goto',tag,url});
    try{
      await gotoFast(url);
      try{ fs.writeFileSync(p(`page_${tag}.html`), await page.content()); }catch{}
      await safeShot(`page_${tag}.png`);
    }catch(e){
      append('pageerror.jsonl',{ts:now(),name:'GotoError',message:String(e&&e.message||e),stack:e&&e.stack||null});
    }
  }

  await ctx.close(); await browser.close();

  const count=(f)=>{ try{ const s=fs.readFileSync(p(f),'utf-8').trim(); return s? s.split('\n').filter(Boolean).length:0; }catch{return 0;} };
  const ce=count('console_error.jsonl'), pe=count('pageerror.jsonl'), rf=count('requestfailed.jsonl');
  const ok=(ce===0 && pe===0);
  write('verdict.json',{ok,ts:now(),base:BASE,rid:RID,evidence_dir:EVID,console_error_lines:ce,pageerror_lines:pe,requestfailed_lines:rf});
  process.exit(ok?0:6);
})().catch(e=>{
  try{ write('verdict.json',{ok:false,ts:now(),base:BASE,rid:RID,evidence_dir:EVID,reason:'UNHANDLED',message:String(e&&e.message||e),stack:e&&e.stack||null}); }catch{}
  process.exit(6);
});
JS

BASE="$BASE" RID="$RID" EVID="$EVID" node "$PW" >"$EVID/pw_gate.out" 2>"$EVID/pw_gate.err" || true
[ -s "$EVID/verdict.json" ] || { log "[FAIL] verdict.json missing"; tail -n 80 "$EVID/pw_gate.err" | tee -a "$EVID/summary.txt" >/dev/null || true; echo "EVID=$EVID"; exit 2; }

log "== verdict =="
cat "$EVID/verdict.json" | tee -a "$EVID/summary.txt" >/dev/null
echo "EVID=$EVID"
cat "$EVID/verdict.json"
