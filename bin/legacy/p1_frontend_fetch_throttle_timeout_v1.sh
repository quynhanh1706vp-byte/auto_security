#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fetchpatch_${TS}"
echo "[BACKUP] ${JS}.bak_fetchpatch_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_FETCH_THROTTLE_TIMEOUT_V1"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

patch = r'''/* ===== VSP_P1_FETCH_THROTTLE_TIMEOUT_V1 ===== */
(function(){
  try{
    if (window.__VSP_FETCH_THROTTLE_TIMEOUT_V1) return;
    window.__VSP_FETCH_THROTTLE_TIMEOUT_V1 = 1;

    const origFetch = window.fetch ? window.fetch.bind(window) : null;
    if (!origFetch) return;

    const MAX_INFLIGHT = 4;
    const TIMEOUT_MS = 6000;
    let inflight = 0;
    const q = [];

    function runNext(){
      while(inflight < MAX_INFLIGHT && q.length){
        const job = q.shift();
        inflight++;
        job().finally(()=>{ inflight--; runNext(); });
      }
    }

    window.fetch = function(input, init){
      return new Promise((resolve,reject)=>{
        const job = async () => {
          const ctrl = new AbortController();
          const t = setTimeout(()=>ctrl.abort("timeout"), TIMEOUT_MS);
          try{
            const ii = Object.assign({}, init||{}, { signal: ctrl.signal });
            const res = await origFetch(input, ii);
            resolve(res);
          }catch(e){
            reject(e);
          }finally{
            clearTimeout(t);
          }
        };
        q.push(job);
        runNext();
      });
    };
  }catch(e){}
})();\n'''

# chèn patch lên đầu file để có hiệu lực sớm
s = patch + s
p.write_text(s, encoding="utf-8")
print("[OK] patched fetch throttle+timeout into", p)
PY

echo "[DONE] Ctrl+Shift+R: http://127.0.0.1:8910/vsp5"
