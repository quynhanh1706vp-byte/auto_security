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
cp -f "$W" "${W}.bak_p111c_${TS}"
ok "backup: ${W}.bak_p111c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P111_TABS_MICROCACHE_V1"
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

block_re = re.compile(r'(?s)# ===\s*' + re.escape(MARK) + r'\s*===.*?# ===\s*/' + re.escape(MARK) + r'\s*===\s*')

new_block = r'''
# === VSP_P111_TABS_MICROCACHE_V1 ===
# Shared micro-cache (multi gunicorn workers) for HTML shell of tab pages.
import os, time, json, hashlib

class _VSP_P111_TabSharedCache:
    def __init__(self, app, ttl_sec=30, cache_dir=None):
        self.app = app
        self.ttl = float(ttl_sec)
        self.cache_dir = cache_dir or os.environ.get("VSP_P111_TAB_CACHE_DIR", "/dev/shm/vsp_p111_tabs_cache")
        try:
            os.makedirs(self.cache_dir, exist_ok=True)
        except Exception:
            self.cache_dir = "/tmp/vsp_p111_tabs_cache"
            os.makedirs(self.cache_dir, exist_ok=True)

    def _key(self, path, qs):
        raw = (path + ("?" + qs if qs else "")).encode("utf-8", "ignore")
        return hashlib.sha1(raw).hexdigest()

    def _paths(self, key):
        return (os.path.join(self.cache_dir, key + ".json"),
                os.path.join(self.cache_dir, key + ".bin"))

    def __call__(self, environ, start_response):
        try:
            if os.environ.get("VSP_P111_TAB_CACHE", "1") in ("0","false","False"):
                return self.app(environ, start_response)

            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            path   = environ.get("PATH_INFO", "") or ""
            qs     = environ.get("QUERY_STRING", "") or ""

            if path not in ("/runs","/data_source","/settings","/rule_overrides"):
                return self.app(environ, start_response)

            # do not cache personalized content
            if environ.get("HTTP_COOKIE") or environ.get("HTTP_AUTHORIZATION"):
                return self.app(environ, start_response)

            if method not in ("GET","HEAD"):
                return self.app(environ, start_response)

            if (environ.get("HTTP_X_VSP_NOCACHE") == "1") or ("nocache=1" in qs) or ("cache=0" in qs):
                return self.app(environ, start_response)

            now = time.time()
            ttl = float(os.environ.get("VSP_P111_TAB_TTL", str(int(self.ttl))))
            key = self._key(path, qs)
            meta_p, body_p = self._paths(key)

            # HIT (shared)
            try:
                if os.path.isfile(meta_p) and os.path.isfile(body_p):
                    meta = json.loads(open(meta_p, "r", encoding="utf-8").read())
                    ts = float(meta.get("ts", 0.0))
                    age = now - ts
                    if age <= ttl:
                        status = meta.get("status", "200 OK")
                        headers = meta.get("headers", [])
                        body = open(body_p, "rb").read()
                        hdrs = list(headers)
                        hdrs.append(("Cache-Control", "no-store"))
                        hdrs.append(("X-VSP-P111-TAB-CACHE", f"HIT-SHARED; age={age:.2f}s; ttl={ttl:.0f}s; pid={os.getpid()}"))
                        start_response(status, hdrs)
                        return [b""] if method == "HEAD" else [body]
            except Exception:
                pass

            # MISS: capture downstream (do NOT call start_response here)
            captured = {"status": None, "headers": None}
            def sr_capture(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers)
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

            # cache only 200 HTML + not huge
            ctype = ""
            for k,v in headers:
                if str(k).lower() == "content-type":
                    ctype = str(v); break
            cacheable = status.startswith("200") and ("text/html" in (ctype or "").lower()) and (len(body) <= 600_000)

            if cacheable:
                try:
                    os.makedirs(self.cache_dir, exist_ok=True)
                    tmp_meta = meta_p + ".tmp"
                    tmp_body = body_p + ".tmp"
                    with open(tmp_body, "wb") as f:
                        f.write(body)
                    meta = {"ts": now, "status": status, "headers": headers}
                    with open(tmp_meta, "w", encoding="utf-8") as f:
                        f.write(json.dumps(meta, ensure_ascii=False))
                    os.replace(tmp_body, body_p)
                    os.replace(tmp_meta, meta_p)
                except Exception:
                    pass

            hdrs2 = list(headers)
            hdrs2.append(("Cache-Control", "no-store"))
            hdrs2.append(("X-VSP-P111-TAB-CACHE", f"MISS; ttl={ttl:.0f}s; pid={os.getpid()}"))
            start_response(status, hdrs2)
            return [b""] if method == "HEAD" else [body]

        except Exception:
            return self.app(environ, start_response)

def _vsp_p111_install_tabs_shared_cache():
    try:
        ttl = float(os.environ.get("VSP_P111_TAB_TTL","30"))
        g = globals()
        if "application" in g and callable(g.get("application")):
            g["application"] = _VSP_P111_TabSharedCache(g["application"], ttl_sec=ttl)
            return True
        if "app" in g:
            a = g.get("app")
            if hasattr(a, "wsgi_app") and callable(getattr(a, "wsgi_app")):
                a.wsgi_app = _VSP_P111_TabSharedCache(a.wsgi_app, ttl_sec=ttl)
                return True
        return False
    except Exception:
        return False

_VSP_P111_INSTALLED = _vsp_p111_install_tabs_shared_cache()
# === /VSP_P111_TABS_MICROCACHE_V1 ===
'''.strip("\n")

if block_re.search(s):
    s2 = block_re.sub(new_block, s, count=1)
else:
    m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
    s2 = (s[:m.start()] + "\n\n" + new_block + "\n\n" + s[m.start():]) if m else (s + "\n\n" + new_block + "\n")

p.write_text(s2, encoding="utf-8")
print("[OK] patched P111 -> shared cache (multi-worker stable)")
PY

python3 -m py_compile "$W" >/dev/null 2>&1 || { err "py_compile failed"; exit 3; }
ok "py_compile ok"

ok "restart service: $SVC"
sudo systemctl restart "$SVC"
sleep 1

tabs=(/runs /data_source /settings /rule_overrides)

echo "== [P111c] Warm once (populate shared cache) =="
for t in "${tabs[@]}"; do
  curl -fsS -o /dev/null --connect-timeout 2 --max-time 20 "$BASE$t" || true
done

echo "== [P111c] Header check (expect HIT-SHARED) =="
for t in "${tabs[@]}"; do
  echo "-- $t --"
  curl -fsS -D- -o /dev/null --connect-timeout 2 --max-time 12 "$BASE$t" \
    | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P111-TAB-CACHE:/{print}'
done

echo
echo "== [P111c] Perf quick loop (8 hits each) =="
for t in "${tabs[@]}"; do
  echo "== $t =="
  for i in 1 2 3 4 5 6 7 8; do
    curl -sS -o /dev/null --connect-timeout 2 --max-time 20 -w "t=%{time_total}\n" "$BASE$t"
  done
done

echo
echo "Tip: shared cache dir: /dev/shm/vsp_p111_tabs_cache (fallback /tmp). TTL: VSP_P111_TAB_TTL=30"
