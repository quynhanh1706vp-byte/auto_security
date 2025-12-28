#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fetch_norm_${TS}"
echo "[BACKUP] $F.bak_fetch_norm_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_FETCH_NORMALIZE_DASH_P0_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
/* VSP_FETCH_NORMALIZE_DASH_P0_V3: normalize dashboard payload at fetch() */
(function(){
  try{
    if (window.__VSP_FETCH_NORM_P0_V3) return;
    window.__VSP_FETCH_NORM_P0_V3 = 1;

    // ensure normalizer exists (fallback)
    if (!window.__vspNormalizeDash){
      window.__vspNormalizeDash = function(d){
        try{
          if(!d || typeof d!=="object") return d;
          const c = d?.gate?.counts_total || d?.gate?.counts || null;
          if(!c || typeof c!=="object") return d;
          const CR = +c.CRITICAL||0, HI=+c.HIGH||0, ME=+c.MEDIUM||0, LO=+c.LOW||0, IN=+c.INFO||0, TR=+c.TRACE||0;
          const total = CR+HI+ME+LO+IN+TR;
          d.by_severity = d.by_severity || {CRITICAL:CR,HIGH:HI,MEDIUM:ME,LOW:LO,INFO:IN,TRACE:TR};
          d.kpi = d.kpi || {};
          d.kpi.total   = (d.kpi.total   ?? total);
          d.kpi.critical= (d.kpi.critical?? CR);
          d.kpi.high    = (d.kpi.high    ?? HI);
          d.kpi.medium  = (d.kpi.medium  ?? ME);
          d.kpi.low     = (d.kpi.low     ?? LO);
          d.kpi.info    = (d.kpi.info    ?? IN);
          d.kpi.trace   = (d.kpi.trace   ?? TR);
          const degr = d?.degraded?.any ?? d?.kpi?.degraded ?? d?.degraded ?? null;
          if (degr !== null && d.kpi.degraded === undefined) d.kpi.degraded = degr;
          return d;
        }catch(_){ return d; }
      };
    }

    const origFetch = window.fetch && window.fetch.bind(window);
    if (!origFetch) return;

    const needNorm = (u)=>{
      try{
        if(!u) return false;
        return (
          u.includes("/api/vsp/dashboard_commercial_v2") ||
          u.includes("/api/vsp/dashboard_commercial_v1") ||
          u.includes("/api/vsp/dashboard_v3") ||
          u.includes("/api/vsp/dashboard_commercial_v2?")
        );
      }catch(_){ return false; }
    };

    window.fetch = async function(input, init){
      const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
      const res = await origFetch(input, init);
      try{
        if (!needNorm(url)) return res;
        if (!res || !res.ok) return res;

        // Only for JSON
        const ct = (res.headers && (res.headers.get("content-type")||"")) || "";
        if (ct && !ct.includes("application/json")) return res;

        const data = await res.clone().json().catch(()=>null);
        if (!data) return res;

        const norm = window.__vspNormalizeDash ? window.__vspNormalizeDash(data) : data;

        const headers = new Headers(res.headers || {});
        headers.set("content-type", "application/json; charset=utf-8");
        return new Response(JSON.stringify(norm), {
          status: res.status,
          statusText: res.statusText,
          headers
        });
      }catch(_){
        return res;
      }
    };
  }catch(_){}
})();
'''

m = re.search(r"(['\"])use strict\1\s*;\s*", s)
if m:
    i=m.end()
    s = s[:i] + inject + s[i:]
else:
    s = inject + "\n" + s

s += f"\n/* {MARK} */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check "$F"
echo "[OK] node --check OK"

bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R http://127.0.0.1:8910/vsp4  (KPI should no longer be all-0 if gate counts are nonzero)"
