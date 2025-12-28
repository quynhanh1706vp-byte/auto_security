#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need awk; need head; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERR] $*"; }

[ -f "$W" ] || { err "missing $W"; exit 2; }
cp -f "$W" "${W}.bak_p111b_${TS}"
ok "backup: ${W}.bak_p111b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P111_TABS_MICROCACHE_V1"
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace whole block if exists
block_re = re.compile(r'(?s)# ===\s*' + re.escape(MARK) + r'\s*===.*?# ===\s*/' + re.escape(MARK) + r'\s*===\s*')
new_block = r'''
# === VSP_P111_TABS_MICROCACHE_V1 ===
# WSGI-safe micro-cache for HTML tab pages (runs/data_source/settings/rule_overrides)
# IMPORTANT: call start_response exactly ONCE.
import os, time

class _VSP_P111_TabMicroCache:
    def __init__(self, app, ttl_sec=30):
        self.app = app
        self.ttl = float(ttl_sec)
        self._cache = {}  # key -> (ts, status, headers, body)

    def __call__(self, environ, start_response):
        try:
            if os.environ.get("VSP_P111_TAB_CACHE", "1") in ("0","false","False"):
                return self.app(environ, start_response)

            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            path = environ.get("PATH_INFO", "") or ""
            qs   = environ.get("QUERY_STRING", "") or ""
            key  = path + ("?" + qs if qs else "")

            if path not in ("/runs","/data_source","/settings","/rule_overrides"):
                return self.app(environ, start_response)

            # avoid caching personalized content
            if environ.get("HTTP_COOKIE") or environ.get("HTTP_AUTHORIZATION"):
                return self.app(environ, start_response)

            if method not in ("GET","HEAD"):
                return self.app(environ, start_response)

            if (environ.get("HTTP_X_VSP_NOCACHE") == "1") or ("nocache=1" in qs) or ("cache=0" in qs):
                return self.app(environ, start_response)

            now = time.time()
            ent = self._cache.get(key)
            if ent:
                ts, status, headers, body = ent
                age = now - ts
                if age <= self.ttl:
                    hdrs = list(headers)
                    hdrs.append(("X-VSP-P111-TAB-CACHE", f"HIT; age={age:.2f}s; ttl={self.ttl:.0f}s"))
                    start_response(status, hdrs)
                    return [b""] if method == "HEAD" else [body]
                else:
                    self._cache.pop(key, None)

            captured = {"status": None, "headers": None}
            def sr_capture(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers)
                # return a dummy write callable (rarely used in modern WSGI)
                def _write(_data): return None
                return _write

            it = self.app(environ, sr_capture)

            body = b""
            if it is not None:
                for chunk in it:
                    if chunk:
                        body += chunk
                if hasattr(it, "close"):
                    try: it.close()
                    except Exception: pass

            status  = captured["status"] or "200 OK"
            headers = captured["headers"] or []

            # Cache only 200 HTML and not huge
            ctype = ""
            for k,v in headers:
                if str(k).lower() == "content-type":
                    ctype = str(v); break

            if status.startswith("200") and ("text/html" in ctype.lower()) and (len(body) <= 600_000):
                self._cache[key] = (now, status, headers, body)

            hdrs2 = list(headers)
            hdrs2.append(("X-VSP-P111-TAB-CACHE", f"MISS; ttl={self.ttl:.0f}s"))
            start_response(status, hdrs2)
            return [b""] if method == "HEAD" else [body]

        except Exception:
            return self.app(environ, start_response)

def _vsp_p111_install_tabs_microcache():
    try:
        ttl = float(os.environ.get("VSP_P111_TAB_TTL","30"))
        g = globals()
        if "application" in g and callable(g.get("application")):
            g["application"] = _VSP_P111_TabMicroCache(g["application"], ttl_sec=ttl)
            return True
        if "app" in g:
            a = g.get("app")
            if hasattr(a, "wsgi_app") and callable(getattr(a, "wsgi_app")):
                a.wsgi_app = _VSP_P111_TabMicroCache(a.wsgi_app, ttl_sec=ttl)
                return True
        return False
    except Exception:
        return False

_VSP_P111_INSTALLED = _vsp_p111_install_tabs_microcache()
# === /VSP_P111_TABS_MICROCACHE_V1 ===
'''.strip("\n")

if block_re.search(s):
    s2 = block_re.sub(new_block, s, count=1)
else:
    # append near end
    m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
    if m:
        s2 = s[:m.start()] + "\n\n" + new_block + "\n\n" + s[m.start():]
    else:
        s2 = s + "\n\n" + new_block + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched P111 block (WSGI-safe)")
PY

python3 -m py_compile "$W" >/dev/null 2>&1 || { err "py_compile failed"; exit 3; }
ok "py_compile ok"

ok "restart service: $SVC"
sudo systemctl restart "$SVC"
sleep 1

tabs=(/runs /data_source /settings /rule_overrides)

echo "== [P111b] Header check (expect X-VSP-P111-TAB-CACHE) =="
for t in "${tabs[@]}"; do
  echo "-- $t --"
  curl -fsS -D- -o /dev/null --connect-timeout 2 --max-time 12 "$BASE$t" \
    | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P111-TAB-CACHE:/{print}'
done

measure(){ curl -sS -o /dev/null --connect-timeout 2 --max-time 20 -w "%{time_total}\n" "$1" || echo 999; }
median3(){ sort -n | awk 'NR==2{print;exit}'; }

echo
echo "== [P111b] Perf measure (median of 3) =="
for t in "${tabs[@]}"; do
  echo "-- tab $t --"
  med="$( { measure "$BASE$t"; measure "$BASE$t"; measure "$BASE$t"; } | median3 )"
  echo "median_tab_sec $t $med"
done

echo
echo "Tip: set VSP_P111_TAB_TTL=30 (default). Disable cache: VSP_P111_TAB_CACHE=0"
