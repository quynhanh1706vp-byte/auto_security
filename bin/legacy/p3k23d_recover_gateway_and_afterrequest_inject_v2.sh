#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
MARK="VSP_P3K23D_AFTERREQUEST_EARLY_SHIM_V2"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need curl; need grep; need ls; need head

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [0] restore gateway from latest bak_p3k23c_v2 if exists =="
latest_bak="$(ls -1t ${F}.bak_p3k23c_v2_* 2>/dev/null | head -n 1 || true)"
if [ -n "${latest_bak:-}" ]; then
  cp -f "$latest_bak" "$F"
  echo "[OK] restored from $latest_bak -> $F"
else
  echo "[WARN] no ${F}.bak_p3k23c_v2_* found; keeping current $F"
fi

echo "== [1] compile check before patch =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo "== [2] patch after_request injector (NO nested quotes) =="
cp -f "$F" "${F}.bak_p3k23d_v2_${TS}"
echo "[BACKUP] ${F}.bak_p3k23d_v2_${TS}"

python3 - "$F" "$MARK" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
mark = sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")

if mark in s:
    print("[OK] already patched")
    raise SystemExit(0)

# ensure flask.request import
if not re.search(r'(?m)^\s*from\s+flask\s+import\s+.*\brequest\b', s):
    m = re.search(r'(?m)^\s*from\s+flask\s+import\s+([^\n]+)$', s)
    if m:
        line = m.group(0)
        if "request" not in line:
            parts = line.split("import", 1)
            newline = parts[0] + "import request, " + parts[1].strip()
            s = s.replace(line, newline, 1)
    else:
        s = "from flask import request\n" + s

shim_html = f"""<!-- === {mark} === -->
<script>
(function(){{
  try{{
    if (window.__VSP_EARLY_SAFE_SHIM__) return;
    window.__VSP_EARLY_SAFE_SHIM__ = true;

    function _s(x){{ try{{ return String((x && (x.message||x)) || x || ""); }}catch(e){{ return ""; }} }}
    function _isNoise(x){{ const s=_s(x); return /timeout|AbortError|NS_BINDING_ABORTED|NetworkError/i.test(s); }}

    window.addEventListener('unhandledrejection', function(ev){{
      try{{ if (_isNoise(ev && ev.reason)) {{ ev.preventDefault(); return; }} }}catch(e){{}}
    }});

    window.addEventListener('error', function(ev){{
      try{{
        const msg = ev && (ev.message || (ev.error && ev.error.message) || ev.error);
        if (_isNoise(msg)) {{ ev.preventDefault(); return true; }}
      }}catch(e){{}}
    }}, true);

    const sp = new URLSearchParams(location.search || "");
    const urlRid = sp.get("rid") || "";

    // If ?rid= exists => never call rid_latest* (return url rid immediately)
    if (urlRid && window.fetch && !window.__VSP_EARLY_FETCH_SHIM__){{
      const _fetch = window.fetch.bind(window);
      window.fetch = function(input, init){{
        try{{
          const u = (typeof input === "string") ? input : (input && input.url) || "";
          if (/\\/api\\/vsp\\/rid_latest(_v3)?\\b/.test(u)) {{
            const body = JSON.stringify({{ok:true, rid:urlRid, mode:"url"}});
            return Promise.resolve(new Response(body, {{status:200, headers: {{"Content-Type":"application/json"}}}}));
          }}
        }}catch(e){{}}
        return _fetch(input, init).catch(function(e){{
          if (_isNoise(e)) return new Response("{{}}", {{status:200, headers: {{"Content-Type":"application/json"}}}});
          throw e;
        }});
      }};
      window.__VSP_EARLY_FETCH_SHIM__ = true;
    }}
  }}catch(e){{}}
}})();
</script>
"""

inject_block = f"""
# === {mark} ===
_VSP_EARLY_SHIM_HTML_{mark} = {repr(shim_html)}

def __vsp_{mark}_inject(resp):
    try:
        # only touch /vsp5 HTML
        if request and getattr(request, "path", "") == "/vsp5":
            mt = (getattr(resp, "mimetype", "") or "")
            if "html" in mt:
                html = resp.get_data(as_text=True) or ""
                if "{mark}" not in html:
                    import re as __re
                    m = __re.search(r'(?is)<head[^>]*>', html)
                    if m:
                        html = html[:m.end()] + "\\n" + _VSP_EARLY_SHIM_HTML_{mark} + "\\n" + html[m.end():]
                    else:
                        html = _VSP_EARLY_SHIM_HTML_{mark} + "\\n" + html
                    resp.set_data(html)
    except Exception:
        pass
    return resp

try:
    app.after_request(__vsp_{mark}_inject)
except Exception:
    try:
        application.after_request(__vsp_{mark}_inject)
    except Exception:
        pass
# === /{mark} ===
"""

s = s + "\n" + inject_block
p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

echo "== [3] compile check after patch =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo "== [4] restart + wait healthz =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"

for i in 1 2 3 4 5; do
  if curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1; then
    echo "[OK] healthz reachable"
    break
  fi
  sleep 1
done

echo "== [5] smoke: marker must appear in served /vsp5 HTML =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print((json.load(sys.stdin) or {}).get("rid",""))' 2>/dev/null || true)"
[ -n "${RID:-}" ] || RID="VSP_CI_20251219_092640"

curl -fsS "$BASE/vsp5?rid=$RID" | grep -n "$MARK" | head -n 3 && echo "[OK] marker present in /vsp5 HTML" || {
  echo "[FAIL] marker missing in /vsp5 HTML"
  exit 2
}

echo "[DONE] p3k23d_recover_gateway_and_afterrequest_inject_v2"
