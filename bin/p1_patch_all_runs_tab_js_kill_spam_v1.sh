#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need node; need date; need sudo; need systemctl; need ls; need grep

JS_DIR="static/js"
[ -d "$JS_DIR" ] || { echo "[ERR] missing $JS_DIR"; exit 2; }

# Targets: the stable file + any resolved/resolve timestamped variants
mapfile -t FILES < <(ls -1 "$JS_DIR"/vsp_runs_tab_resolved_v1.js 2>/dev/null; ls -1 "$JS_DIR"/vsp_runs_tab_resolve*.js 2>/dev/null || true)

[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] no runs-tab js files found under $JS_DIR"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] files=${#FILES[@]} TS=$TS"
printf '%s\n' "${FILES[@]}" | sed 's/^/[FILE] /'

python3 - <<'PY'
from pathlib import Path
import re, time

MARK="VSP_P1_GUARDED_POLL_FETCH_V1"

inject = f"""// {MARK}
(function(){{
  if (window.__VSP_GUARDED_FETCH) return;
  window.__VSP_GUARDED_FETCH = true;

  const nativeFetch = (window.fetch ? window.fetch.bind(window) : null);

  const st = {{
    inflight:false,
    backoffMs:2000,
    nextTryAt:0,
    lastWarnAt:0,
  }};

  function mkJsonResponse(obj, status){{
    try {{
      return new Response(JSON.stringify(obj), {{
        status: status || 503,
        headers: {{ "Content-Type":"application/json" }}
      }});
    }} catch(e) {{
      return {{ ok:false, status: status||503, json: async()=>obj }};
    }}
  }}

  function urlStr(input){{
    try {{
      if (typeof input === "string") return input;
      if (input && typeof input.url === "string") return input.url;
    }} catch(e) {{}}
    return "";
  }}

  function shouldGuard(url){{
    if (!url) return false;
    const u = url.toString();
    if (!u.includes("/api/vsp/")) return false;

    // never guard download/export endpoints
    if (u.includes("/api/vsp/run_file")) return false;
    if (u.includes("/api/vsp/run_file2")) return false;
    if (u.includes("/api/vsp/export_")) return false;
    if (u.includes("/api/vsp/sha256")) return false;

    // guard only polling endpoints
    if (u.includes("/api/vsp/runs")) return true;
    if (u.includes("/api/vsp/dashboard")) return true;
    return false;
  }}

  window.__VSP_GUARDED_FETCH_FN = async function(input, init){{
    const u = urlStr(input);
    if (!nativeFetch || !shouldGuard(u)) {{
      return nativeFetch ? nativeFetch(input, init) : mkJsonResponse({{ok:false,error:"NO_FETCH"}},503);
    }}

    const now = Date.now();
    if (now < st.nextTryAt) {{
      return mkJsonResponse({{ok:false, who:"VSP_GUARDED_FETCH", error:"BACKOFF"}}, 503);
    }}
    if (st.inflight) {{
      return mkJsonResponse({{ok:false, who:"VSP_GUARDED_FETCH", error:"INFLIGHT"}}, 503);
    }}

    st.inflight = True if False else True  # keep syntax valid in JS injection? (won't be used)
  }};
}})();
"""

# Fix the one JS line above: replace the python-ish dummy with real JS assignment
inject = inject.replace("st.inflight = True if False else True", "st.inflight = true")

inject2 = """
  // Guarded fetch (real)
  window.__VSP_GUARDED_FETCH_FN = async function(input, init){
    const u = urlStr(input);
    if (!nativeFetch || !shouldGuard(u)){
      return nativeFetch ? nativeFetch(input, init) : mkJsonResponse({ok:false,error:"NO_FETCH"},503);
    }

    const now = Date.now();
    if (now < st.nextTryAt){
      // NO network call => no red spam
      return mkJsonResponse({ok:false, who:"VSP_GUARDED_FETCH", error:"BACKOFF"}, 503);
    }
    if (st.inflight){
      return mkJsonResponse({ok:false, who:"VSP_GUARDED_FETCH", error:"INFLIGHT"}, 503);
    }

    st.inflight = true;
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), 8000);

    try{
      const _init = Object.assign({}, init||{});
      _init.signal = ctrl.signal;
      _init.cache = "no-store";
      const r = await nativeFetch(input, _init);
      st.backoffMs = 2000;
      st.nextTryAt = 0;
      return r;
    }catch(e){
      const n2 = Date.now();
      if (n2 - st.lastWarnAt > 5000){
        console.warn("[VSP] poll down; backoff", st.backoffMs, "ms");
        st.lastWarnAt = n2;
      }
      st.nextTryAt = n2 + st.backoffMs;
      st.backoffMs = Math.min(st.backoffMs * 2, 60000);
      return mkJsonResponse({ok:false, who:"VSP_GUARDED_FETCH", error:"FETCH_FAILED"}, 503);
    }finally{
      clearTimeout(t);
      st.inflight = false;
    }
  };

  // Guard XHR too (some code uses it; you enabled Log XMLHttpRequests)
  try{
    const _open = XMLHttpRequest.prototype.open;
    const _send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url){
      try{ this.__vsp_url = url; }catch(e){}
      return _open.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function(){
      try{
        const u = (this.__vsp_url || "");
        if (shouldGuard(u)){
          const now = Date.now();
          if (now < st.nextTryAt || st.inflight){
            // NO network call => avoid red spam
            const self=this;
            setTimeout(function(){
              try{ self.abort(); }catch(e){}
            }, 0);
            return;
          }
        }
      }catch(e){}
      return _send.apply(this, arguments);
    };
  }catch(e){}
"""

# splice inject2 right before final "})();"
inject = inject.replace("})();", inject2 + "\n})();")

def patch_file(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        return False, "already"
    # prepend injection at very top
    s = inject + "\n" + s

    # replace any fetch( with guarded fetch (catch the captured fetch patterns too)
    s = re.sub(r'(?<![\w$])fetch\s*\(', 'window.__VSP_GUARDED_FETCH_FN(', s)
    s = s.replace('window.fetch(', 'window.__VSP_GUARDED_FETCH_FN(')
    s = s.replace('globalThis.fetch(', 'window.__VSP_GUARDED_FETCH_FN(')

    fp.write_text(s, encoding="utf-8")
    return True, "patched"

import sys
paths = sys.argv[1:]
ok=0
for f in paths:
    fp=Path(f)
    changed, msg = patch_file(fp)
    print(f"[JS] {fp.name}: {msg}")
    ok += 1 if changed else 0
print("[OK] patched_count=", ok)
PY "${FILES[@]}"

# JS syntax check all files
for f in "${FILES[@]}"; do
  node --check "$f" >/dev/null
done
echo "[OK] node --check OK for all"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
