#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_cio_route_v2_${TS}" && echo "[BACKUP] $F.bak_cio_route_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="# === VSP_EXPORT_CIO_ROUTE_SAFE_V2B_BEGIN ==="
END  ="# === VSP_EXPORT_CIO_ROUTE_SAFE_V2B_END ==="

block = r'''
{BEGIN}
import os
import subprocess
from flask import send_file, request

@app.get("/api/vsp/run_export_cio_v2/<rid>")
def api_vsp_run_export_cio_v2(rid):
    fmt = (request.args.get("fmt") or "html").lower().strip()
    rebuild = (request.args.get("rebuild") or "0").strip() == "1"
    if fmt != "html":
        return jsonify({"ok": False, "error": "only_html_supported", "fmt": fmt, "rid": rid}), 400

    builder = "/home/test/Data/SECURITY_BUNDLE/bin/vsp_build_cio_report_v2.py"
    if not os.path.isfile(builder):
        return jsonify({"ok": False, "error": "missing_builder", "builder": builder, "rid": rid}), 500

    r = subprocess.run(["python3","-u",builder,rid], capture_output=True, text=True)

    out_html = None
    for line in (r.stdout or "").splitlines():
        if "wrote " in line and "vsp_run_report_cio_v2.html" in line:
            out_html = line.split("wrote ",1)[1].split(" (run_dir=",1)[0].strip()
            break

    if rebuild or (not out_html) or (not os.path.isfile(out_html)):
        # fallback search common roots
        roots = [
          "/home/test/Data/SECURITY-10-10-v4/out_ci",
          "/home/test/Data/SECURITY_BUNDLE/out_ci",
          "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        ]
        for rr in roots:
            cand = os.path.join(rr, rid, "reports", "vsp_run_report_cio_v2.html")
            if os.path.isfile(cand):
                out_html = cand
                break

    if not out_html or not os.path.isfile(out_html):
        return jsonify({
            "ok": False,
            "error": "cio_report_not_found",
            "rid": rid,
            "builder_stdout": (r.stdout or "")[-2000:],
            "builder_stderr": (r.stderr or "")[-2000:],
            "rc": r.returncode
        }), 404

    return send_file(out_html, mimetype="text/html")
{END}
'''.replace("{BEGIN}", BEGIN).replace("{END}", END)

if BEGIN in s and END in s:
    s = re.sub(re.escape(BEGIN)+r".*?"+re.escape(END), block, s, flags=re.S)
else:
    s = s.rstrip() + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected CIO v2 export route")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK => $F"
