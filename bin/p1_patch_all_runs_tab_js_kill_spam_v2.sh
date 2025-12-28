#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need node; need date; need sudo; need systemctl; need ls

JS_DIR="static/js"
[ -d "$JS_DIR" ] || { echo "[ERR] missing $JS_DIR"; exit 2; }

# Collect files: stable + timestamped resolve variants
mapfile -t FILES < <(
  ls -1 "$JS_DIR"/vsp_runs_tab_resolved_v1.js 2>/dev/null || true
  ls -1 "$JS_DIR"/vsp_runs_tab_resolve*.js 2>/dev/null || true
)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[ERR] no runs-tab js files found under $JS_DIR"
  exit 2
fi

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] files=${#FILES[@]} TS=$TS"
printf '%s\n' "${FILES[@]}" | sed 's/^/[FILE] /'

# Backup
for f in "${FILES[@]}"; do
  cp -f "$f" "$f.bak_killspam_${TS}"
done
echo "[OK] backups done (*.bak_killspam_${TS})"

# Write patcher python file (avoid here-doc breakage)
PATCHER="/tmp/vsp_patch_runs_js_killspam_${TS}.py"
cat > "$PATCHER" <<'PY'
from pathlib import Path
import re, sys

MARK="VSP_P1_KILL_RED_SPAM_FETCH_XHR_V2"

INJECT = f"""// {MARK}
(function(){{
  if (window.__VSP_GUARDED_POLL) return;
  window.__VSP_GUARDED_POLL = true;

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

    // never guard download/export/sha endpoints
    if (u.includes("/api/vsp/run_file")) return false;
    if (u.includes("/api/vsp/run_file2")) return false;
    if (u.includes("/api/vsp/export_")) return false;
    if (u.includes("/api/vsp/sha256")) return false;

    // guard polling endpoints
    if (u.includes("/api/vsp/runs")) return true;
    if (u.includes("/api/vsp/dashboard")) return true;  // includes dashboard_commercial_v2
    return false;
  }}

  window.__VSP_GUARDED_FETCH = async function(input, init){{
    const u = urlStr(input);
    if (!nativeFetch || !shouldGuard(u)){{
      return nativeFetch ? nativeFetch(input, init) : mkJsonResponse({{ok:false,error:"NO_FETCH"}},503);
    }}

    const now = Date.now();
    if (now < st.nextTryAt){{
      // no network call => no red spam
      return mkJsonResponse({{ok:false, who:"VSP_GUARDED_FETCH", error:"BACKOFF"}}, 503);
    }}
    if (st.inflight){{
      return mkJsonResponse({{ok:false, who:"VSP_GUARDED_FETCH", error:"INFLIGHT"}}, 503);
    }}

    st.inflight = true;
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), 8000);

    try {{
      const _init = Object.assign({{}}, init||{{}});
      _init.signal = ctrl.signal;
      _init.cache = "no-store";
      const r = await nativeFetch(input, _init);

      st.backoffMs = 2000;
      st.nextTryAt = 0;
      return r;
    }} catch(e) {{
      const n2 = Date.now();
      if (n2 - st.lastWarnAt > 5000){{
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

  // Guard XHR as well (Log XMLHttpRequests shows these)
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
            // no network call
            const self=this;
            setTimeout(function(){{ try{{ self.abort(); }}catch(e){{}} }}, 0);
            return;
          }}
        }}
      }} catch(e) {{}}
      return _send.apply(this, arguments);
    }};
  }} catch(e) {{}}
}})();
"""

def patch_one(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        return "already"
    s = INJECT + "\n" + s

    # replace fetch() usage to guarded fetch (best-effort)
    s = re.sub(r'(?<![\\w$])fetch\\s*\\(', 'window.__VSP_GUARDED_FETCH(', s)
    s = s.replace('window.fetch(', 'window.__VSP_GUARDED_FETCH(')
    s = s.replace('globalThis.fetch(', 'window.__VSP_GUARDED_FETCH(')

    fp.write_text(s, encoding="utf-8")
    return "patched"

paths = [Path(x) for x in sys.argv[1:]]
for fp in paths:
    print(fp.name, patch_one(fp))
PY

python3 "$PATCHER" "${FILES[@]}"

# JS syntax check
for f in "${FILES[@]}"; do
  node --check "$f" >/dev/null
done
echo "[OK] node --check OK for all"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
