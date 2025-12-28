#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need node; need date; need sudo; need systemctl; need find; need sort

JS_DIR="static/js"
[ -d "$JS_DIR" ] || { echo "[ERR] missing $JS_DIR"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

# Find all variants that start with vsp_runs_tab_resolv (resolve/resolved + timestamp)
mapfile -t FILES < <(find "$JS_DIR" -maxdepth 1 -type f -name 'vsp_runs_tab_resolv*.js' -print | sort -u)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[ERR] no runs-tab js files found under $JS_DIR (pattern vsp_runs_tab_resolv*.js)"
  exit 2
fi

echo "[INFO] files=${#FILES[@]} TS=$TS"
printf '%s\n' "${FILES[@]}" | sed 's/^/[FILE] /'

# Backup
for f in "${FILES[@]}"; do
  cp -f "$f" "$f.bak_killspam_${TS}"
done
echo "[OK] backups done (*.bak_killspam_${TS})"

PATCHER="/tmp/vsp_patch_runs_js_killspam_${TS}.py"
cat > "$PATCHER" <<'PY'
from pathlib import Path
import re, sys

MARK="VSP_P1_KILL_RED_SPAM_FETCH_XHR_V3"

INJECT = f"""// {MARK}
(function(){{
  if (window.__VSP_GUARDED_POLL) return;
  window.__VSP_GUARDED_POLL = true;

  const nativeFetch = (window.fetch ? window.fetch.bind(window) : null);
  const st = {{ inflight:false, backoffMs:2000, nextTryAt:0, lastWarnAt:0 }};

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

    if (u.includes("/api/vsp/run_file")) return false;
    if (u.includes("/api/vsp/run_file2")) return false;
    if (u.includes("/api/vsp/export_")) return false;
    if (u.includes("/api/vsp/sha256")) return false;

    if (u.includes("/api/vsp/runs")) return true;
    if (u.includes("/api/vsp/dashboard")) return true; // dashboard_commercial_v2 etc.
    return false;
  }}

  window.__VSP_GUARDED_FETCH = async function(input, init){{
    const u = urlStr(input);
    if (!nativeFetch || !shouldGuard(u)){{
      return nativeFetch ? nativeFetch(input, init) : mkJsonResponse({{ok:false,error:"NO_FETCH"}},503);
    }}

    const now = Date.now();
    if (now < st.nextTryAt) {{
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
      const r = await nativeFetch(input, _init);
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

  // Guard XHR too
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

FETCH_RE = re.compile(r'(?<![\w$])fetch\s*\(')  # <-- REGEX ĐÚNG, KHÔNG ESCAPE BẬY

def patch_one(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        return "already"

    s = INJECT + "\n" + s

    # replace fetch( to guarded fetch (best effort)
    s = FETCH_RE.sub('window.__VSP_GUARDED_FETCH(', s)
    s = s.replace('window.fetch(', 'window.__VSP_GUARDED_FETCH(')
    s = s.replace('globalThis.fetch(', 'window.__VSP_GUARDED_FETCH(')

    fp.write_text(s, encoding="utf-8")
    return "patched"

for f in sys.argv[1:]:
    fp = Path(f)
    print(fp.name, patch_one(fp))
PY

python3 "$PATCHER" "${FILES[@]}"

for f in "${FILES[@]}"; do
  node --check "$f" >/dev/null
done
echo "[OK] node --check OK for all"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
