#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"

echo "== [1] pick latest backup to restore =="
BK="$(ls -1t ${APP}.bak_report_importlib_* 2>/dev/null | head -n 1 || true)"
if [ -z "${BK:-}" ]; then
  BK="$(ls -1t ${APP}.bak_report_cio_parsefix_* 2>/dev/null | head -n 1 || true)"
fi
if [ -z "${BK:-}" ]; then
  BK="$(ls -1t ${APP}.bak_report_cio_* 2>/dev/null | head -n 1 || true)"
fi
[ -n "${BK:-}" ] || { echo "[ERR] no suitable backup found for ${APP}"; exit 2; }

cp -f "$BK" "$APP"
echo "[OK] restored $APP <= $BK"

echo "== [2] rewrite /api/vsp/run_report_cio_v1/<rid> endpoint safely =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="### VSP_REPORT_CIO_SAFE_V1 ###"

# Ensure helper exists (or insert it)
if MARK not in s:
    helper = r'''
### VSP_REPORT_CIO_SAFE_V1 ###
import os
import glob
from flask import Response, jsonify, request

def _vsp_run_dir_report_cio_safe_v1(rid: str):
    # prefer existing resolver if available
    for nm in ("_vsp_resolve_run_dir_by_rid", "_vsp_resolve_run_dir_by_rid_v1", "_vsp_resolve_run_dir_by_rid_v2", "_vsp_resolve_run_dir_by_rid_v3"):
        fn = globals().get(nm)
        if callable(fn):
            try:
                rd = fn(rid)
                if rd:
                    return rd
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
'''
    # insert before __main__ if present, else append
    m = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
    ins = m.start() if m else len(s)
    s = s[:ins] + "\n" + helper + "\n" + s[ins:]

# Now replace existing endpoint function block entirely (from decorator to before next decorator)
pattern = re.compile(
    r'(?ms)^@app\.get\("/api/vsp/run_report_cio_v1/<rid>"\)\s*\n'
    r'(?:^@.*\n)*'
    r'^def\s+api_vsp_run_report_cio_v1\([^)]*\):\n'
    r'(?:^[ \t].*\n)*'
    r'(?=^@app\.|^@|\Z)'
)

new_fn = r'''@app.get("/api/vsp/run_report_cio_v1/<rid>")
def api_vsp_run_report_cio_v1(rid):
    # CIO report HTML (safe: importlib renderer)
    import traceback, importlib.util, json
    from flask import render_template_string

    rd = _vsp_run_dir_report_cio_safe_v1(rid)
    if not rd:
        return jsonify({"ok": False, "rid": rid, "error": "run_dir_not_found"}), 200

    ui_root = os.path.abspath(os.path.dirname(__file__))
    tpl_path = os.path.join(ui_root, "report_templates", "vsp_report_cio_v1.html")
    if not os.path.isfile(tpl_path):
        return jsonify({"ok": False, "rid": rid, "error": "template_missing", "template": tpl_path}), 500

    try:
        mod_path = os.path.join(ui_root, "bin", "vsp_build_report_cio_v1.py")
        if not os.path.isfile(mod_path):
            return jsonify({"ok": False, "rid": rid, "error": "renderer_missing", "path": mod_path}), 500
        spec = importlib.util.spec_from_file_location("vsp_build_report_cio_v1", mod_path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)  # type: ignore
        if not hasattr(mod, "build"):
            return jsonify({"ok": False, "rid": rid, "error": "renderer_no_build"}), 500
        ctx = mod.build(rd, ui_root)
    except Exception as e:
        return jsonify({"ok": False, "rid": rid, "error": "renderer_failed", "detail": str(e), "trace": traceback.format_exc()[-2000:]}), 500

    try:
        tpl = open(tpl_path, "r", encoding="utf-8").read()
        html = render_template_string(tpl, **ctx)
    except Exception as e:
        return jsonify({"ok": False, "rid": rid, "error": "template_render_failed", "detail": str(e), "trace": traceback.format_exc()[-2000:]}), 500

    # archive into run_dir
    try:
        rep_dir = os.path.join(rd, "reports")
        os.makedirs(rep_dir, exist_ok=True)
        with open(os.path.join(rep_dir, "vsp_run_report_cio_v1.html"), "w", encoding="utf-8") as f:
            f.write(html)
    except Exception:
        pass

    return Response(html, status=200, content_type="text/html; charset=utf-8")
'''

if pattern.search(s):
    s = pattern.sub(new_fn + "\n\n", s, count=1)
else:
    # If endpoint not found, append it near end (before __main__)
    m = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
    ins = m.start() if m else len(s)
    s = s[:ins] + "\n\n" + new_fn + "\n\n" + s[ins:]

p.write_text(s, encoding="utf-8")
print("[OK] endpoint rewritten safely")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] fix_report_cio_broken_app_v1"
