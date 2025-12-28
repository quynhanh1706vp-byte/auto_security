#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_sha256_always200_${TS}"
echo "[BACKUP] ${F}.bak_sha256_always200_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_SHA256_ALWAYS200_WSGIMW_V2"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

block = r'''
# ==== VSP_P1_SHA256_ALWAYS200_WSGIMW_V2 ====
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

def _vsp__unq(s):
    try:
        from urllib.parse import unquote_plus
        return unquote_plus(s)
    except Exception:
        return s

def _vsp__is_safe_rel(rel):
    # prevent path traversal
    if not rel or rel.startswith("/") or rel.startswith("\\"):
        return False
    if ".." in rel.replace("\\","/").split("/"):
        return False
    return True

class _VSPSha256Always200WSGIMW:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        if path not in ("/api/vsp/sha256", "/api/vsp/sha256/"):
            return self.app(environ, start_response)

        import os, json
        from pathlib import Path as _P

        rid  = _vsp__unq(_vsp__qs_get(environ, "rid"))
        name = _vsp__unq(_vsp__qs_get(environ, "name"))

        # default response (degraded)
        resp = {"ok": False, "rid": rid, "name": name, "missing": True, "resolved": None, "sha256": None}

        # resolve roots
        env_roots = (os.environ.get("VSP_RUNS_ROOTS") or "").strip()
        roots = [x.strip() for x in env_roots.split(":") if x.strip()] if env_roots else [
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        ]

        # candidate relative paths (fallbacks)
        cands = []
        if name and _vsp__is_safe_rel(name):
            cands.append(name)
            if name.startswith("reports/"):
                alt = name[len("reports/"):]
                if _vsp__is_safe_rel(alt):
                    cands.append(alt)

        found = None
        found_rel = None
        if rid and cands:
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

        if found:
            try:
                resp["ok"] = True
                resp["missing"] = False
                resp["resolved"] = found_rel
                resp["sha256"] = _vsp__sha256_hex(str(found))
            except Exception:
                resp["ok"] = False
                resp["missing"] = True

        out = json.dumps(resp, ensure_ascii=False).encode("utf-8")
        headers = [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(out))),
            ("X-VSP-SHA256", "P1_WSGI_V2"),
        ]
        if resp.get("missing"):
            headers.append(("X-VSP-DEGRADED", "sha256_missing_artifact"))
        else:
            headers.append(("X-VSP-SHA256-RESOLVED", resp.get("resolved") or ""))

        start_response("200 OK", headers)
        return [out]

try:
    if "application" in globals() and not getattr(application, "__vsp_sha256_always200_wrapped__", False):
        application = _VSPSha256Always200WSGIMW(application)
        try:
            application.__vsp_sha256_always200_wrapped__ = True
        except Exception:
            pass
except Exception:
    pass
# ==== /VSP_P1_SHA256_ALWAYS200_WSGIMW_V2 ====
'''
p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh

# final selfcheck
bin/p0_commercial_selfcheck_ui_v1.sh
