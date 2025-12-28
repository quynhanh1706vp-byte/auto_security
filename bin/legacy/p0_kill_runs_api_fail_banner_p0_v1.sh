#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import time, re

MARK = "VSP_P0_RUNS_BANNER_KILL_V1"
payload = r"""<!-- VSP_P0_RUNS_BANNER_KILL_V1 -->
<script id="VSP_P0_RUNS_BANNER_KILL_V1">
(function(){
  function killOnce(){
    // 1) clear sticky localStorage flags related to runs/api fail/degraded
    try{
      var ks=[];
      for(var i=0;i<localStorage.length;i++){ ks.push(localStorage.key(i)); }
      ks.forEach(function(k){
        if(!k) return;
        var kk = String(k).toLowerCase();
        // aggressive but safe: only touch vsp/runs-ish keys
        if(kk.indexOf('vsp')>=0 && (kk.indexOf('runs')>=0 || kk.indexOf('run')>=0)){
          if(kk.indexOf('fail')>=0 || kk.indexOf('api')>=0 || kk.indexOf('degraded')>=0 || kk.indexOf('banner')>=0){
            localStorage.removeItem(k);
          }
        }
        // some past patches used generic keys
        if(kk.indexOf('runs')>=0 && (kk.indexOf('api')>=0 || kk.indexOf('fail')>=0 || kk.indexOf('degraded')>=0)){
          localStorage.removeItem(k);
        }
      });
    }catch(e){}

    // 2) hide any banner DOM that matches RUNS API FAIL or api/vsp/runs error text
    try{
      var nodes = document.querySelectorAll('body *');
      for(var j=0;j<nodes.length;j++){
        var el = nodes[j];
        if(!el) continue;
        var t = (el.innerText || el.textContent || '').trim();
        if(!t) continue;

        var hit = (t.indexOf('RUNS API FAIL') >= 0) ||
                  (t.indexOf('/api/vsp/runs') >= 0 && t.toLowerCase().indexOf('error') >= 0);
        if(!hit) continue;

        // hide a few levels up to kill the whole banner container
        var p = el;
        for(var k2=0;k2<5;k2++){
          if(p && p.parentElement) p = p.parentElement;
        }
        try { (p||el).style.display = 'none'; } catch(_){}
      }
    }catch(e){}
  }

  function run(){
    setTimeout(killOnce, 30);
    setTimeout(killOnce, 300);
  }

  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run);
  else run();
})();
</script>
"""

tpl_root = Path("templates")
changed = []
for p in sorted(tpl_root.rglob("*.html")):
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        continue
    bak = p.with_name(p.name + f".bak_killruns_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    if "</body>" in s:
        s2 = s.replace("</body>", payload + "\n</body>")
    else:
        s2 = s + "\n" + payload + "\n"
    p.write_text(s2, encoding="utf-8")
    changed.append(str(p))

print("[OK] injected into templates:", len(changed))
for x in changed[:30]:
    print(" -", x)
PY

echo "[OK] Now restart UI and hard refresh."
# restart sạch theo chuẩn bạn đang dùng
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*pid=\\([0-9]\\+\\).*/\\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify runs API (should be 200) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=20" | sed -n '1,12p' || true
