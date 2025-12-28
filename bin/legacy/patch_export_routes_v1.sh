#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
BACKUP="${APP}.bak_export_$(date +%Y%m%d_%H%M%S)"

echo "[i] Backup $APP -> $BACKUP"
cp "$APP" "$BACKUP"

python3 - "$APP" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã có rồi thì thôi, khỏi patch nữa
if "def export_run(" in data:
    print("[i] export_run() đã tồn tại, không sửa.")
    sys.exit(0)

# Thêm import riêng, không đụng import cũ
if "send_from_directory" not in data:
    data = "from flask import send_from_directory, abort\n" + data

# Snippet route export
snippet = r"""

@app.route("/runs/<run_id>/export/<fmt>")
def export_run(run_id, fmt):
    \"\"\"Export artifacts cho một RUN.

    fmt: 'csv' | 'pdf' | 'html'
    \"\"\"
    from pathlib import Path

    if fmt not in {"csv", "pdf", "html"}:
        abort(404)

    base = ROOT / "out" / run_id
    if not base.exists():
        abort(404)

    report = base / "report"
    if not report.is_dir():
        report = base

    if fmt == "csv":
        candidates = ["findings_unified.csv", "findings.csv"]
    elif fmt == "html":
        candidates = ["security_resilient.html", "simple_report.html"]
    else:  # pdf
        candidates = ["security_resilient.pdf", "simple_report.pdf"]

    for name in candidates:
        f = report / name
        if f.is_file():
            return send_from_directory(str(report), name, as_attachment=True)

    abort(404)
"""

# Chèn trước if __name__ == "__main__" nếu có, không thì append cuối file
marker = 'if __name__ == "__main__":'
idx = data.find(marker)
if idx != -1:
    data = data[:idx] + snippet + "\n\n" + data[idx:]
else:
    data = data.rstrip() + "\n" + snippet + "\n"

path.write_text(data, encoding="utf-8")
print("[OK] Đã thêm export_run() vào app.py")
PY
