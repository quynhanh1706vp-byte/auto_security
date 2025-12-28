#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need date; need find

TS="$(date +%Y%m%d_%H%M%S)"
TPL_DIR="templates"
[ -d "$TPL_DIR" ] || { echo "[ERR] missing templates/"; exit 2; }

python3 - <<'PY'
from pathlib import Path
import re, time

MARK="VSP_GLOBAL_POLL_GUARD_P1_V1"
INJECT = f"""
<!-- {MARK} -->
<script>
(function(){{
  if (window.__VSP_GLOBAL_POLL_GUARD) return;
  window.__VSP_GLOBAL_POLL_GUARD = true;

  const nativeFetch = (globalThis.fetch ? globalThis.fetch.bind(globalThis) : null);

  const MIN = {{
    runs: 12000,
    dash: 15000
  }};
  const st = {{
    last: Object.create(null),
    cache: Object.create(null),
    inflight: Object.create(null),
    backoffMs: 2000,
    nextTryAt: 0,
    lastWarnAt: 0
  }};

  function now(){{ return Date.now(); }}
  function baseKey(u){{ try{{ return u.toString().split('?')[0]; }}catch(e){{ return ""; }} }}
  function urlStr(input){{ try{{ if (typeof input==="string") return input; if (input && input.url) return input.url; }}catch(e){{}} return ""; }}

  function shouldGuard(url){{
    const s = (url||"").toString();
    if (!s.includes("/api/vsp/")) return false;

    // never guard downloads/exports/sha/file
    if (s.includes("/api/vsp/run_file")) return false;
    if (s.includes("/api/vsp/run_file2")) return false;
    if (s.includes("/api/vsp/export_")) return false;
    if (s.includes("/api/vsp/sha256")) return false;

    if (s.includes("/api/vsp/runs")) return true;
    if (s.includes("/api/vsp/dashboard")) return true; // includes dashboard_commercial_v2
    return false;
  }}

  function minInterval(key){{
    if (key.includes("/api/vsp/runs")) return MIN.runs;
    if (key.includes("/api/vsp/dashboard")) return MIN.dash;
    return 0;
  }}

  function mkJsonResponse(obj, status){{
    try {{
      return new Response(JSON.stringify(obj), {{
        status: status || 503,
        headers: {{ "Content-Type":"application/json", "X-VSP-CACHED":"1" }}
      }});
    }} catch(e) {{
      return {{ ok:false, status:status||503, json: async()=>obj }};
    }}
  }}

  async function guardedFetch(input, init){{
    if (!nativeFetch) return mkJsonResponse({{ok:false,error:"NO_FETCH"}},503);
    const u = urlStr(input);
    if (!u || !shouldGuard(u)) return nativeFetch(input, init);

    const k = baseKey(u);
    const t = now();
    const min = minInterval(k);

    // If tab is hidden -> do NOT spam network; serve cache if any
    if (document && document.hidden) {{
      if (st.cache[k]) return new Response(st.cache[k], {{ status:200, headers:{{"Content-Type":"application/json","X-VSP-CACHED":"1"}} }});
      return mkJsonResponse({{ok:false, who:"VSP_POLL_GUARD", error:"HIDDEN"}}, 503);
    }}

    // global backoff window (after failures)
    if (t < st.nextTryAt) {{
      if (st.cache[k]) return new Response(st.cache[k], {{ status:200, headers:{{"Content-Type":"application/json","X-VSP-CACHED":"1"}} }});
      return mkJsonResponse({{ok:false, who:"VSP_POLL_GUARD", error:"BACKOFF"}}, 503);
    }}

    const last = st.last[k] || 0;

    // throttle: if too soon -> serve cache, NO network
    if ((t - last) < min && st.cache[k]) {{
      return new Response(st.cache[k], {{ status:200, headers:{{"Content-Type":"application/json","X-VSP-CACHED":"1"}} }});
    }}

    // inflight: serve cache, NO network
    if (st.inflight[k]) {{
      if (st.cache[k]) return new Response(st.cache[k], {{ status:200, headers:{{"Content-Type":"application/json","X-VSP-CACHED":"1"}} }});
      return mkJsonResponse({{ok:false, who:"VSP_POLL_GUARD", error:"INFLIGHT"}}, 503);
    }}

    st.inflight[k] = true;

    const ctrl = new AbortController();
    const timer = setTimeout(()=>ctrl.abort(), 8000);

    try {{
      const _init = Object.assign({{}}, init||{{}});
      _init.signal = ctrl.signal;
      _init.cache = "no-store";
      const r = await nativeFetch(input, _init);

      st.last[k] = t;
      if (r && r.ok) {{
        try {{
          const txt = await r.clone().text();
          if (txt && txt.length < 5_000_000) st.cache[k] = txt;
        }} catch(e){{}}
        // reset backoff after success
        st.backoffMs = 2000;
        st.nextTryAt = 0;
      }}
      return r;
    }} catch(e) {{
      const t2 = now();
      if (t2 - st.lastWarnAt > 5000) {{
        console.warn("[VSP] poll down; backoff", st.backoffMs, "ms");
        st.lastWarnAt = t2;
      }}
      st.nextTryAt = t2 + st.backoffMs;
      st.backoffMs = Math.min(st.backoffMs * 2, 60000);
      if (st.cache[k]) return new Response(st.cache[k], {{ status:200, headers:{{"Content-Type":"application/json","X-VSP-CACHED":"1"}} }});
      return mkJsonResponse({{ok:false, who:"VSP_POLL_GUARD", error:"FETCH_FAILED"}}, 503);
    }} finally {{
      clearTimeout(timer);
      st.inflight[k] = false;
    }}
  }}

  // override as early as possible
  globalThis.fetch = guardedFetch;
  window.fetch = guardedFetch;

  // guard XHR too (best effort)
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
          const k = baseKey(u);
          const t = now();
          const min = minInterval(k);
          const last = st.last[k] || 0;
          if (document && document.hidden) {{ try{{ this.abort(); }}catch(e){{}}; return; }}
          if (t < st.nextTryAt) {{ try{{ this.abort(); }}catch(e){{}}; return; }}
          if ((t-last) < min) {{ try{{ this.abort(); }}catch(e){{}}; return; }}
          if (st.inflight[k]) {{ try{{ this.abort(); }}catch(e){{}}; return; }}
        }}
      }} catch(e) {{}}
      return _send.apply(this, arguments);
    }};
  }} catch(e) {{}}
}})();
</script>
<!-- /{MARK} -->
"""

tpl_dir = Path("templates")
patched = 0
for f in tpl_dir.rglob("*.html"):
    s = f.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        continue
    if "</head>" not in s.lower():
        continue
    # insert just before </head>
    s2 = re.sub(r"</head>", INJECT + "\n</head>", s, flags=re.IGNORECASE, count=1)
    if s2 != s:
        bak = f.with_suffix(f.suffix + f".bak_pollguard_{int(time.time())}")
        bak.write_text(s, encoding="utf-8")
        f.write_text(s2, encoding="utf-8")
        patched += 1

print("[OK] patched_templates=", patched)
PY

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
