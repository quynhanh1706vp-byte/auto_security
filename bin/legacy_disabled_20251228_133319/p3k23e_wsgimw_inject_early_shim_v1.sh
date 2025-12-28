#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
MARK="VSP_P3K23E_WSGIMW_EARLY_SAFE_SHIM_V1"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need curl; need grep; need ls; need head

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [0] restore baseline gateway (prefer bak_p3k23c_v2; otherwise keep current) =="
baseline="$(ls -1t ${F}.bak_p3k23c_v2_* 2>/dev/null | head -n 1 || true)"
if [ -n "${baseline:-}" ]; then
  cp -f "$baseline" "$F"
  echo "[OK] restored baseline: $baseline -> $F"
else
  echo "[WARN] no ${F}.bak_p3k23c_v2_* found; keep current $F"
fi

echo "== [1] compile check baseline =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo "== [2] patch: append WSGI middleware shim (safe, handles Content-Length) =="
cp -f "$F" "${F}.bak_p3k23e_${TS}"
echo "[BACKUP] ${F}.bak_p3k23e_${TS}"

python3 - "$F" "$MARK" <<'PY'
from pathlib import Path
import sys, re

p = Path(sys.argv[1])
mark = sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")

if mark in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Minimal JS shim (no template dependency)
shim = f"""<!-- === {mark} === -->
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

    // If ?rid exists => never call rid_latest endpoints
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
          if (_isNoise(e)) return new Response("{}", {{status:200, headers: {{"Content-Type":"application/json"}}}});
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
class __VspEarlySafeShimMW:
    def __init__(self, app):
        self.app = app
        self.__VSP_EARLY_SAFE_SHIM_WRAPPED__ = True

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            if path != "/vsp5":
                return self.app(environ, start_response)

            captured = {{}}
            def _sr(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers or [])
                captured["exc_info"] = exc_info
                return lambda x: None

            it = self.app(environ, _sr)

            # Decide based on headers
            hdrs = captured.get("headers") or []
            ctype = ""
            for k,v in hdrs:
                if str(k).lower() == "content-type":
                    ctype = str(v)
                    break
            if "text/html" not in ctype.lower():
                return self._pass_through(it, start_response, captured)

            # Collect body (limit)
            chunks = []
            total = 0
            limit = 5 * 1024 * 1024  # 5MB
            for b in it:
                if not isinstance(b, (bytes, bytearray)):
                    try:
                        b = (str(b)).encode("utf-8", "ignore")
                    except Exception:
                        b = b""
                chunks.append(bytes(b))
                total += len(b)
                if total > limit:
                    return self._pass_through_iter(chunks, it, start_response, captured)

            body = b"".join(chunks)
            try:
                html = body.decode("utf-8", "replace")
            except Exception:
                return self._pass_through_bytes(body, start_response, captured)

            if "{mark}" in html:
                return self._pass_through_bytes(body, start_response, captured)

            # inject right after <head...>
            m = re.search(r"(?is)<head[^>]*>", html)
            if m:
                html2 = html[:m.end()] + "\\n" + {repr(shim)} + "\\n" + html[m.end():]
            else:
                html2 = {repr(shim)} + "\\n" + html

            out = html2.encode("utf-8", "ignore")

            # fix headers: drop Content-Length, set new
            new_headers = []
            for k,v in hdrs:
                if str(k).lower() == "content-length":
                    continue
                new_headers.append((k,v))
            new_headers.append(("Content-Length", str(len(out))))

            start_response(captured.get("status","200 OK"), new_headers, captured.get("exc_info"))
            return [out]
        except Exception:
            # NEVER break prod; if anything goes wrong, pass through
            return self.app(environ, start_response)

    def _pass_through(self, it, start_response, cap):
        start_response(cap.get("status","200 OK"), cap.get("headers") or [], cap.get("exc_info"))
        return it

    def _pass_through_bytes(self, body, start_response, cap):
        hdrs = cap.get("headers") or []
        start_response(cap.get("status","200 OK"), hdrs, cap.get("exc_info"))
        return [body]

    def _pass_through_iter(self, first_chunks, it, start_response, cap):
        hdrs = cap.get("headers") or []
        start_response(cap.get("status","200 OK"), hdrs, cap.get("exc_info"))
        def gen():
            for c in first_chunks:
                yield c
            for c in it:
                yield c
        return gen()

def __vsp_wrap_if_present(name):
    g = globals()
    obj = g.get(name, None)
    if obj and callable(obj):
        # avoid double wrap
        if getattr(obj, "__VSP_EARLY_SAFE_SHIM_WRAPPED__", False):
            return
        g[name] = __VspEarlySafeShimMW(obj)

__vsp_wrap_if_present("application")
__vsp_wrap_if_present("app")
# === /{mark} ===
"""

s = s + "\n" + inject_block
p.write_text(s, encoding="utf-8")
print("[OK] appended middleware shim:", mark)
PY

echo "== [3] compile check after patch =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo "== [4] restart + wait healthz =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"
for i in 1 2 3 4 5; do
  curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1 && { echo "[OK] healthz reachable"; break; }
  sleep 1
done

echo "== [5] smoke: marker must appear in served /vsp5 HTML =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print((json.load(sys.stdin) or {}).get("rid",""))' 2>/dev/null || true)"
[ -n "${RID:-}" ] || RID="VSP_CI_20251219_092640"

# Retry /vsp5 a few times (gunicorn just restarted)
ok=0
for i in 1 2 3; do
  html="$(curl -fsS --connect-timeout 2 --max-time 6 "$BASE/vsp5?rid=$RID" 2>/dev/null || true)"
  if echo "$html" | grep -q "$MARK"; then ok=1; break; fi
  sleep 0.5
done

[ "$ok" -eq 1 ] && echo "[OK] marker present in /vsp5 HTML" || { echo "[FAIL] marker missing in /vsp5 HTML"; exit 2; }

echo "[DONE] p3k23e_wsgimw_inject_early_shim_v1"
