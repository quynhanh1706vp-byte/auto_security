#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_global_shims_commercial_p0_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F (global shim)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_THROTTLE_DASHBOARD_EXTRAS_P0_V2"
cp -f "$F" "$F.bak_${MARK}_${TS}" && echo "[BACKUP] $F.bak_${MARK}_${TS}"

python3 - "$F" "$MARK" <<'PY'
from pathlib import Path
import sys, re

p = Path(sys.argv[1])
mark = sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")
if mark in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert state + helper right after "const _fetch = ..." block
anchor = r"const _fetch\s*=\s*window\.fetch[^\n]*\n"
m = re.search(anchor, s)
if not m:
    print("[ERR] cannot find _fetch assignment in shim")
    raise SystemExit(2)

insert_pos = m.end()

state = f"""
  // {mark}: throttle + cache + cooldown for dashboard extras to avoid spam ERR_NETWORK_CHANGED
  let __vsp_extras_cache_text = '';
  let __vsp_extras_cache_ts = 0;
  let __vsp_extras_last_try = 0;
  let __vsp_extras_last_fail = 0;
  let __vsp_extras_inflight = null;

  function __vsp_resp_json(text, status=200){{
    try {{
      return new Response(text || '{{}}', {{
        status: status,
        headers: {{'content-type':'application/json; charset=utf-8'}}
      }});
    }} catch(_e) {{
      // older browsers fallback
      return new Response(text || '{{}}');
    }}
  }}

  async function __vsp_fetch_extras_with_cache(url, init){{
    const now = Date.now();
    const THROTTLE_MS = 10_000;   // 1 req / 10s
    const COOLDOWN_MS = 30_000;   // after fail, skip 30s
    const CACHE_OK_MS = 120_000;  // serve cache up to 2 min

    // if hidden -> prefer cache (avoid background spam)
    if (document.hidden && (now - __vsp_extras_cache_ts) < CACHE_OK_MS && __vsp_extras_cache_text) {{
      return __vsp_resp_json(__vsp_extras_cache_text, 200);
    }}

    // cooldown after fail
    if ((now - __vsp_extras_last_fail) < COOLDOWN_MS) {{
      if (__vsp_extras_cache_text) return __vsp_resp_json(__vsp_extras_cache_text, 200);
      return __vsp_resp_json('{{}}', 200);
    }}

    // throttle
    if ((now - __vsp_extras_last_try) < THROTTLE_MS) {{
      if (__vsp_extras_cache_text) return __vsp_resp_json(__vsp_extras_cache_text, 200);
      return __vsp_resp_json('{{}}', 200);
    }}

    __vsp_extras_last_try = now;

    // de-dup inflight
    if (__vsp_extras_inflight) {{
      const t = await __vsp_extras_inflight;
      return __vsp_resp_json(t, 200);
    }}

    __vsp_extras_inflight = (async () => {{
      try {{
        const r = await _fetch(url, init);
        const t = await r.text();
        if (r && r.ok) {{
          __vsp_extras_cache_text = t || '{{}}';
          __vsp_extras_cache_ts = Date.now();
        }}
        return (t || '{{}}');
      }} catch(_e) {{
        __vsp_extras_last_fail = Date.now();
        return (__vsp_extras_cache_text || '{{}}');
      }} finally {{
        __vsp_extras_inflight = null;
      }}
    }})();

    const txt = await __vsp_extras_inflight;
    return __vsp_resp_json(txt, 200);
  }}
"""

s2 = s[:insert_pos] + state + s[insert_pos:]

# Patch inside window.fetch wrapper: early-handle dashboard_v3_extras_v1
pat = r"window\.fetch\s*=\s*async\s*function\s*\(\s*input\s*,\s*init\s*\)\s*\{\s*"
m2 = re.search(pat, s2)
if not m2:
    print("[ERR] cannot find window.fetch wrapper in shim")
    raise SystemExit(3)

pos2 = m2.end()

hook = f"""
      // {mark}: intercept dashboard extras first (avoid repeated failed XHR spam)
      if (url && url.includes('/api/vsp/dashboard_v3_extras_v1')) {{
        return await __vsp_fetch_extras_with_cache(url, init);
      }}
"""

# Insert hook after url extraction line if possible
# Find "const url =" within first ~25 lines after wrapper start
chunk = s2[pos2:pos2+2000]
murl = re.search(r"const\s+url\s*=\s*\([^\n]+\)\s*;\s*\n", chunk)
if murl:
    ip = pos2 + murl.end()
    s3 = s2[:ip] + hook + s2[ip:]
else:
    s3 = s2[:pos2] + hook + s2[pos2:]

p.write_text(s3, encoding="utf-8")
print("[OK] patched:", p)
PY

node --check "$F" >/dev/null && echo "[OK] node --check $F"
echo "DONE. Ctrl+Shift+R lại, mở #dashboard, xem console còn ERR_NETWORK_CHANGED không."
