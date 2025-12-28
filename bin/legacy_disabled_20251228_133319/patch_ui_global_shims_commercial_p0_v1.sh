#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_UI_GLOBAL_SHIMS_COMMERCIAL_P0_V1"

# 1) write global shim js (loaded FIRST)
JS="static/js/vsp_ui_global_shims_commercial_p0_v1.js"
mkdir -p static/js
[ -f "$JS" ] && cp -f "$JS" "$JS.bak_${TS}" && echo "[BACKUP] $JS.bak_${TS}"

cat > "$JS" <<'JS'
/* VSP_UI_GLOBAL_SHIMS_COMMERCIAL_P0_V1
 * 목적: UI 안정화(P0)
 *  - Fix: VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...) is not a function
 *  - Fetch fallback: run_status_v2 -> run_status_v1 (+ /v1/<rid>)
 *  - Soft-degrade for missing endpoints (never throw to console)
 */
(function(){
  'use strict';
  if (window.__VSP_UI_GLOBAL_SHIMS_COMMERCIAL_P0_V1) return;
  window.__VSP_UI_GLOBAL_SHIMS_COMMERCIAL_P0_V1 = 1;

  // ---- (A) normalize drilldown artifacts callable BEFORE anyone uses it ----
  function normalizeCallable(v){
    if (typeof v === 'function') return v;
    if (v && typeof v.open === 'function') {
      const obj = v;
      const fn = function(arg){
        try { return obj.open(arg); } catch(e){ try{ console.warn('[VSP][DD] open failed', e);}catch(_){} return null; }
      };
      fn.__wrapped_from_object = true;
      return fn;
    }
    const noop = function(_arg){ return null; };
    noop.__noop = true;
    return noop;
  }

  try{
    let _val = window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
    Object.defineProperty(window, 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', {
      configurable: true, enumerable: true,
      get: function(){ return _val; },
      set: function(v){ _val = normalizeCallable(v); }
    });
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = _val;
  }catch(e){
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = normalizeCallable(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2);
  }

  // ---- (B) fetch fallback (targeted) ----
  const _fetch = window.fetch ? window.fetch.bind(window) : null;
  if (_fetch) {
    function parseRidFromUrl(u){
      try{
        const url = new URL(u, window.location.origin);
        return url.searchParams.get('rid') || '';
      }catch(_){ return ''; }
    }
    function swapEndpoint(u, from, to){
      try { return u.replace(from, to); } catch(_) { return u; }
    }
    async function tryFetch(u, init){
      try { return await _fetch(u, init); } catch(_) { return null; }
    }

    window.fetch = async function(input, init){
      const url = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
      let res = null;

      // first attempt
      res = await tryFetch(input, init);

      // if ok => return
      if (res && res.ok) return res;

      // targeted fallbacks
      if (url.includes('/api/vsp/run_status_v2')) {
        const rid = parseRidFromUrl(url);
        // 1) v2 -> v1 (same query)
        let u1 = swapEndpoint(url, '/api/vsp/run_status_v2', '/api/vsp/run_status_v1');
        let r1 = await tryFetch(u1, init);
        if (r1 && r1.ok) return r1;

        // 2) path form /run_status_v1/<rid>
        if (rid) {
          let u2 = '/api/vsp/run_status_v1/' + encodeURIComponent(rid);
          let r2 = await tryFetch(u2, init);
          if (r2 && r2.ok) return r2;
        }
        return res || r1 || null;
      }

      if (url.includes('/api/vsp/findings_effective_v1')) {
        const rid = parseRidFromUrl(url);
        // try path form /findings_effective_v1/<rid>
        if (rid) {
          let u2 = '/api/vsp/findings_effective_v1/' + encodeURIComponent(rid);
          let r2 = await tryFetch(u2, init);
          if (r2 && r2.ok) return r2;
        }
        // no hard fallback => return original (avoid throwing)
        return res;
      }

      // default: return original result (even if null)
      return res;
    };
  }
})();
JS

node --check "$JS" >/dev/null && echo "[OK] node --check $JS"

# 2) inject script tag into main template(s) BEFORE other scripts
TPLS=()
# primary known template
[ -f "templates/vsp_dashboard_2025.html" ] && TPLS+=("templates/vsp_dashboard_2025.html")
# also patch any template that serves vsp4
while IFS= read -r f; do TPLS+=("$f"); done < <(grep -RIl "/vsp4" templates 2>/dev/null || true)

# unique
uniq_tpls=()
for t in "${TPLS[@]}"; do
  [[ " ${uniq_tpls[*]} " == *" $t "* ]] || uniq_tpls+=("$t")
done

[ "${#uniq_tpls[@]}" -gt 0 ] || { echo "[ERR] cannot find template to inject"; exit 2; }

for T in "${uniq_tpls[@]}"; do
  cp -f "$T" "$T.bak_${MARK}_${TS}" && echo "[BACKUP] $T.bak_${MARK}_${TS}"

  python3 - "$T" "$JS" "$MARK" "$TS" <<'PY'
from pathlib import Path
import sys, re
tpl = Path(sys.argv[1])
js  = sys.argv[2]
mark= sys.argv[3]
ts  = sys.argv[4]

s = tpl.read_text(encoding="utf-8", errors="replace")
if mark in s:
    print("[OK] already injected:", tpl)
    raise SystemExit(0)

tag = f'\n<!-- {mark} -->\n<script src="/{js}?v={ts}"></script>\n'

# insert before </head> preferred (loads early), else before </body>, else prepend
if re.search(r'</head\s*>', s, flags=re.I):
    s2 = re.sub(r'(</head\s*>)', tag + r'\1', s, count=1, flags=re.I)
elif re.search(r'</body\s*>', s, flags=re.I):
    s2 = re.sub(r'(</body\s*>)', tag + r'\1', s, count=1, flags=re.I)
else:
    s2 = tag + s

tpl.write_text(s2, encoding="utf-8")
print("[OK] injected tag into:", tpl)
PY
done

echo
echo "DONE."
echo "NEXT: Ctrl+Shift+R (hard refresh) => click 5 tabs (dashboard/runs/datasource/settings/rules) xem console còn đỏ không."
