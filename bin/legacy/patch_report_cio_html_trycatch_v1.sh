#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
APP="vsp_demo_app.py"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "$APP.bak_report_html_trycatch_${TS}" && echo "[BACKUP] $APP.bak_report_html_trycatch_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

pat = re.compile(r'(?ms)^@app\.get\("/vsp/report_cio_v1/<rid>"\)\s*\n^def\s+vsp_report_cio_v1\([^)]*\):\n(?:^[ \t].*\n)*?(?=^@app\.|^@|\Z)')
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find vsp_report_cio_v1 route")

new_fn = r'''@app.get("/vsp/report_cio_v1/<rid>")
def vsp_report_cio_v1(rid):
    # HTML report route (safe render with debug)
    import traceback
    from flask import render_template_string

    rd = _vsp_resolve_run_dir_report_v1(rid)
    if not rd:
        return Response(f"<h3>run_dir_not_found</h3><pre>{rid}</pre>", status=404, content_type="text/html; charset=utf-8")

    ctx, meta, code = _vsp_build_report_ctx_v1(rid, rd)
    if not ctx:
        return Response(f"<h3>report_failed</h3><pre>{meta}</pre>", status=500, content_type="text/html; charset=utf-8")

    ui_root = os.path.abspath(os.path.dirname(__file__))
    tpl_path = os.path.join(ui_root, "report_templates", "vsp_report_cio_v1.html")

    try:
        if not isinstance(ctx, dict):
            raise TypeError(f"ctx must be dict, got {type(ctx)}")
        tpl = open(tpl_path, "r", encoding="utf-8").read()
        html = render_template_string(tpl, **ctx)
    except Exception as e:
        err = {
            "ok": False,
            "rid": rid,
            "error": "template_render_failed",
            "detail": str(e),
            "template": tpl_path,
            "ctx_keys_sample": sorted(list(ctx.keys()))[:80],
            "trace_tail": traceback.format_exc()[-2500:],
        }
        return Response(f"<h3>template_render_failed</h3><pre>{err}</pre>", status=500, content_type="text/html; charset=utf-8")

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
s2 = s[:m.start()] + new_fn + "\n\n" + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched vsp_report_cio_v1 with try/except render")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] patch_report_cio_html_trycatch_v1"
