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

# Tìm block route /report/<run_id>/html
idx = code.find('@app.route("/report/<run_id>/html"')
if idx == -1:
    idx = code.find("@app.route('/report/<run_id>/html'")
if idx == -1:
    print("[ERR] Không tìm thấy @app.route('/report/<run_id>/html') trong app.py")
    sys.exit(1)

def_idx = code.find("def ", idx)
if def_idx == -1:
    print("[ERR] Không tìm thấy def sau route /report/<run_id>/html")
    sys.exit(1)

end = code.find("\n@app.route", def_idx + 1)
if end == -1:
    end = len(code)

before = code[:idx]
after = code[end:]

new_block = textwrap.dedent("""
@app.route("/report/<run_id>/html", methods=["GET"])
def report_html(run_id):
    \"""
    Mở report HTML chính cho một RUN.

    Ưu tiên:
      - pm_style_report.html (nếu file đủ lớn, tránh file stub rỗng)
      - pm_style_report_print.html
      - simple_report.html
      - checkmarx_like.html
      - security_resilient.html
    \"""
    from pathlib import Path
    from flask import send_file

    root = Path("/home/test/Data/SECURITY_BUNDLE")
    run_dir = root / "out" / run_id
    report_dir = run_dir / "report"

    if not report_dir.is_dir():
        return f"Không tìm thấy thư mục report cho {run_id}: {report_dir}", 404

    candidates = [
        "pm_style_report.html",
        "pm_style_report_print.html",
        "simple_report.html",
        "checkmarx_like.html",
        "security_resilient.html",
    ]

    for name in candidates:
        f = report_dir / name
        if not f.is_file():
            continue

        # Nếu là pm_style* mà file quá nhỏ (< 2KB) thì coi như hỏng, bỏ qua
        try:
            size = f.stat().st_size
        except OSError:
            size = 0

        if name.startswith("pm_style") and size < 2048:
            print(f"[WARN][REPORT_HTML] Bỏ qua {f} (size={size} bytes, có vẻ là stub).")
            continue

        print(f"[INFO][REPORT_HTML] Dùng {f} (size={size} bytes)")
        return send_file(str(f), conditional=False)

    html_files = sorted(p.name for p in report_dir.glob("*.html"))
    listing = ", ".join(html_files) if html_files else "Không có file .html nào"

    msg = (
        f"Không tìm thấy report HTML phù hợp trong {report_dir}.\\n"
        f"Các file hiện có: {listing}"
    )
    print(f"[WARN][REPORT_HTML] {msg}")
    return msg, 404
""").lstrip("\\n")

code_new = before + new_block + "\\n" + after
path.write_text(code_new, encoding="utf-8")
print("[OK] Đã patch lại route /report/<run_id>/html (v3).")
PY
