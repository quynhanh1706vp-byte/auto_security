#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportpdf_override_v3_${TS}"
echo "[BACKUP] $F.bak_exportpdf_override_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_EXPORT_OVERRIDE_VIEWFUNC_V3 ==="
if TAG in t:
    print("[OK] already patched, skip")
    raise SystemExit(0)

block = r'''
# === VSP_EXPORT_OVERRIDE_VIEWFUNC_V3 ===
import os, glob

def _vsp__get_flask_app():
    # support both naming styles
    a = globals().get("app", None)
    if a is not None and hasattr(a, "url_map") and hasattr(a, "view_functions"):
        return a
    a = globals().get("application", None)
    if a is not None and hasattr(a, "url_map") and hasattr(a, "view_functions"):
        return a
    return None

def _vsp_norm_rid(rid: str) -> str:
    rid = (rid or "").strip()
    return rid[4:] if rid.startswith("RUN_") else rid

def _vsp_ci_root() -> str:
    return os.environ.get("VSP_CI_OUT_ROOT") or "/home/test/Data/SECURITY-10-10-v4/out_ci"

def _vsp_resolve_ci_dir(rid: str) -> str:
    rn = _vsp_norm_rid(rid)
    base = _vsp_ci_root()
    cand = os.path.join(base, rn)
    if os.path.isdir(cand):
        return cand
    # fallback: substring match in latest dirs
    gl = sorted(glob.glob(os.path.join(base, "VSP_CI_*")), reverse=True)
    for d in gl:
        if rn in os.path.basename(d):
            return d
    return ""

def _pick_newest(patterns):
    best = ""
    best_m = -1.0
    for pat in patterns:
        for f in glob.glob(pat):
            try:
                m = os.path.getmtime(f)
            except Exception:
                continue
            if m > best_m:
                best_m = m
                best = f
    return best

def _pick_pdf(ci_dir: str) -> str:
    return _pick_newest([os.path.join(ci_dir, "reports", "*.pdf"), os.path.join(ci_dir, "*.pdf")])

def _pick_html(ci_dir: str) -> str:
    return _pick_newest([os.path.join(ci_dir, "reports", "*.html"), os.path.join(ci_dir, "*.html")])

def _pick_zip(ci_dir: str) -> str:
    return _pick_newest([os.path.join(ci_dir, "reports", "*.zip"), os.path.join(ci_dir, "*.zip")])

def _vsp_export_v3_override(**kwargs):
    from flask import request, jsonify, send_file
    # rid param name may vary (rid/run_id/...)
    rid = kwargs.get("rid") or kwargs.get("run_id")
    if not rid and kwargs:
        rid = list(kwargs.values())[0]

    fmt = (request.args.get("fmt") or "html").lower().strip()
    ci_dir = _vsp_resolve_ci_dir(rid or "")

    if not ci_dir:
        resp = jsonify({"ok": False, "http_code": 404, "error": "EXPORT_CI_DIR_NOT_FOUND", "rid": rid, "rid_norm": _vsp_norm_rid(rid or "")})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    if fmt == "pdf":
        f = _pick_pdf(ci_dir)
        if f and os.path.isfile(f):
            resp = send_file(f, mimetype="application/pdf", as_attachment=True, download_name=os.path.basename(f))
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            resp.headers["X-VSP-EXPORT-FILE"] = os.path.basename(f)
            return resp
        resp = jsonify({"ok": False, "http_code": 404, "error": "PDF_NOT_FOUND", "ci_run_dir": ci_dir})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    if fmt == "zip":
        f = _pick_zip(ci_dir)
        if f and os.path.isfile(f):
            resp = send_file(f, mimetype="application/zip", as_attachment=True, download_name=os.path.basename(f))
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            resp.headers["X-VSP-EXPORT-FILE"] = os.path.basename(f)
            return resp
        resp = jsonify({"ok": False, "http_code": 404, "error": "ZIP_NOT_FOUND", "ci_run_dir": ci_dir})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    # default html
    f = _pick_html(ci_dir)
    if f and os.path.isfile(f):
        resp = send_file(f, mimetype="text/html", as_attachment=True, download_name=os.path.basename(f))
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
        resp.headers["X-VSP-EXPORT-FILE"] = os.path.basename(f)
        return resp
    resp = jsonify({"ok": False, "http_code": 404, "error": "HTML_NOT_FOUND", "ci_run_dir": ci_dir})
    resp.status_code = 404
    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
    return resp

# bind override to the REAL endpoint for /api/vsp/run_export_v3/*
try:
    _a = _vsp__get_flask_app()
    _ep = None
    _rules = []
    if _a is not None:
        for _r in _a.url_map.iter_rules():
            if "/api/vsp/run_export_v3/" in (_r.rule or ""):
                _rules.append((_r.rule, _r.endpoint, sorted(list(_r.methods or []))))
        # pick the most relevant: has variable segment "<...>"
        for rule, ep, methods in _rules:
            if "<" in rule and "GET" in methods:
                _ep = ep
                break
        if not _ep and _rules:
            _ep = _rules[0][1]

    if _a is not None and _ep and _ep in _a.view_functions:
        _a.view_functions[_ep] = _vsp_export_v3_override
        print("[VSP_EXPORT_OVERRIDE_V3] bound endpoint=", _ep)
        print("[VSP_EXPORT_OVERRIDE_V3] candidates=", _rules[:5])
    else:
        print("[VSP_EXPORT_OVERRIDE_V3][WARN] app/endpoint not found; app=", type(_a), "ep=", _ep, "candidates=", _rules[:5])
except Exception as _e:
    try:
        print("[VSP_EXPORT_OVERRIDE_V3][ERR]", repr(_e))
    except Exception:
        pass
'''

# insert block near EOF (safe)
t = t + "\n\n" + block + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] inserted override v3")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
