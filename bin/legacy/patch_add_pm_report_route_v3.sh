#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui
APP="app.py"
echo "[i] APP = $APP"

python3 - << 'PY'
from pathlib import Path

app_path = Path("app.py")
text = app_path.read_text(encoding="utf-8")

# Nếu đã có route pm_report thì bỏ qua
if "def pm_report(" in text:
    print("[OK] Đã có route pm_report, bỏ qua patch.")
else:
    marker = "if __name__ =="
    idx = text.find(marker)
    if idx == -1:
        print("[ERR] Không thấy 'if __name__ ==' trong app.py, không patch.")
    else:
        insert = '''

@app.route("/pm_report/<run_id>/<fmt>")
def pm_report(run_id, fmt):
    """
    Serve HTML/PDF report cho 1 RUN cụ thể.

    Ví dụ URL:
      - /pm_report/RUN_20251121_143512/html
      - /pm_report/RUN_20251121_143512/pdf
    """
    from pathlib import Path
    from flask import abort, send_from_directory

    base = Path("/home/test/Data/SECURITY_BUNDLE/out")
    run_dir = base / run_id / "report"
    if not run_dir.is_dir():
        abort(404)

    fmt = fmt.lower()
    if fmt == "html":
        candidates = [
            "pm_style_report.html",
            "security_resilient.html",
            "simple_report.html",
        ]
    elif fmt == "pdf":
        candidates = [
            "pm_style_report.pdf",
            "security_resilient.pdf",
            "simple_report.pdf",
        ]
    else:
        abort(404)

    for name in candidates:
        f = run_dir / name
        if f.is_file():
            return send_from_directory(run_dir, f.name)

    abort(404)
'''
        text = text[:idx] + insert + "\n\n" + text[idx:]
        app_path.write_text(text, encoding="utf-8")
        print("[OK] Đã chèn route pm_report vào app.py.")
PY
