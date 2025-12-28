#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

BAK="${WSGI}.bak_runfileallow_mw_${TS}"
cp -f "$WSGI" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_WSGI_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

block=textwrap.dedent("""
# ===================== {MARK} =====================
# Intercept /api/vsp/run_file_allow at gateway-level to avoid upstream 500 breaking Dashboard.
try:
    import os, json, time, re
    from pathlib import Path

    def _vsp_wsgify_json(obj):
        b = (json.dumps(obj, ensure_ascii=False) + "\\n").encode("utf-8", "replace")
        return b

    def _vsp_safe_relpath(pth: str) -> str:
        pth = (pth or "").strip()
        if not pth: return ""
        if pth.startswith("/"): return ""
        if ".." in pth: return ""
        pth = pth.replace("\\\\", "/")
        while "//" in pth: pth = pth.replace("//", "/")
        if pth.startswith("./"): pth = pth[2:]
        if not pth: return ""
        if any(seg.strip()=="" for seg in pth.split("/")): return ""
        return pth

    def _vsp_is_rid(v: str) -> bool:
        if not v: return False
        v=str(v).strip()
        if len(v)<6 or len(v)>140: return False
        if any(c.isspace() for c in v): return False
        if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.:-]+$", v): return False
        if not any(ch.isdigit() for ch in v): return False
        return True

    def _vsp_allowed_path(rel: str) -> bool:
        rel = (rel or "").lower().strip()
        if not rel: return False
        exts = (".json",".sarif",".csv",".html",".txt",".log",".zip",".tgz",".gz")
        if not rel.endswith(exts): 
            return False
        deny = ("id_rsa","known_hosts",".pem",".key","passwd","shadow","token","secret")
        if any(x in rel for x in deny):
            return False
        return True

    def _vsp_roots():
        roots = [
            Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
            Path("/home/test/Data/SECURITY_BUNDLE/out"),
            Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
            Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
        ]
        base = Path("/home/test/Data")
        if base.is_dir():
            try:
                for d in base.iterdir():
                    if d.is_dir() and d.name.startswith("SECURITY"):
                        roots.append(d/"out_ci")
                        roots.append(d/"out")
            except Exception:
                pass
        return roots

    def _vsp_find_run_dir(rid: str):
        cand=[]
        for r in _vsp_roots():
            try:
                d = r / rid
                if d.is_dir():
                    cand.append((d.stat().st_mtime, d))
            except Exception:
                pass
        cand.sort(reverse=True, key=lambda t: t[0])
        return cand[0][1] if cand else None

    def _vsp_cache_path():
        return Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/_rid_latest_cache.json")

    def _vsp_guess_mime(rel: str) -> str:
        rel = (rel or "").lower()
        if rel.endswith(".json") or rel.endswith(".sarif"): return "application/json"
        if rel.endswith(".csv"): return "text/csv; charset=utf-8"
        if rel.endswith(".html"): return "text/html; charset=utf-8"
        if rel.endswith(".txt") or rel.endswith(".log"): return "text/plain; charset=utf-8"
        return "application/octet-stream"

    def _vsp_parse_qs(qs: str):
        # minimal QS parser (avoid importing urllib if you prefer; but safe anyway)
        try:
            from urllib.parse import parse_qs
            d=parse_qs(qs or "", keep_blank_values=True)
            def one(k): 
                v=d.get(k, [""])
                return (v[0] if v else "") or ""
            return one("rid").strip(), one("path").strip()
        except Exception:
            return "", ""

    def _vsp_stream_file(path: Path, chunk=1024*256):
        with path.open("rb") as f:
            while True:
                b=f.read(chunk)
                if not b: break
                yield b

    def _vsp_mw_run_file_allow(app):
        def _wrapped(environ, start_response):
            try:
                if environ.get("REQUEST_METHOD") != "GET":
                    return app(environ, start_response)
                if environ.get("PATH_INFO") != "/api/vsp/run_file_allow":
                    return app(environ, start_response)

                rid, rel = _vsp_parse_qs(environ.get("QUERY_STRING",""))
                rel = _vsp_safe_relpath(rel)
                if not _vsp_is_rid(rid):
                    body=_vsp_wsgify_json({"ok": False, "err": "bad rid", "rid": rid, "path": rel})
                    start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                             ("Cache-Control","no-store"),
                                             ("X-VSP-RUNFILEALLOW", "{MARK}")])
                    return [body]
                if not _vsp_allowed_path(rel):
                    body=_vsp_wsgify_json({"ok": False, "err": "not allowed", "rid": rid, "path": rel})
                    start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                             ("Cache-Control","no-store"),
                                             ("X-VSP-RUNFILEALLOW", "{MARK}")])
                    return [body]

                run_dir = _vsp_find_run_dir(rid)

                if run_dir is None:
                    cp=_vsp_cache_path()
                    try:
                        if cp.is_file():
                            j=json.loads(cp.read_text(encoding="utf-8", errors="replace") or "{}")
                            if (j.get("rid") or "").strip()==rid:
                                pth=(j.get("path") or "").strip()
                                if pth and Path(pth).is_dir():
                                    run_dir=Path(pth)
                    except Exception:
                        pass

                if run_dir is None:
                    body=_vsp_wsgify_json({"ok": False, "err": "rid dir not found", "rid": rid, "path": rel})
                    start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                             ("Cache-Control","no-store"),
                                             ("X-VSP-RUNFILEALLOW", "{MARK}")])
                    return [body]

                fpath = run_dir / rel
                if not fpath.is_file():
                    body=_vsp_wsgify_json({"ok": False, "err": "missing file", "rid": rid, "path": rel, "run_dir": str(run_dir)})
                    start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                             ("Cache-Control","no-store"),
                                             ("X-VSP-RUNFILEALLOW", "{MARK}")])
                    return [body]

                # size guard
                try:
                    sz=fpath.stat().st_size
                    if sz > 250*1024*1024:
                        body=_vsp_wsgify_json({"ok": False, "err": "file too large", "rid": rid, "path": rel, "size": sz})
                        start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                                 ("Cache-Control","no-store"),
                                                 ("X-VSP-RUNFILEALLOW", "{MARK}")])
                        return [body]
                except Exception:
                    pass

                mime=_vsp_guess_mime(rel)
                headers=[("Content-Type", mime),
                         ("Cache-Control","no-store"),
                         ("X-VSP-RUNFILEALLOW","{MARK}")]
                start_response("200 OK", headers)
                return _vsp_stream_file(fpath)

            except Exception as e:
                body=_vsp_wsgify_json({"ok": False, "err": "exception", "detail": str(e)[:180], "marker": "{MARK}"})
                start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                         ("Cache-Control","no-store"),
                                         ("X-VSP-RUNFILEALLOW","{MARK}")])
                return [body]
        return _wrapped

    # attach middleware at EOF so it wins (last wrapper)
    if "application" in globals() and callable(globals().get("application")):
        application = _vsp_mw_run_file_allow(application)
        print("[{MARK}] enabled (application wrapped)")
    elif "app" in globals() and callable(globals().get("app")):
        app = _vsp_mw_run_file_allow(app)
        print("[{MARK}] enabled (app wrapped)")
    else:
        print("[{MARK}] WARN: cannot find WSGI callable to wrap")
except Exception as _e:
    print("[{MARK}] FAILED:", repr(_e))
# ===================== /{MARK} =====================
""").replace("{MARK}", MARK).strip()+"\n"

# append at EOF (must be last wrapper)
s = s.rstrip() + "\n\n" + block
p.write_text(s, encoding="utf-8")
print("[OK] appended", MARK, "into", p)
PY

python3 -m py_compile "$WSGI" && echo "[OK] py_compile: $WSGI" || { echo "[ERR] py_compile failed (auto-rollback)"; cp -f "$BAK" "$WSGI"; exit 3; }

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5. run_file_allow should no longer be upstream-wrapped."
