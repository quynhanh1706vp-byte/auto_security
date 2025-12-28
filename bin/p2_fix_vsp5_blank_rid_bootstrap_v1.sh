#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

JS="static/js/vsp_dashboard_consistency_patch_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_ridbootstrap_${TS}"
echo "[BACKUP] ${JS}.bak_ridbootstrap_${TS}"

python3 - "$JS" <<'PY'
from pathlib import Path
p=Path(__import__("sys").argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_RID_BOOTSTRAP_EARLY_V1"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

boot = r'''/* {MARK}
   Ensure RID exists BEFORE vsp_dashboard_luxe_v1.js runs.
*/
(function(){
  function qsRid(){
    try { return (new URLSearchParams(window.location.search)).get('rid') || ''; } catch(e){ return ''; }
  }
  async function fetchLatestRid(){
    try{
      const r = await fetch('/api/vsp/rid_latest', {credentials:'same-origin'});
      const j = await r.json();
      return (j && (j.rid || j.run_id || '')) || '';
    }catch(e){ return ''; }
  }
  async function ensureRid(){
    let rid = qsRid();
    if(!rid){
      try { rid = localStorage.getItem('vsp_rid') || ''; } catch(e){}
    }
    if(!rid && window.__VSP_RID) rid = String(window.__VSP_RID||'');
    if(!rid){
      rid = await fetchLatestRid();
    }
    if(rid){
      window.__VSP_RID = rid;
      try { localStorage.setItem('vsp_rid', rid); } catch(e){}
      // patch URL if missing rid (no reload)
      try{
        const u = new URL(window.location.href);
        if(!u.searchParams.get('rid')){
          u.searchParams.set('rid', rid);
          history.replaceState({}, '', u.toString());
        }
      }catch(e){}
    } else {
      console.warn('[VSP] RID still missing; dashboard should degrade gracefully');
    }
    try{
      window.dispatchEvent(new CustomEvent('vsp:rid_ready', {detail:{rid: rid||''}}));
    }catch(e){}
  }

  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ensureRid);
  else ensureRid();
})();
'''.replace("{MARK}", MARK)

# Prepend bootstrap to the file to run as early as possible
p.write_text(boot + "\n\n" + s, encoding="utf-8")
print("[OK] injected early RID bootstrap into", p)
PY

# quick smoke: RID should be obtainable
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] rid_latest=$RID"

echo "== [CHECK] marker head =="
head -n 8 "$JS" | sed 's/^/  /'
echo "[OK] done"
