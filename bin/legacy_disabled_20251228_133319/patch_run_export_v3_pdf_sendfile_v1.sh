#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportpdf_${TS}"
echo "[BACKUP] $F.bak_exportpdf_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_EXPORT_PDF_SEND_FILE_V1 ==="
if TAG in t:
    print("[OK] already patched, skip")
    raise SystemExit(0)

# ensure imports
if "send_file" not in t:
    # try to extend an existing flask import line
    t2 = re.sub(
        r"from\s+flask\s+import\s+([^\n]+)",
        lambda m: m.group(0) + ("" if "send_file" in m.group(1) else ", send_file"),
        t,
        count=1
    )
    if t2 == t:
        # fallback: add a new import line near top
        t2 = re.sub(r"^(\s*import\s+[^\n]+\n)", r"\1from flask import send_file\n", t, count=1, flags=re.M)
    t = t2

# helper block to inject inside handler (or append new handler if not found)
helper = f"""
{TAG}
import os, glob, time
from flask import request, jsonify

def _vsp_norm_rid(rid: str) -> str:
    rid = (rid or "").strip()
    if rid.startswith("RUN_"):
        return rid[4:]
    return rid

def _vsp_ci_root() -> str:
    return os.environ.get("VSP_CI_OUT_ROOT") or "/home/test/Data/SECURITY-10-10-v4/out_ci"

def _vsp_resolve_ci_dir(rid: str) -> str:
    rn = _vsp_norm_rid(rid)
    base = _vsp_ci_root()

    # common case: VSP_CI_YYYYmmdd_HHMMSS
    cand = os.path.join(base, rn)
    if os.path.isdir(cand):
        return cand

    # sometimes input is RUN_VSP_CI..., normalize already handled; try a few heuristics
    # 1) if rn already like VSP_CI_..., ok; else try prefix
    if not rn.startswith("VSP_CI_") and re.match(r"^\\d{{8}}_\\d{{6}}$", rn):
        cand2 = os.path.join(base, "VSP_CI_" + rn)
        if os.path.isdir(cand2):
            return cand2

    # 2) if rn contains VSP_CI_ timestamp tail, try glob
    gl = glob.glob(os.path.join(base, "VSP_CI_*"))
    if gl:
        # last resort: if rn suffix matches, pick it
        for d in sorted(gl, reverse=True):
            if rn in os.path.basename(d):
                return d

    return ""

def _vsp_pick_newest(patterns):
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

def _vsp_pick_pdf(ci_dir: str) -> str:
    # Prefer reports/*.pdf then any *.pdf
    patterns = [
        os.path.join(ci_dir, "reports", "*.pdf"),
        os.path.join(ci_dir, "reports", "report*.pdf"),
        os.path.join(ci_dir, "reports", "*report*.pdf"),
        os.path.join(ci_dir, "*.pdf"),
    ]
    return _vsp_pick_newest(patterns)

def _vsp_pick_html(ci_dir: str) -> str:
    patterns = [
        os.path.join(ci_dir, "reports", "*.html"),
        os.path.join(ci_dir, "reports", "report*.html"),
        os.path.join(ci_dir, "*.html"),
    ]
    return _vsp_pick_newest(patterns)

def _vsp_pick_zip(ci_dir: str) -> str:
    patterns = [
        os.path.join(ci_dir, "reports", "*.zip"),
        os.path.join(ci_dir, "*.zip"),
    ]
    return _vsp_pick_newest(patterns)
"""

