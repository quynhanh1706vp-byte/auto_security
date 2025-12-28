#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need awk; need sort; need head

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERR] $*"; }

[ -f "$W" ] || { err "missing $W"; exit 2; }

cp -f "$W" "${W}.bak_p111_${TS}"
ok "backup: ${W}.bak_p111_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P111_TABS_MICROCACHE_V1"
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if MARK in s:
    print("[OK] marker found: already patched")
    raise SystemExit(0)

patch = r'''
# === __MARK__ ===
# Micro-cache for HTML tab pages (runs/data_source/settings/rule_overrides)
# Goal: tab HTML must be fast like /vsp5 (avoid heavy IO per request).
import time

class _VSP_P111_TabMicroCache:
    def __init__(self, app, ttl_sec=30):
        self.app = app
        self.ttl = float(ttl_sec)
        self._cache = {}  # key -> (ts, status, headers, body)

    def __call__(self, environ, start_response):
        try:
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            path = environ.get("PATH_INFO", "") or ""
            qs = environ.get("QUERY_STRING", "") or ""
            key = path + ("?" + qs if qs else "")

            # Only cache exact tab pages (HTML shell)
            if path not in ("/runs","/data_source","/settings","/rule_overrides"):
                return self.app(environ, start_response)

            # Safety: do not cache if cookies/auth present
            if environ.get("HTTP_COOKIE") or environ.get("HTTP_AUTHORIZATION"):
                return self.app(environ, start_response)

            if method not in ("GET","HEAD"):
                return self.app(environ, start_response)

            # allow disabling runtime
            if (environ.get("HTTP_X_VSP_NOCACHE") == "1") or (("nocache=1" in qs) or ("cache=0" in qs)):
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
            def _sr(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers)
                return start_response(status, headers, exc_info)

            it = self.app(environ, _sr)
            body = b"".join(it) if it is not None else b""
            if hasattr(it, "close"):
                try: it.close()
                except Exception: pass

            status = captured["status"] or "200 OK"
            headers = captured["headers"] or []

            # Cache only 200 HTML with reasonable size
            ctype = ""
            for k,v in headers:
                if str(k).lower() == "content-type":
                    ctype = str(v); break

            if status.startswith("200") and ("text/html" in ctype.lower()) and (len(body) <= 600_000):
                self._cache[key] = (now, status, headers, body)

            # Always add MISS marker
            hdrs2 = list(headers)
            hdrs2.append(("X-VSP-P111-TAB-CACHE", f"MISS; ttl={self.ttl:.0f}s"))
            start_response(status, hdrs2)
            return [b""] if method == "HEAD" else [body]

        except Exception:
            return self.app(environ, start_response)

def _vsp_p111_install_tabs_microcache():
    try:
        g = globals()
        # Wrap exported WSGI entry first
        if "application" in g and callable(g.get("application")):
            g["application"] = _VSP_P111_TabMicroCache(g["application"], ttl_sec=float(os.environ.get("VSP_P111_TAB_TTL","30")))
            return True
        # Flask app: wrap wsgi_app
        if "app" in g:
            a = g.get("app")
            if hasattr(a, "wsgi_app") and callable(getattr(a, "wsgi_app")):
                a.wsgi_app = _VSP_P111_TabMicroCache(a.wsgi_app, ttl_sec=float(os.environ.get("VSP_P111_TAB_TTL","30")))
                return True
        return False
    except Exception:
        return False

# Install after other wrappers (safe)
try:
    import os
    _VSP_P111_INSTALLED = _vsp_p111_install_tabs_microcache()
except Exception:
    _VSP_P111_INSTALLED = False
# === /__MARK__ ===
'''.strip("\n").replace("__MARK__", MARK)

m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m:
    s2 = s[:m.start()] + "\n\n" + patch + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + patch + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched wsgi_vsp_ui_gateway.py (P111 installed)")
PY

python3 -m py_compile "$W" >/dev/null 2>&1 || { err "py_compile failed"; exit 3; }
ok "py_compile ok"

if command -v systemctl >/dev/null 2>&1 && systemctl status "$SVC" >/dev/null 2>&1; then
  ok "restart service: $SVC"
  sudo systemctl restart "$SVC"
  sleep 1
else
  warn "skip restart (no systemctl or service not found): $SVC"
fi

measure(){ curl -sS -o /dev/null --connect-timeout 2 --max-time 20 -w "%{time_total}\n" "$1" || echo 999; }
median3(){ sort -n | awk 'NR==2{print;exit}'; }

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "== [P111] Header check (expect X-VSP-P111-TAB-CACHE) =="
for t in "${tabs[@]}"; do
  echo "-- $t --"
  curl -fsS -D- -o /dev/null --connect-timeout 2 --max-time 12 "$BASE$t" \
    | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P111-TAB-CACHE:/{print}'
done

echo
echo "== [P111] Perf measure (median of 3) =="
tab_meds=()
for t in "${tabs[@]}"; do
  echo "-- tab $t --"
  med="$( { measure "$BASE$t"; measure "$BASE$t"; measure "$BASE$t"; } | median3 )"
  echo "median_tab_sec $t $med"
  tab_meds+=("$med")
done
tab_overall="$(printf "%s\n" "${tab_meds[@]}" | median3)"
echo "[STAT] tab_overall_median_sec=$tab_overall"

verdict_tabs="$(python3 - <<PY
t=float("$tab_overall")
print("GREEN" if t<=1.0 else ("AMBER" if t<=2.0 else "RED"))
PY
)"
echo
echo "== [P111] VERDICT =="
echo "tabs: $verdict_tabs (median=${tab_overall}s)"
