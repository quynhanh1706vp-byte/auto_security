#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"
APP="app.py"
echo "[i] ROOT = $ROOT"
echo "[i] APP  = $APP"

python3 - "$APP" <<'PY'
from pathlib import Path
import textwrap

path = Path("app.py")
txt = path.read_text(encoding="utf-8")
orig = txt

if "/pm_report/<run_id>/<fmt>" in txt:
    print("[INFO] Route /pm_report đã tồn tại, bỏ qua.")
else:
    block = textwrap.dedent("""
    @app.route('/pm_report/<run_id>/<fmt>')
    def pm_report(run_id, fmt):
        \"\"\"Serve PM-style report HTML/PDF cho 1 RUN folder trong out/.\"\"\"
        from pathlib import Path
        from flask import abort, send_file

        root = Path('/home/test/Data/SECURITY_BUNDLE')
        report_dir = root / 'out' / run_id / 'report'

        if not report_dir.is_dir():
            abort(404)

        if fmt == 'html':
            f = report_dir / 'pm_style_report.html'
            if not f.is_file():
                abort(404)
            return send_file(f, mimetype='text/html')
        elif fmt == 'pdf':
            f = report_dir / 'pm_style_report.pdf'
            if not f.is_file():
                abort(404)
            return send_file(f, mimetype='application/pdf')
        else:
            abort(404)
    """)

    marker = "if __name__ == '__main__':"
    idx = txt.rfind(marker)
    if idx != -1:
        txt = txt[:idx] + block + "\n" + txt[idx:]
    else:
        txt = txt + "\n" + block

    if "send_file" not in txt:
        txt = txt.replace("from flask import ", "from flask import send_file, ", 1)

    path.write_text(txt, encoding="utf-8")
    print("[OK] Đã chèn route /pm_report")
PY

echo "[DONE] patch_add_pm_report_route_simple.sh hoàn thành."