# Try to patch existing run_export_v3 handler
# Find decorator line containing run_export_v3 then replace the whole function block
m = re.search(r"@[^\\n]*route\\([^\\n]*?/api/vsp/run_export_v3/[^\\n]*\\)\\s*\\n\\s*def\\s+([a-zA-Z0-9_]+)\\s*\\(", t)
if m:
    func_name = m.group(1)
    print("[INFO] found handler:", func_name)

    # Grab the whole function block (from def to next decorator/def at col 0)
    pat = re.compile(rf"(@[^\\n]*route\\([^\\n]*?/api/vsp/run_export_v3/[^\\n]*\\)\\s*\\n\\s*def\\s+{re.escape(func_name)}\\s*\\([^\\)]*\\)\\s*:\\n)([\\s\\S]*?)(?=\\n@|\\n\\s*def\\s+|\\Z)", re.M)
    mm = pat.search(t)
    if not mm:
        raise SystemExit("[ERR] cannot capture function body for run_export_v3")

    head = mm.group(1)

    # New body: serve file directly for html/zip/pdf; otherwise JSON error
    new_body = """
    # NOTE: commercial export: resolve CI run dir then serve real artifacts
    rid_in = rid
    fmt = (request.args.get("fmt") or "html").lower().strip()
    ci_dir = _vsp_resolve_ci_dir(rid_in)
    if not ci_dir:
        resp = jsonify({"ok": False, "http_code": 404, "error": "EXPORT_CI_DIR_NOT_FOUND", "rid": rid_in, "rid_norm": _vsp_norm_rid(rid_in)})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    if fmt == "pdf":
        pdf = _vsp_pick_pdf(ci_dir)
        if pdf and os.path.isfile(pdf):
            resp = send_file(pdf, mimetype="application/pdf", as_attachment=True, download_name=os.path.basename(pdf))
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return resp
        resp = jsonify({"ok": False, "http_code": 404, "error": "PDF_NOT_FOUND", "ci_run_dir": ci_dir})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    if fmt == "html":
        html = _vsp_pick_html(ci_dir)
        if html and os.path.isfile(html):
            resp = send_file(html, mimetype="text/html", as_attachment=True, download_name=os.path.basename(html))
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return resp
        resp = jsonify({"ok": False, "http_code": 404, "error": "HTML_NOT_FOUND", "ci_run_dir": ci_dir})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    if fmt == "zip":
        z = _vsp_pick_zip(ci_dir)
        if z and os.path.isfile(z):
            resp = send_file(z, mimetype="application/zip", as_attachment=True, download_name=os.path.basename(z))
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return resp
        resp = jsonify({"ok": False, "http_code": 404, "error": "ZIP_NOT_FOUND", "ci_run_dir": ci_dir})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    resp = jsonify({"ok": False, "http_code": 400, "error": "UNSUPPORTED_FMT", "fmt": fmt})
    resp.status_code = 400
    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
    return resp
"""

    # Inject helper once, near top-level (after imports area)
    # Place helper after the first block of imports (best-effort)
    if TAG not in t:
        # insert helper after last "import ..." in the header region (first ~200 lines)
        lines = t.splitlines(True)
        cut = min(len(lines), 250)
        ins_at = 0
        for i in range(cut):
            if re.match(r"^(from\\s+\\S+\\s+import|import\\s+\\S+)", lines[i]):
                ins_at = i+1
        lines.insert(ins_at, helper)
        t = "".join(lines)

    # Replace body
    t = t[:mm.start(2)] + new_body + t[mm.end(2):]
    p.write_text(t, encoding="utf-8")
    print("[OK] patched existing run_export_v3 handler")
else:
    # No handler found: append a new route at end (safe only if route not registered elsewhere)
    print("[WARN] run_export_v3 handler not found; appending new route at file end")
    append = helper + """
@app.route("/api/vsp/run_export_v3/<rid>")
def api_vsp_run_export_v3(rid):
    rid_in = rid
    fmt = (request.args.get("fmt") or "html").lower().strip()
    ci_dir = _vsp_resolve_ci_dir(rid_in)
    if not ci_dir:
        resp = jsonify({"ok": False, "http_code": 404, "error": "EXPORT_CI_DIR_NOT_FOUND", "rid": rid_in, "rid_norm": _vsp_norm_rid(rid_in)})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    if fmt == "pdf":
        pdf = _vsp_pick_pdf(ci_dir)
        if pdf and os.path.isfile(pdf):
            resp = send_file(pdf, mimetype="application/pdf", as_attachment=True, download_name=os.path.basename(pdf))
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return resp
        resp = jsonify({"ok": False, "http_code": 404, "error": "PDF_NOT_FOUND", "ci_run_dir": ci_dir})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    if fmt == "html":
        html = _vsp_pick_html(ci_dir)
        if html and os.path.isfile(html):
            resp = send_file(html, mimetype="text/html", as_attachment=True, download_name=os.path.basename(html))
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return resp
        resp = jsonify({"ok": False, "http_code": 404, "error": "HTML_NOT_FOUND", "ci_run_dir": ci_dir})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    if fmt == "zip":
        z = _vsp_pick_zip(ci_dir)
        if z and os.path.isfile(z):
            resp = send_file(z, mimetype="application/zip", as_attachment=True, download_name=os.path.basename(z))
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return resp
        resp = jsonify({"ok": False, "http_code": 404, "error": "ZIP_NOT_FOUND", "ci_run_dir": ci_dir})
        resp.status_code = 404
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp

    resp = jsonify({"ok": False, "http_code": 400, "error": "UNSUPPORTED_FMT", "fmt": fmt})
    resp.status_code = 400
    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
    return resp
"""
    p.write_text(t + "\n\n" + append + "\n", encoding="utf-8")
    print("[OK] appended run_export_v3 handler")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
