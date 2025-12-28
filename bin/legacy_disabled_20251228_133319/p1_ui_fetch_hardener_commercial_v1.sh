#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need grep; need find

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

# 1) Fix templates: script src must be exactly "...js?v=<TS>" (ONE query only)
python3 - <<PY
from pathlib import Path
import re
ts = "${TS}"
tpls = [
  "templates/vsp_5tabs_enterprise_v2.html",
  "templates/vsp_dashboard_2025.html",
  "templates/vsp_data_source_v1.html",
  "templates/vsp_rule_overrides_v1.html",
]
fixed=[]
for f in tpls:
  p=Path(f)
  if not p.exists(): 
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  s2=re.sub(r'(/static/js/vsp_p1_page_boot_v1\.js)\?v=[^"\']+', r'\\1?v='+ts, s)
  s2=re.sub(r'(/static/js/vsp_p1_page_boot_v1\.js)(\?v='+ts+r')(\?v=[^"\']+)', r'\\1\\2', s2)
  s2=re.sub(r'(<script[^>]+src=")(/static/js/vsp_p1_page_boot_v1\.js)([^"]*)"([^>]*></script>)',
            lambda m: m.group(1)+m.group(2)+"?v="+ts+'"' + m.group(4), s2)
  if s2!=s:
    p.write_text(s2, encoding="utf-8")
    fixed.append(f)
print("[OK] templates fixed:", len(fixed))
for x in fixed: print(" -", x)
PY

# 2) Inject fetch hardener into boot JS (retry + no-store + degraded fallback)
cp -f "$JS" "${JS}.bak_fetch_hardener_${TS}"
echo "[BACKUP] ${JS}.bak_fetch_hardener_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time
p=Path("static/js/vsp_p1_page_boot_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_FETCH_HARDENER_COMMERCIAL_V1"
if MARK in s:
  print("[OK] marker already present:", MARK)
  raise SystemExit(0)

inject = r'''/* VSP_P1_FETCH_HARDENER_COMMERCIAL_V1 %TS% */
(function(){
  try{
    if (window.__VSP_P1_FETCH_HARDENER_COMMERCIAL_V1__) return;
    window.__VSP_P1_FETCH_HARDENER_COMMERCIAL_V1__ = true;

    const _fetch = (window.fetch && window.fetch.bind) ? window.fetch.bind(window) : null;
    if (!_fetch) return;

    function sleep(ms){ return new Promise(r=>setTimeout(r, ms)); }

    function isTarget(url){
      try{
        if(!url) return false;
        return (
          url.indexOf("/api/vsp/runs") >= 0 ||
          url.indexOf("/api/vsp/dash") >= 0 ||
          url.indexOf("/api/vsp/dashboard") >= 0 ||
          url.indexOf("/api/vsp/summary") >= 0
        );
      }catch(e){ return false; }
    }

    async function hardFetch(input, init){
      let url = "";
      try{
        url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
      }catch(e){ url=""; }

      if(!isTarget(url)) return _fetch(input, init);

      // Only harden GET-like calls
      const baseInit = Object.assign({cache:"no-store", credentials:"same-origin"}, init||{});
      const method = (baseInit.method || "GET").toUpperCase();
      if(method !== "GET" && method !== "HEAD") return _fetch(input, init);

      try{
        baseInit.headers = Object.assign({"Cache-Control":"no-store","Pragma":"no-cache"}, baseInit.headers||{});
      }catch(e){}

      let lastResp = null;
      let lastErr = null;

      // Retry up to 4 times, backoff 200/400/600/800ms
      for(let i=0;i<4;i++){
        try{
          const r = await _fetch(url, baseInit);
          lastResp = r;
          if(r && r.status < 500) return r;
        }catch(e){
          lastErr = e;
        }
        await sleep(200*(i+1));
      }

      if(lastResp) return lastResp;

      // Degraded synthetic response (keeps UI alive)
      const body = JSON.stringify({
        ok: true,
        rid_latest: null,
        items: [],
        degraded: true,
        error: String(lastErr || "runs_fetch_failed")
      });
      try{
        return new Response(body, {
          status: 200,
          headers: {
            "Content-Type":"application/json; charset=utf-8",
            "Cache-Control":"no-store",
            "X-VSP-DEGRADED":"1"
          }
        });
      }catch(e){
        return _fetch(url, baseInit); // last resort
      }
    }

    window.fetch = hardFetch;
  }catch(e){}
})();
'''
inject = inject.replace("%TS%", time.strftime("%Y%m%d_%H%M%S"))
s2 = inject + "\n" + s
p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

echo "[OK] restart UI"
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || true
else
  echo "[WARN] missing start script bin/p1_ui_8910_single_owner_start_v2.sh (skip restart)"
fi

echo "== verify =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_p1_page_boot_v1.js" | head -n 2 || true
grep -n "VSP_P1_FETCH_HARDENER_COMMERCIAL_V1" static/js/vsp_p1_page_boot_v1.js | head -n 2 || true

echo "[NEXT] Mở Incognito /vsp5 (khuyến nghị) hoặc Ctrl+F5 để chắc chắn sạch cache."
