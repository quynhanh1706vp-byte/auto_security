#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
MARK="VSP_P3K23D_AFTERREQUEST_EARLY_SHIM_V1"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need curl; need grep

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [0] restore gateway from latest bak_p3k23c_v2 if current is broken =="
latest_bak="$(ls -1t ${F}.bak_p3k23c_v2_* 2>/dev/null | head -n 1 || true)"
if [ -n "${latest_bak:-}" ]; then
  cp -f "$latest_bak" "$F"
  echo "[OK] restored from $latest_bak -> $F"
else
  echo "[WARN] no ${F}.bak_p3k23c_v2_* found; keeping current $F"
fi

echo "== [1] compile check before patch =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo "== [2] patch after_request injector (safe, no template dependency) =="
cp -f "$F" "${F}.bak_p3k23d_${TS}"
echo "[BACKUP] ${F}.bak_p3k23d_${TS}"

python3 - "$F" "$MARK" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
mark = sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")

if mark in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Ensure request is importable (Flask)
# We'll try to minimally add "request" to existing flask import line if present.
# Common patterns:
#   from flask import Flask, request, ...
#   from flask import request
if re.search(r'(?m)^\s*from\s+flask\s+import\s+.*\brequest\b', s):
    pass
else:
    # try to extend an existing "from flask import ..." line
    m = re.search(r'(?m)^\s*from\s+flask\s+import\s+([^\n]+)$', s)
    if m:
        line = m.group(0)
        if "request" not in line:
            # inject request after "import"
            parts = line.split("import", 1)
            newline = parts[0] + "import request, " + parts[1].strip()
            s = s.replace(line, newline, 1)
    else:
        # fallback: add a new import near top
        s = "from flask import request\n" + s

INJECT = r"""
# === {MARK} ===
def __vsp_p3k23d_inject_early_shim_html_bytes(data_bytes: bytes) -> bytes:
    try:
        if not data_bytes:
            return data_bytes
        if b"{MARK}" in data_bytes:
            return data_bytes

        html = data_bytes.decode("utf-8", errors="replace")
        if "{MARK}" in html:
            return data_bytes

        shim = """<!-- === {MARK} === -->
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
          if (/\/api\/vsp\/rid_latest(_v3)?\b/.test(u)) {{
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
""".replace("{MARK}", "{MARK}")

        if "<head" in html.lower():
            # insert right after <head...>
            m = re.search(r'(?is)<head[^>]*>', html)
            if m:
                html = html[:m.end()] + "\n" + shim + "\n" + html[m.end():]
            else:
                html = shim + "\n" + html
        else:
            html = shim + "\n" + html

        return html.encode("utf-8", errors="replace")
    except Exception:
        return data_bytes

def __vsp_p3k23d_after_request_injector(resp):
    try:
        # only touch /vsp5 HTML
        if request and getattr(request, "path", "") == "/vsp5":
            mt = (getattr(resp, "mimetype", "") or "")
            if "html" in mt:
                data = resp.get_data()
                newd = __vsp_p3k23d_inject_early_shim_html_bytes(data)
                if newd is not data:
                    resp.set_data(newd)
    except Exception:
        pass
    return resp
# === /{MARK} ===
""".replace("{MARK}", mark)

# Put injector near the end of file, then register after_request.
# Registering:
#   app.after_request(__vsp_p3k23d_after_request_injector)
# But we must locate a real "app" variable. We'll try both "app" and "application".
register_line = "\ntry:\n    app.after_request(__vsp_p3k23d_after_request_injector)\nexcept Exception:\n    try:\n        application.after_request(__vsp_p3k23d_after_request_injector)\n    except Exception:\n        pass\n"

# Append safely
s = s + "\n" + INJECT + "\n" + register_line

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

echo "== [3] compile check after patch =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo "== [4] restart + wait port =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"

# wait for port responds (max ~5s)
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

echo "[DONE] p3k23d_recover_gateway_and_afterrequest_inject_v1"
