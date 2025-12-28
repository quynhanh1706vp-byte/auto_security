#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_sha256_fallback_${TS}"
echo "[BACKUP] ${F}.bak_sha256_fallback_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_SHA256_FALLBACK_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# We patch by wrapping a helper at EOF that intercepts sha256 route via WSGI middleware (last layer),
# similar to runs MW, but only for /api/vsp/sha256.
block = r'''
# ==== VSP_P1_SHA256_FALLBACK_V1 ====
def _vsp__sha256_hex(path):
    import hashlib
    h=hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()

def _vsp__qs_get(environ, key):
    qs = environ.get("QUERY_STRING") or ""
    for part in qs.split("&"):
        if part.startswith(key + "="):
            return part.split("=",1)[1]
    return ""

def _vsp__safe_unquote(s):
    try:
        from urllib.parse import unquote_plus
        return unquote_plus(s)
    except Exception:
        return s

class _VSPSha256FallbackWSGIMW:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        if path != "/api/vsp/sha256":
            return self.app(environ, start_response)

        # Let downstream handler try first; if it returns 404, we attempt fallback.
        captured = {"status": None, "headers": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            return None

        body_iter = self.app(environ, _sr)
        try:
            body = b"".join(body_iter)
        except Exception:
            return self.app(environ, start_response)

        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []
        try:
            code = int(status.split()[0])
        except Exception:
            code = 200

        if code != 404:
            start_response(status, headers)
            return [body]

        # fallback compute sha256 if possible
        import os
        from pathlib import Path as _P

        rid = _vsp__safe_unquote(_vsp__qs_get(environ, "rid"))
        name = _vsp__safe_unquote(_vsp__qs_get(environ, "name"))

        # basic guard
        if not rid or not name:
            start_response(status, headers)
            return [body]

        # candidate names
        cands = [name]
        # common fallbacks: reports/x -> x
        if name.startswith("reports/"):
            cands.append(name[len("reports/"):])

        # try to resolve within known roots used by runs listing
        roots = []
        env_roots = (os.environ.get("VSP_RUNS_ROOTS") or "").strip()
        if env_roots:
            roots = [x.strip() for x in env_roots.split(":") if x.strip()]
        else:
            roots = ["/home/test/Data/SECURITY_BUNDLE/out", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]

        found = None
        found_rel = None
        for r in roots:
            base = _P(r) / rid
            if not base.exists():
                continue
            for rel in cands:
                fp = base / rel
                if fp.exists() and fp.is_file():
                    found = fp
                    found_rel = rel
                    break
            if found:
                break

        if not found:
            start_response(status, headers)
            return [body]

        try:
            digest = _vsp__sha256_hex(str(found))
            import json
            out = json.dumps({"ok": True, "rid": rid, "name": name, "resolved": found_rel, "sha256": digest}, ensure_ascii=False).encode("utf-8")
            new_headers=[]
            for k,v in headers:
                if k.lower() in ("content-length","content-type"):
                    continue
                new_headers.append((k,v))
            new_headers.append(("Content-Type","application/json; charset=utf-8"))
            new_headers.append(("Content-Length", str(len(out))))
            new_headers.append(("X-VSP-SHA256-FALLBACK", found_rel or ""))
            start_response("200 OK", new_headers)
            return [out]
        except Exception:
            start_response(status, headers)
            return [body]

try:
    if "application" in globals() and not getattr(application, "__vsp_sha256_fallback_wrapped__", False):
        application = _VSPSha256FallbackWSGIMW(application)
        try:
            application.__vsp_sha256_fallback_wrapped__ = True
        except Exception:
            pass
except Exception:
    pass
# ==== /VSP_P1_SHA256_FALLBACK_V1 ====
'''
p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh

bin/p0_commercial_selfcheck_ui_v1.sh
