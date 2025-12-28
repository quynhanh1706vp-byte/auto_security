#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need curl; need jq; need grep

TS="$(date +%Y%m%d_%H%M%S)"
export TS
echo "[INFO] TS=$TS"

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

# 1) Patch templates: bootjs must be ONE query string + defer
python3 - <<'PY'
from pathlib import Path
import os, re

ts=os.environ["TS"]
tpls=[
  Path("templates/vsp_5tabs_enterprise_v2.html"),
  Path("templates/vsp_dashboard_2025.html"),
  Path("templates/vsp_data_source_v1.html"),
  Path("templates/vsp_rule_overrides_v1.html"),
]
boot_re = re.compile(r'<script\s+(?:defer\s+)?src="/static/js/vsp_p1_page_boot_v1\.js\?v=[^"]+"\s*></script>')
new_tag = f'<script defer src="/static/js/vsp_p1_page_boot_v1.js?v={ts}"></script>'

changed=[]
for p in tpls:
  if not p.exists(): 
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  s2=boot_re.sub(new_tag, s)
  if s2!=s:
    p.write_text(s2, encoding="utf-8")
    changed.append(p.name)

print("[OK] templates patched:", len(changed))
for x in changed: print(" -", x)
PY

# 2) Prepend bootjs: force XHR for /api/vsp/runs (bypass fetch/cache glitches)
cp -f "$JS" "${JS}.bak_force_xhr_${TS}"
echo "[BACKUP] ${JS}.bak_force_xhr_${TS}"

python3 - <<'PY'
from pathlib import Path
import os

ts=os.environ["TS"]
p=Path("static/js/vsp_p1_page_boot_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_FORCE_XHR_RUNS_V1"
if MARK in s:
  print("[OK] marker already present:", MARK)
  raise SystemExit(0)

inject = r'''/* VSP_P1_FORCE_XHR_RUNS_V1 __TS__ */
(function(){
  if (window.__VSP_P1_FORCE_XHR_RUNS_V1__) return;
  window.__VSP_P1_FORCE_XHR_RUNS_V1__ = true;

  function xhrGet(url){
    return new Promise(function(resolve, reject){
      try{
        var x = new XMLHttpRequest();
        x.open('GET', url, true);
        try { x.setRequestHeader('Cache-Control', 'no-store'); } catch(_){}
        x.onreadystatechange = function(){
          if (x.readyState !== 4) return;
          resolve({ status: x.status || 0, text: x.responseText || '' });
        };
        x.onerror = function(){ reject(new Error('xhr error')); };
        x.send(null);
      }catch(e){ reject(e); }
    });
  }

  var origFetch = window.fetch ? window.fetch.bind(window) : null;

  window.fetch = function(input, init){
    var url = (typeof input === 'string') ? input : (input && input.url) ? input.url : (''+input);
    if (url.indexOf('/api/vsp/runs') !== -1){
      return xhrGet(url).then(function(r){
        var status = r.status || 503;
        try{
          return new Response(r.text, {
            status: status,
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'cache-control': 'no-store'
            }
          });
        }catch(e){
          // ultra-safe fallback (should not happen)
          return {
            ok: status >= 200 && status < 300,
            status: status,
            json: function(){ return Promise.resolve(JSON.parse(r.text || '{}')); },
            text: function(){ return Promise.resolve(r.text || ''); }
          };
        }
      }).catch(function(err){
        if (origFetch) return origFetch(input, init);
        throw err;
      });
    }
    return origFetch ? origFetch(input, init) : Promise.reject(new Error('fetch missing'));
  };
})();
'''
inject = inject.replace("__TS__", ts) + "\n"
p.write_text(inject + s, encoding="utf-8")
print("[OK] prepended:", MARK)
PY

# 3) Restart UI (use your standard single-owner launcher if present)
echo "[OK] restart UI"
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh
else
  echo "[WARN] missing bin/p1_ui_8910_single_owner_start_v2.sh (skip)"
fi

echo "== verify =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_p1_page_boot_v1.js" | head -n 2 || true
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | jq -r '.ok,.rid_latest,.items[0].run_id' || true
grep -n "VSP_P1_FORCE_XHR_RUNS_V1" static/js/vsp_p1_page_boot_v1.js | head -n 2 || true

echo "[NEXT] Mở Incognito -> http://127.0.0.1:8910/vsp5 (khuyến nghị) hoặc Ctrl+F5."
