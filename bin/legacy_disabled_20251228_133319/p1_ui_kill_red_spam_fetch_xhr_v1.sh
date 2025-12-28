#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_killspam_${TS}"
echo "[BACKUP] ${JS}.bak_killspam_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_KILL_RED_SPAM_FETCH_XHR_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = f"""// {MARK}
(function(){{
  if (window.__VSP_GUARDED_FETCH) return;

  // keep original fetch
  if (!window.__VSP_NATIVE_FETCH) {{
    window.__VSP_NATIVE_FETCH = (window.fetch ? window.fetch.bind(window) : null);
  }}

  const st = {{
    inflight: false,
    backoffMs: 2000,
    nextTryAt: 0,
    lastWarnAt: 0,
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

    // only guard our poll APIs
    if (!u.includes("/api/vsp/")) return false;

    // never guard file/download/export/sha
    if (u.includes("/api/vsp/run_file")) return false;
    if (u.includes("/api/vsp/run_file2")) return false;
    if (u.includes("/api/vsp/export_")) return false;
    if (u.includes("/api/vsp/sha256")) return false;

    // guard noisy polling endpoints
    if (u.includes("/api/vsp/runs")) return true;
    if (u.includes("/api/vsp/dashboard")) return true;  // includes dashboard_commercial_v2
    return false;
  }}

  window.__VSP_GUARDED_FETCH = async function(input, init){{
    const nf = window.__VSP_NATIVE_FETCH;
    const u = urlStr(input);

    if (!nf || !shouldGuard(u)) {{
      return nf ? nf(input, init) : mkJsonResponse({{ok:false,error:"NO_FETCH"}}, 503);
    }}

    const now = Date.now();
    if (now < st.nextTryAt) {{
      // IMPORTANT: no network call => no red spam
      return mkJsonResponse({{ok:false, who:"VSP_GUARDED_FETCH", error:"BACKOFF"}}, 503);
    }}
    if (st.inflight) {{
      return mkJsonResponse({{ok:false, who:"VSP_GUARDED_FETCH", error:"INFLIGHT"}}, 503);
    }}

    st.inflight = true;
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), 8000);

    try {{
      const _init = Object.assign({{}}, init||{{}});
      _init.signal = ctrl.signal;
      _init.cache = "no-store";
      const r = await nf(input, _init);

      // responded => reset backoff
      st.backoffMs = 2000;
      st.nextTryAt = 0;
      return r;
    }} catch(e) {{
      const n2 = Date.now();
      if (n2 - st.lastWarnAt > 5000) {{
        console.warn("[VSP] poll down; backoff", st.backoffMs, "ms");
        st.lastWarnAt = n2;
      }}
      st.nextTryAt = n2 + st.backoffMs;
      st.backoffMs = Math.min(st.backoffMs * 2, 60000);
      return mkJsonResponse({{ok:false, who:"VSP_GUARDED_FETCH", error:"FETCH_FAILED"}}, 503);
    }} finally {{
      clearTimeout(t);
      st.inflight = false;
    }}
  }};

  // Also guard XMLHttpRequest (some codepaths / libs use XHR)
  try {{
    const _open = XMLHttpRequest.prototype.open;
    const _send = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url){{
      try {{ this.__vsp_url = url; }} catch(e) {{}}
      return _open.apply(this, arguments);
    }};

    XMLHttpRequest.prototype.send = function(){{
      try {{
        const u = (this.__vsp_url || "");
        if (shouldGuard(u)) {{
          const now = Date.now();
          if (now < st.nextTryAt || st.inflight) {{
            // NO network call => avoid red spam
            const self=this;
            setTimeout(function(){{
              try {{ self.abort(); }} catch(e) {{}}
              try {{ if (self.onerror) self.onerror(new Event("error")); }} catch(e) {{}}
              try {{ if (self.onreadystatechange) self.onreadystatechange(); }} catch(e) {{}}
            }}, 0);
            return;
          }}
        }}
      }} catch(e) {{}}
      return _send.apply(this, arguments);
    }};
  }} catch(e) {{}}
}})();
"""

# 1) prepend injection at very top
s = inject + "\n" + s

# 2) Replace ALL fetch calls to guarded fetch
# - fetch(  -> window.__VSP_GUARDED_FETCH(
# - window.fetch( -> window.__VSP_GUARDED_FETCH(
# - globalThis.fetch( -> window.__VSP_GUARDED_FETCH(
s = re.sub(r'(?<![\w$])fetch\s*\(', 'window.__VSP_GUARDED_FETCH(', s)
s = s.replace('window.fetch(', 'window.__VSP_GUARDED_FETCH(')
s = s.replace('globalThis.fetch(', 'window.__VSP_GUARDED_FETCH(')

p.write_text(s, encoding="utf-8")
print("[OK] injected + replaced fetch() -> __VSP_GUARDED_FETCH()")
PY

node --check static/js/vsp_runs_tab_resolved_v1.js
echo "[OK] node --check OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
