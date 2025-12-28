#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

cd "$ROOT"
echo "[i] APP = $APP"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("app.py")
text = path.read_text(encoding="utf-8")

# 1) Xoá mọi route cũ /pm_report nếu có
pattern = r"@app\.route\('/pm_report[^']*'\)[\s\S]*?^def\s+pm_report[\s\S]*?(?=^@app\.route|^if __name__ == ['\"]__main__['\"]:|\\Z)"
new_text, n = re.subn(pattern, "", text, flags=re.MULTILINE)
if n:
    print(f"[INFO] Đã xoá {n} block route /pm_report cũ.")
text = new_text

# 2) Thêm route mới
insert = """

@app.route('/pm_report/<run_id>/<fmt>')
def pm_report(run_id, fmt):
    \"\"\"Serve PM-style report (HTML/PDF) cho một RUN_* trong out/.\"\"\"
    from flask import abort, send_file
    from pathlib import Path

    root = Path('/home/test/Data/SECURITY_BUNDLE/out')

    run_dir = root / run_id
    report_dir = run_dir / 'report'

    if not report_dir.is_dir():
        print(f"[WARN] Không tìm thấy report_dir cho {run_id}: {report_dir}")
        abort(404)

    # Ưu tiên pm_style_report, nếu không có thì fallback sang các report khác
    html_candidates = [
        'pm_style_report.html',
        'security_resilient.html',
        'simple_report.html',
    ]

    if fmt == 'html':
        html_path = None
        for name in html_candidates:
            p = report_dir / name
            if p.is_file():
                html_path = p
                break
        if html_path is None:
            print(f"[WARN] Không tìm thấy HTML report cho {run_id} trong {report_dir}")
            abort(404)
        return send_file(html_path)

    elif fmt == 'pdf':
        # Nếu đã có file PDF thì serve, chưa có thì 404 (sau này ta bổ sung generator riêng)
        pdf_path = report_dir / 'pm_style_report.pdf'
        if not pdf_path.is_file():
            print(f"[WARN] Không tìm thấy PDF report cho {run_id}: {pdf_path}")
            abort(404)
        return send_file(pdf_path)

    else:
        abort(404)
"""

marker = "if __name__ == '__main__':"
if insert.strip() in text:
    print("[INFO] Route /pm_report/<run_id>/<fmt> đã tồn tại, không patch.")
elif marker in text:
    text = text.replace(marker, insert + "\n\n" + marker)
    path.write_text(text, encoding="utf-8")
    print("[OK] Đã chèn route /pm_report/<run_id>/<fmt> vào app.py")
else:
    print("[ERR] Không thấy marker main trong app.py, không patch.")
PY

echo "[DONE] patch_pm_report_route_v2.sh hoàn thành."
