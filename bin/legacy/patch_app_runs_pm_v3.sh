#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
cd /home/test/Data/SECURITY_BUNDLE/ui
echo "[i] APP = $APP"

python3 - "$APP" <<'PY'
from pathlib import Path
import textwrap

app_path = Path("app.py")
text = app_path.read_text(encoding="utf-8")

marker1 = "if __name__ == '__main__':"
marker2 = 'if __name__ == "__main__":'

if marker1 in text:
    marker = marker1
elif marker2 in text:
    marker = marker2
else:
    raise SystemExit("[ERR] Không tìm thấy block main trong app.py")

head, _sep, _tail = text.partition(marker)

tail = """
from pathlib import Path
import json
from flask import render_template, send_file, abort

ROOT = Path("/home/test/Data/SECURITY_BUNDLE")
OUT_DIR = ROOT / "out"

def _collect_runs():
    \"\"\"Đọc toàn bộ *_RUN_* trong out/ và xây list cho tab Runs & Reports.\"\"\"
    runs = []
    if not OUT_DIR.exists():
        return runs

    def sort_key(p: Path):
        # sort theo tên (RUN_YYYYmmdd_HHMMSS hoặc PREFIX_RUN_YYYYmmdd_HHMMSS)
        return p.name

    for p in sorted(OUT_DIR.glob("*_RUN_*"), key=sort_key, reverse=True):
        run_id = p.name
        report_dir = p / "report"
        summary = report_dir / "summary_unified.json"

        total = 0
        crit = 0
        high = 0
        if summary.exists():
            try:
                data = json.loads(summary.read_text(encoding="utf-8"))
            except Exception:
                data = {}
            total = data.get("total") or data.get("TOTAL") or 0
            sev = (
                data.get("severity_counts")
                or data.get("severity")
                or data.get("sev")
                or {}
            )
            crit = sev.get("CRITICAL") or sev.get("critical") or 0
            high = sev.get("HIGH") or sev.get("high") or 0

        src_guess = "-"
        if "_RUN_" in run_id:
            src_guess = run_id.split("_RUN_", 1)[0]

        runs.append({
            "id": run_id,
            "src": src_guess,
            "total": int(total),
            "crit": int(crit),
            "high": int(high),
            "mode": "Offline · aggr",
        })

    return runs


@app.route('/runs')
def runs_view():
    \"\"\"Trang lịch sử RUN: lấy list từ out/*_RUN_*\"\"\"
    runs = _collect_runs()
    return render_template('runs.html', runs=runs)


@app.route('/pm_report/<run_id>/<fmt>')
def pm_report(run_id, fmt):
    \"\"\"Mở HTML/PDF report cho từng RUN.

    URL:
      /pm_report/<RUN_ID>/html
      /pm_report/<RUN_ID>/pdf
    \"\"\"
    report_dir = OUT_DIR / run_id / "report"
    if not report_dir.exists():
        abort(404)

    if fmt == "html":
        # Ưu tiên pm_style_report.html, không có thì fallback
        for name in ["pm_style_report.html", "security_resilient.html", "simple_report.html"]:
            f = report_dir / name
            if f.exists():
                return send_file(str(f), mimetype="text/html")
        abort(404)

    elif fmt == "pdf":
        for name in ["pm_style_report.pdf", "security_resilient.pdf"]:
            f = report_dir / name
            if f.exists():
                return send_file(str(f), mimetype="application/pdf")
        abort(404)

    abort(404)


if __name__ == '__main__':
    # main block luôn ở cuối file sau khi định nghĩa route
    app.run(debug=True, host='0.0.0.0', port=8905)
"""

new_text = head + tail
app_path.write_text(new_text, encoding="utf-8")
print("[OK] Đã patch lại /runs, /pm_report và block main trong app.py")
PY
