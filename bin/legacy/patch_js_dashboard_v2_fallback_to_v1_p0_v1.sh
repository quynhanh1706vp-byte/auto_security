#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_dash_fallback_${TS}"
echo "[BACKUP] $F.bak_dash_fallback_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_DASH_FETCH_FALLBACK_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

snippet = r"""
/* VSP_DASH_FETCH_FALLBACK_P0_V1: if dashboard_commercial_v2 fails/ok=false -> fallback to v1 (no KPI=0) */
(function(){
  try{
    if (window.__VSP_DASH_FETCH_FALLBACK_P0_V1) return;
    window.__VSP_DASH_FETCH_FALLBACK_P0_V1 = 1;
    const _fetch = window.fetch;
    if (typeof _fetch !== 'function') return;

    function toUrl(input){
      try{
        if (typeof input === 'string') return input;
        if (input && typeof input.url === 'string') return input.url;
      }catch(_){}
      return '';
    }
    function v2toV1(u){
      return (u||'').replace('/api/vsp/dashboard_commercial_v2','/api/vsp/dashboard_commercial_v1');
    }

    window.fetch = async function(input, init){
      const u = toUrl(input);
      const isDashV2 = u.includes('/api/vsp/dashboard_commercial_v2');
      if (!isDashV2) return _fetch.apply(this, arguments);

      try{
        const resp = await _fetch.apply(this, arguments);
        if (!resp || !resp.ok){
          return _fetch.call(this, v2toV1(u), init);
        }
        try{
          const j = await resp.clone().json();
          if (j && j.ok === false){
            return _fetch.call(this, v2toV1(u), init);
          }
        }catch(_){}
        return resp;
      }catch(e){
        return _fetch.call(this, v2toV1(u), init);
      }
    };

    console.log("[VSP] dash fetch fallback v2->v1 installed");
  }catch(_){}
})();
"""

# inject right after first 'use strict'
idx = s.find("'use strict'")
if idx < 0:
    idx = s.find('"use strict"')
if idx < 0:
    # if can't find, prepend safely
    s = snippet + "\n" + s
else:
    # insert after the line that contains use strict;
    line_end = s.find("\n", idx)
    if line_end < 0:
        line_end = idx
    s = s[:line_end+1] + snippet + "\n" + s[line_end+1:]

p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

node --check "$F"
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R /vsp4#dashboard. Nếu v2 ok=false -> UI tự fallback v1, KPI không còn 0."
