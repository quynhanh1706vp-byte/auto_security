#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

marker = "def report_simple("
if marker in code:
    print("[INFO] Đã có route report_simple(), bỏ qua.")
    sys.exit(0)

block = textwrap.dedent("""
@app.route("/report/<run_id>/simple", methods=["GET"])
def report_simple(run_id):
    \"""
    View Checkmarx-style / simple report cho một RUN.
    \"""
    from pathlib import Path
    from flask import send_file

    root = Path("/home/test/Data/SECURITY_BUNDLE")
    run_dir = root / "out" / run_id
    report_dir = run_dir / "report"

    if not report_dir.is_dir():
        return f"Không tìm thấy thư mục report cho {run_id}: {report_dir}", 404

    # Ưu tiên simple_report.html, fallback sang checkmarx_like.html nếu cần.
    candidates = ["simple_report.html", "checkmarx_like.html"]

    for name in candidates:
        f = report_dir / name
        if f.is_file():
            print(f"[INFO][REPORT_SIMPLE] Dùng {f}")
            return send_file(str(f), conditional=False)

    msg = (
        f"Không tìm thấy simple_report.html/checkmarx_like.html trong {report_dir}"
    )
    print(f"[WARN][REPORT_SIMPLE] {msg}")
    return msg, 404
""").lstrip("\n")

# chèn block ngay SAU route /report/<run_id>/html nếu có, cho gọn
idx = code.find('@app.route("/report/<run_id>/html"')
if idx == -1:
    idx = code.find("@app.route('/report/<run_id>/html'")
if idx != -1:
    end = code.find("\n@app.route", idx + 1)
    if end == -1:
        end = len(code)
    code_new = code[:end] + "\n\n" + block + "\n" + code[end:]
else:
    # nếu không tìm thấy thì append cuối file
    print("[WARN] Không tìm thấy route /report/<run_id>/html, append ở cuối file.")
    code_new = code.rstrip() + "\n\n" + block + "\n"

path.write_text(code_new, encoding="utf-8")
print("[OK] Đã thêm route /report/<run_id>/simple.")
PY
