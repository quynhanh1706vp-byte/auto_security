#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_cio_route_${TS}" && echo "[BACKUP] $F.bak_cio_route_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="# === VSP_EXPORT_CIO_ROUTE_V1_BEGIN ==="
END  ="# === VSP_EXPORT_CIO_ROUTE_V1_END ==="

block = r'''
{BEGIN}
import os
from flask import send_file, request

@app.get("/api/vsp/run_export_cio_v1/<rid>")
def api_vsp_run_export_cio_v1(rid):
    """
    Commercial CIO report (HTML):
      - Executive Summary
      - Top 10 findings
      - ISO27001 control matrix (if iso_controls.json available)
    """
    fmt = (request.args.get("fmt") or "html").lower().strip()
    rebuild = (request.args.get("rebuild") or "0").strip() == "1"

    # build report using bundle script
    builder = "/home/test/Data/SECURITY_BUNDLE/bin/vsp_build_cio_report_v1.py"
    if not os.path.isfile(builder):
        return jsonify({"ok": False, "error": "missing_builder", "builder": builder, "rid": rid}), 500

    # resolve run_dir via helper if available
    run_dir = None
    try:
        run_dir = _vsp_find_run_dir(rid)  # may exist from other patches
    except Exception:
        run_dir = None

    # if helper missing, builder will resolve by itself
    out_html = None
    if run_dir:
        out_html = os.path.join(run_dir, "reports", "vsp_run_report_cio_v1.html")

    if (not out_html) or rebuild or (not os.path.isfile(out_html)):
        import subprocess
        cmd = ["python3", "-u", builder, rid]
        subprocess.run(cmd, check=False)

        # recompute expected output
        if run_dir:
            out_html = os.path.join(run_dir, "reports", "vsp_run_report_cio_v1.html")

    # final resolve (builder default)
    if not out_html or not os.path.isfile(out_html):
        # last attempt: search common roots quickly
        roots = [
          "/home/test/Data/SECURITY-10-10-v4/out_ci",
          "/home/test/Data/SECURITY_BUNDLE/out_ci",
          "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        ]
        for r in roots:
            cand = os.path.join(r, rid, "reports", "vsp_run_report_cio_v1.html")
            if os.path.isfile(cand):
                out_html = cand
                break

    if not out_html or not os.path.isfile(out_html):
        return jsonify({"ok": False, "error": "cio_report_not_found", "rid": rid}), 404

    if fmt != "html":
        return jsonify({"ok": False, "error": "only_html_supported", "fmt": fmt, "rid": rid}), 400

    return send_file(out_html, mimetype="text/html")
{END}
'''.replace("{BEGIN}", BEGIN).replace("{END}", END)

if BEGIN in s and END in s:
  s = re.sub(re.escape(BEGIN)+r".*?"+re.escape(END), block, s, flags=re.S)
else:
  s = s.rstrip() + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected CIO export route")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK => $F"
