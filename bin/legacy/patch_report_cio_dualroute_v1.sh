#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
APP="vsp_demo_app.py"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "$APP.bak_report_dual_${TS}" && echo "[BACKUP] $APP.bak_report_dual_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="### VSP_REPORT_CIO_DUALROUTE_V1 ###"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Remove any previous definitions of these endpoints (safe best-effort)
s = re.sub(r'(?ms)^@app\.get\("/api/vsp/run_report_cio_v1/<rid>"\)\s*\n^def\s+api_vsp_run_report_cio_v1\([^)]*\):\n(?:^[ \t].*\n)*?(?=^@app\.|^@|\Z)', '', s)
s = re.sub(r'(?ms)^@app\.get\("/vsp/report_cio_v1/<rid>"\)\s*\n^def\s+vsp_report_cio_v1\([^)]*\):\n(?:^[ \t].*\n)*?(?=^@app\.|^@|\Z)', '', s)

block = r'''
### VSP_REPORT_CIO_DUALROUTE_V1 ###
import os, glob
from flask import Response, jsonify, request

def _vsp_resolve_run_dir_report_v1(rid: str):
    # prefer existing resolver if present
    for nm in ("_vsp_resolve_run_dir_by_rid", "_vsp_resolve_run_dir_by_rid_v1", "_vsp_resolve_run_dir_by_rid_v2", "_vsp_resolve_run_dir_by_rid_v3"):
        fn = globals().get(nm)
        if callable(fn):
            try:
                rd = fn(rid)
                if rd: return rd
            except Exception:
                pass
    # fallback glob
    pats = [
      f"/home/test/Data/*/out_ci/{rid}",
      f"/home/test/Data/*/out/{rid}",
      f"/home/test/Data/SECURITY-10-10-v4/out_ci/{rid}",
      f"/home/test/Data/SECURITY_BUNDLE/out_ci/{rid}",
    ]
    for pat in pats:
        for d in glob.glob(pat):
            if os.path.isdir(d):
                return d
    return None

def _vsp_build_report_ctx_v1(rid: str, rd: str):
    import traceback, importlib.util
    ui_root = os.path.abspath(os.path.dirname(__file__))
    tpl_path = os.path.join(ui_root, "report_templates", "vsp_report_cio_v1.html")
    if not os.path.isfile(tpl_path):
        return None, {"ok": False, "rid": rid, "error": "template_missing", "template": tpl_path}, 500

    try:
        mod_path = os.path.join(ui_root, "bin", "vsp_build_report_cio_v1.py")
        if not os.path.isfile(mod_path):
            return None, {"ok": False, "rid": rid, "error": "renderer_missing", "path": mod_path}, 500
        spec = importlib.util.spec_from_file_location("vsp_build_report_cio_v1", mod_path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)  # type: ignore
        if not hasattr(mod, "build"):
            return None, {"ok": False, "rid": rid, "error": "renderer_no_build"}, 500
        ctx = mod.build(rd, ui_root)
        return (ctx, {"ok": True, "rid": rid}, 200)
    except Exception as e:
        return None, {"ok": False, "rid": rid, "error": "renderer_failed", "detail": str(e), "trace": traceback.format_exc()[-2000:]}, 500

@app.get("/api/vsp/run_report_cio_v1/<rid>")
def api_vsp_run_report_cio_v1(rid):
    # API returns JSON only (commercial-safe). HTML is served by /vsp/report_cio_v1/<rid>.
    rd = _vsp_resolve_run_dir_report_v1(rid)
    if not rd:
        return jsonify({"ok": False, "rid": rid, "error": "run_dir_not_found"}), 200

    ctx, meta, code = _vsp_build_report_ctx_v1(rid, rd)
    if not ctx:
        return jsonify(meta), code

    return jsonify({
        "ok": True,
        "rid": rid,
        "run_dir": rd,
        "url": f"/vsp/report_cio_v1/{rid}",
        "note": "Open url for HTML report. API returns JSON by design."
    }), 200

@app.get("/vsp/report_cio_v1/<rid>")
def vsp_report_cio_v1(rid):
    # HTML report route (no API wrappers should interfere)
    from flask import render_template_string
    rd = _vsp_resolve_run_dir_report_v1(rid)
    if not rd:
        return Response(f"<h3>run_dir_not_found</h3><pre>{rid}</pre>", status=404, content_type="text/html; charset=utf-8")

    ctx, meta, code = _vsp_build_report_ctx_v1(rid, rd)
    if not ctx:
        return Response(f"<h3>report_failed</h3><pre>{meta}</pre>", status=500, content_type="text/html; charset=utf-8")

    ui_root = os.path.abspath(os.path.dirname(__file__))
    tpl_path = os.path.join(ui_root, "report_templates", "vsp_report_cio_v1.html")
    tpl = open(tpl_path, "r", encoding="utf-8").read()
    html = render_template_string(tpl, **ctx)

    # archive
    try:
        rep_dir = os.path.join(rd, "reports")
        os.makedirs(rep_dir, exist_ok=True)
        with open(os.path.join(rep_dir, "vsp_run_report_cio_v1.html"), "w", encoding="utf-8") as f:
            f.write(html)
    except Exception:
        pass

    return Response(html, status=200, content_type="text/html; charset=utf-8")
'''

m = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
ins = m.start() if m else len(s)
s = s[:ins] + "\n\n" + block + "\n\n" + s[ins:]

p.write_text(s, encoding="utf-8")
print("[OK] injected dual-route report CIO")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] patch_report_cio_dualroute_v1"
