#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_gfetch_${TS}"
echo "[BACKUP] ${JS}.bak_gfetch_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_UI_GLOBAL_FETCH_BACKOFF_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = f"""
// {MARK}
(function(){{
  if (window.__VSP_GLOBAL_FETCH_BACKOFF) return;
  window.__VSP_GLOBAL_FETCH_BACKOFF = true;

  const nativeFetch = window.fetch.bind(window);

  function mkJsonResponse(obj, status){{
    try {{
      return new Response(JSON.stringify(obj), {{
        status: status || 503,
        headers: {{ "Content-Type":"application/json" }}
      }});
    }} catch(e) {{
      return {{
        ok: false,
        status: status || 503,
        json: async()=>obj
      }};
    }}
  }}

  function urlToStr(input){{
    try {{
      if (typeof input === "string") return input;
      if (input && typeof input.url === "string") return input.url;
    }} catch(e) {{}}
    return "";
  }}

  function shouldGuard(url){{
    // Guard only polling endpoints (avoid breaking downloads/exports/run_file)
    if (!url) return false;
    // same-origin or explicit 127.0.0.1:8910
    const u = url.toString();
    if (!(u.includes("/api/vsp/"))) return false;

    // allow these always (no backoff)
    if (u.includes("/api/vsp/run_file")) return false;
    if (u.includes("/api/vsp/export_")) return false;
    if (u.includes("/api/vsp/sha256")) return false;

    // guard noisy poll endpoints
    if (u.includes("/api/vsp/runs")) return true;
    if (u.includes("/api/vsp/dashboard")) return true;

    return false;
  }}

  const st = {{
    inflight: false,
    backoffMs: 2000,
    nextTryAt: 0,
    lastWarnAt: 0,
  }};

  window.fetch = async function(input, init){{
    const url = urlToStr(input);
    if (!shouldGuard(url)) {{
      return nativeFetch(input, init);
    }}

    const now = Date.now();
    if (now < st.nextTryAt) {{
      // IMPORTANT: no network call => no red XHR spam
      return mkJsonResponse({{ok:false, who:"VSP_FETCH_BACKOFF", error:"BACKOFF", nextTryAt:st.nextTryAt}}, 503);
    }}
    if (st.inflight) {{
      return mkJsonResponse({{ok:false, who:"VSP_FETCH_BACKOFF", error:"INFLIGHT"}}, 503);
    }}

    st.inflight = true;

    const ctrl = new AbortController();
    const timeoutMs = 8000;
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);

    try {{
      const _init = Object.assign({{}}, init||{{}});
      _init.signal = ctrl.signal;
      _init.cache = "no-store";
      const r = await nativeFetch(input, _init);
      // server responded => reset backoff
      st.backoffMs = 2000;
      st.nextTryAt = 0;
      return r;
    }} catch(e) {{
      const n2 = Date.now();
      if (n2 - st.lastWarnAt > 5000) {{
        console.warn("[VSP] poll endpoints down; backoff", st.backoffMs, "ms");
        st.lastWarnAt = n2;
      }}
      st.nextTryAt = n2 + st.backoffMs;
      st.backoffMs = Math.min(st.backoffMs * 2, 60000);
      // no rethrow
      return mkJsonResponse({{ok:false, who:"VSP_FETCH_BACKOFF", error:"FETCH_FAILED"}}, 503);
    }} finally {{
      clearTimeout(t);
      st.inflight = false;
    }}
  }};
}})();
"""

# insert after "use strict" if exists, else prepend
if '"use strict"' in s or "'use strict'" in s:
    lines=s.splitlines(True)
    out=[]
    inserted=False
    for ln in lines:
        out.append(ln)
        if not inserted and ("use strict" in ln):
            out.append("\n"+inject+"\n")
            inserted=True
    s2="".join(out)
else:
    s2=inject + "\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

node --check static/js/vsp_runs_tab_resolved_v1.js
echo "[OK] node --check OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
