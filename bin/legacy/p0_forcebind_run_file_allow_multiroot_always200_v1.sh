#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

cp -f "$PYF" "${PYF}.bak_runfileallow_forcebind_${TS}"
echo "[BACKUP] ${PYF}.bak_runfileallow_forcebind_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

block=textwrap.dedent("""
# ===================== {MARK} =====================
try:
    import os, json, time, re
    from pathlib import Path
    from flask import request, jsonify, send_file, make_response

    _app = globals().get("app") or globals().get("application")
    if _app is None:
        print("[{MARK}] WARN: cannot find app/application in globals()")
    else:
        def _vf_is_rid(v: str) -> bool:
            if not v: return False
            v=str(v).strip()
            if len(v)<6 or len(v)>140: return False
            if any(c.isspace() for c in v): return False
            if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.:-]+$", v): return False
            if not any(ch.isdigit() for ch in v): return False
            return True

        def _vf_safe_relpath(p: str) -> str:
            p = (p or "").strip()
            if not p: return ""
            if p.startswith("/") or p.startswith("\\"): return ""
            if ".." in p: return ""
            p = p.replace("\\", "/")
            while "//" in p: p = p.replace("//", "/")
            if p.startswith("./"): p = p[2:]
            # no empty segments
            if any(seg.strip()=="" for seg in p.split("/")): return ""
            return p

        def _vf_allowed_path(rel: str) -> bool:
            # commercial-safe allowlist: only common artifact types
            rel = rel.lower().strip()
            if not rel: return False
            exts = (".json",".sarif",".csv",".html",".txt",".log",".zip",".tgz",".gz")
            if not rel.endswith(exts): 
                return False
            # deny secrets-ish
            deny = ("id_rsa","known_hosts",".pem",".key","passwd","shadow","token","secret")
            if any(x in rel for x in deny): 
                return False
            return True

        def _vf_roots():
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

        def _vf_find_run_dir(rid: str):
            cand=[]
            for r in _vf_roots():
                try:
                    d = r / rid
                    if d.is_dir():
                        cand.append((d.stat().st_mtime, d))
                except Exception:
                    pass
            cand.sort(reverse=True, key=lambda t: t[0])
            return cand[0][1] if cand else None

        def _vf_cache_path():
            return Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/_rid_latest_cache.json")

        def vsp_run_file_allow_multiroot_v1():
            # ALWAYS 200 JSON on errors (dashboard-safe)
            try:
                rid = (request.args.get("rid","") or "").strip()
                rel = _vf_safe_relpath(request.args.get("path","") or "")
                if not _vf_is_rid(rid):
                    return jsonify({"ok": False, "err": "bad rid", "rid": rid, "path": rel}), 200
                if not _vf_allowed_path(rel):
                    return jsonify({"ok": False, "err": "not allowed", "rid": rid, "path": rel}), 200

                run_dir = _vf_find_run_dir(rid)

                # fallback: if cache has exact rid/path
                if run_dir is None:
                    cp=_vf_cache_path()
                    try:
                        if cp.is_file():
                            j=json.loads(cp.read_text(encoding="utf-8", errors="replace") or "{}")
                            if (j.get("rid") or "").strip() == rid:
                                pth = (j.get("path") or "").strip()
                                if pth and Path(pth).is_dir():
                                    run_dir = Path(pth)
                    except Exception:
                        pass

                if run_dir is None:
                    return jsonify({"ok": False, "err": "rid dir not found", "rid": rid, "path": rel}), 200

                fpath = (run_dir / rel)
                if not fpath.is_file():
                    return jsonify({"ok": False, "err": "missing file", "rid": rid, "path": rel, "run_dir": str(run_dir)}), 200

                # size guard (commercial-safe)
                try:
                    sz = fpath.stat().st_size
                    if sz > 250*1024*1024:
                        return jsonify({"ok": False, "err": "file too large", "rid": rid, "path": rel, "size": sz}), 200
                except Exception:
                    pass

                # send streaming (don’t load whole file)
                mt = "application/octet-stream"
                if rel.endswith(".json") or rel.endswith(".sarif"):
                    mt = "application/json"
                elif rel.endswith(".csv"):
                    mt = "text/csv"
                elif rel.endswith(".html"):
                    mt = "text/html"
                elif rel.endswith(".txt") or rel.endswith(".log"):
                    mt = "text/plain"

                resp = make_response(send_file(str(fpath), mimetype=mt, as_attachment=False))
                resp.headers["Cache-Control"] = "no-store"
                resp.headers["X-VSP-RUNFILEALLOW"] = "{MARK}"
                return resp

            except Exception as e:
                return jsonify({"ok": False, "err": "exception", "detail": str(e)[:180]}), 200

        # Force-bind by url_map
        eps=[]
        try:
            for rule in list(_app.url_map.iter_rules()):
                if getattr(rule, "rule", "") == "/api/vsp/run_file_allow" and ("GET" in (rule.methods or set())):
                    eps.append(rule.endpoint)
        except Exception as e:
            print("[{MARK}] WARN url_map scan failed:", repr(e))

        if eps:
            for ep in eps:
                _app.view_functions[ep] = vsp_run_file_allow_multiroot_v1
            print("[{MARK}] OK rebound existing endpoints:", eps)
        else:
            _app.add_url_rule("/api/vsp/run_file_allow", "vsp_run_file_allow_multiroot_v1",
                              vsp_run_file_allow_multiroot_v1, methods=["GET"])
            print("[{MARK}] OK added new rule endpoint=vsp_run_file_allow_multiroot_v1")

except Exception as _e:
    print("[{MARK}] FAILED:", repr(_e))
# ===================== /{MARK} =====================
""").replace("{MARK}", MARK).strip()+"\n"

m=re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m:
    s = s[:m.start()] + block + "\n" + s[m.start():]
else:
    s = s.rstrip() + "\n\n" + block

p.write_text(s, encoding="utf-8")
print("[OK] appended", MARK, "into", p)
PY

python3 -m py_compile "$PYF" && echo "[OK] py_compile: $PYF" || { echo "[ERR] py_compile failed"; exit 3; }
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Force-bound /api/vsp/run_file_allow (multiroot + always200)."
