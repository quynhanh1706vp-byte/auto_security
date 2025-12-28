#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
BACKUP="${APP}.bak_export_fix_$(date +%Y%m%d_%H%M%S)"

echo "[i] Backup $APP -> $BACKUP"
cp "$APP" "$BACKUP"

python3 - "$APP" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

marker = '@app.route("/runs/<run_id>/export/<fmt>")'
start = data.find(marker)
if start == -1:
    print("[ERR] Không tìm thấy block @app.route(\"/runs/<run_id>/export/<fmt>\") trong app.py")
    sys.exit(1)

# Tìm block tiếp theo (@app.route hoặc if __name__ == "__main__")
next_route = data.find("@app.route(", start + 10)
main_idx   = data.find('if __name__ == "__main__":', start + 10)

candidates = [i for i in [next_route, main_idx] if i != -1]
if candidates:
    end = min(candidates)
else:
    end = len(data)

print(f"[i] Sẽ thay thế block export_run từ index {start} đến {end}")

new_block = '''
@app.route("/runs/<run_id>/export/<fmt>")
def export_run(run_id, fmt):
    """Export artifacts cho một RUN.

    fmt: 'csv' | 'pdf' | 'html'
    """
    from pathlib import Path

    # Chỉ cho 3 định dạng
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

'''.lstrip("\n")

fixed = data[:start] + new_block + data[end:]
path.write_text(fixed, encoding="utf-8")
print("[OK] Đã thay thế hàm export_run() bằng bản sạch.")
PY
