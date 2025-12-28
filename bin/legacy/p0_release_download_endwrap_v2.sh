#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_reldl_endwrap_v2_${TS}"
echo "[BACKUP] ${W}.bak_reldl_endwrap_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RELEASE_DOWNLOAD_ENDWRAP_V2"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r'''
# ===================== VSP_P0_RELEASE_DOWNLOAD_ENDWRAP_V2 =====================
# WSGI-level interception (always wins) for:
#   GET /api/vsp/release_latest      -> adds download_url
#   GET /api/vsp/release_download/*  -> safe download from releases dirs
try:
    import os, json, re as _re
    from wsgiref.util import FileWrapper

    _UI_ROOT = os.path.dirname(os.path.abspath(__file__))
    _UI_RELEASE_DIR = os.path.join(_UI_ROOT, "releases")
    _OUTCI_RELEASE_DIR = "/home/test/Data/SECURITY_BUNDLE/out_ci/releases"
    _CAND_LATEST = [
        os.path.join(_OUTCI_RELEASE_DIR, "release_latest.json"),
        os.path.join(_UI_RELEASE_DIR, "release_latest.json"),
    ]

    def _safe_name(name: str) -> bool:
        if not name or "/" in name or "\\" in name or ".." in name:
            return False
        # allow common package extensions + sha256 + json
        return bool(_re.match(r'^[A-Za-z0-9._-]+(\.zip|\.tgz|\.tar\.gz|\.sha256|\.json)$', name))

    def _find_latest_json():
        for fp in _CAND_LATEST:
            if os.path.isfile(fp) and os.path.getsize(fp) > 2:
                return fp
        return None

    def _resolve_pkg_abs(j: dict):
        # prefer abs fields
        for k in ("release_pkg_abs","package_abs","pkg_abs"):
            v = (j.get(k) or "").strip()
            if v.startswith("/") and os.path.isfile(v):
                return v
        # common relative fields
        for k in ("package","package_path","release_pkg"):
            v = (j.get(k) or "").strip()
            if not v:
                continue
            # if already abs
            if v.startswith("/") and os.path.isfile(v):
                return v
            # try under /home/test/Data/SECURITY_BUNDLE
            cand = os.path.join("/home/test/Data/SECURITY_BUNDLE", v.lstrip("/"))
            if os.path.isfile(cand):
                return cand
            # try under ui root
            cand2 = os.path.join(_UI_ROOT, v.lstrip("/"))
            if os.path.isfile(cand2):
                return cand2
            # try basename inside known release dirs
            base = os.path.basename(v)
            for d in (_OUTCI_RELEASE_DIR, _UI_RELEASE_DIR):
                c = os.path.join(d, base)
                if os.path.isfile(c):
                    return c
        return ""

    def _json_resp(start_response, obj, code="200 OK", extra_headers=None):
        body = (json.dumps(obj, ensure_ascii=False)).encode("utf-8")
        headers = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("X-VSP-RELEASEDL", "ENDWRAP_V2"),
            ("Content-Length", str(len(body))),
        ]
        if extra_headers:
            headers.extend(extra_headers)
        start_response(code, headers)
        return [body]

    def _download_resp(start_response, abs_path, filename):
        st = os.stat(abs_path)
        headers = [
            ("Content-Type", "application/octet-stream"),
            ("Content-Disposition", f'attachment; filename="{filename}"'),
            ("Cache-Control", "no-store"),
            ("X-VSP-RELEASEDL", "ENDWRAP_V2"),
            ("Content-Length", str(st.st_size)),
        ]
        start_response("200 OK", headers)
        return FileWrapper(open(abs_path, "rb"))

    def _wrap_release_endwrap(app_callable):
        def _wrapped(environ, start_response):
            try:
                path = environ.get("PATH_INFO","") or ""
                if path == "/api/vsp/release_latest":
                    fp = _find_latest_json()
                    if not fp:
                        return _json_resp(start_response, {"ok": False, "err": "release_latest.json not found", "cands": _CAND_LATEST}, "404 Not Found")
                    try:
                        j = json.load(open(fp, "r", encoding="utf-8", errors="ignore"))
                    except Exception as e:
                        return _json_resp(start_response, {"ok": False, "err": f"invalid json: {e}", "source_json": fp}, "500 Internal Server Error")
                    pkg_abs = _resolve_pkg_abs(j or {})
                    out = dict(j or {})
                    out["ok"] = True
                    out["source_json"] = fp
                    if pkg_abs and os.path.isfile(pkg_abs):
                        name = os.path.basename(pkg_abs)
                        out["package_name"] = name
                        out["download_url"] = f"/api/vsp/release_download/{name}"
                        sha = pkg_abs + ".sha256"
                        if os.path.isfile(sha):
                            out["sha256_url"] = f"/api/vsp/release_download/{os.path.basename(sha)}"
                    else:
                        out["download_url"] = ""
                        out["warn"] = "package not resolved to existing file"
                    return _json_resp(start_response, out, "200 OK")
                if path.startswith("/api/vsp/release_download/"):
                    name = path.split("/api/vsp/release_download/",1)[1]
                    if not _safe_name(name):
                        return _json_resp(start_response, {"ok": False, "err": "bad filename"}, "400 Bad Request")
                    # search file only in release dirs
                    for d in (_OUTCI_RELEASE_DIR, _UI_RELEASE_DIR):
                        cand = os.path.join(d, name)
                        if os.path.isfile(cand):
                            return _download_resp(start_response, cand, name)
                    return _json_resp(start_response, {"ok": False, "err": "file not found", "name": name}, "404 Not Found")
            except Exception as e:
                return _json_resp(start_response, {"ok": False, "err": f"endwrap error: {e}"}, "500 Internal Server Error")
            return app_callable(environ, start_response)
        return _wrapped

    # wrap whichever callable exists (outermost)
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_release_endwrap(app)
    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_release_endwrap(application)

    print("[VSP_P0_RELEASE_DOWNLOAD_ENDWRAP_V2] enabled")
except Exception as _e:
    print("[VSP_P0_RELEASE_DOWNLOAD_ENDWRAP_V2] ERROR:", _e)
# ===================== /VSP_P0_RELEASE_DOWNLOAD_ENDWRAP_V2 =====================
''').strip() + "\n\n"

p.write_text(s + "\n\n" + block, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended + py_compile ok:", MARK)
PY

echo "== restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify release_latest now has download_url + header X-VSP-RELEASEDL: ENDWRAP_V2 =="
curl -fsS -D /tmp/rel.h "$BASE/api/vsp/release_latest" -o /tmp/rel.json
grep -i '^X-VSP-RELEASEDL:' /tmp/rel.h || { echo "[ERR] missing X-VSP-RELEASEDL"; sed -n '1,30p' /tmp/rel.h; exit 2; }
python3 -m json.tool /tmp/rel.json | head -n 120

DL="$(python3 - <<'PY'
import json
j=json.load(open("/tmp/rel.json","r",encoding="utf-8"))
print(j.get("download_url",""))
PY
)"
[ -n "$DL" ] || { echo "[ERR] missing download_url in JSON"; cat /tmp/rel.json; exit 2; }

echo "== verify download HEAD =="
curl -fsS -I "$BASE$DL" | sed -n '1,18p'
echo "[DONE] release download ok: $DL"
