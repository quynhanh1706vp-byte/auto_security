#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/app.py"

echo "[i] ROOT = $ROOT"
echo "[i] APP  = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, os

path = sys.argv[1]
print("[PY] Đọc", path)
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

marker = "PM-STYLE REPORT ROUTE V2"
if marker in src:
    print("[PY] Đã có PM-STYLE REPORT ROUTE V2, bỏ qua.")
    raise SystemExit(0)

block = """
# === PM-STYLE REPORT ROUTE V2 (HTML/PDF) ===
@app.route('/pm_report/<run_id>/<fmt>')
def pm_style_report_v2(run_id, fmt):
    \"""Serve PM-style HTML/PDF report cho một RUN_*\"""
    import os
    from flask import abort, send_file

    # /home/test/Data/SECURITY_BUNDLE/ui/app.py
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    run_dir = os.path.join(base_dir, 'out', run_id, 'report')

    if not os.path.isdir(run_dir):
        abort(404)

    if fmt == 'html':
        candidates = ['pm_style_report.html', 'pm_style_report_print.html']
    elif fmt == 'pdf':
        candidates = ['pm_style_report.pdf', 'pm_style_report_print.pdf']
    else:
        abort(404)

    for name in candidates:
        p = os.path.join(run_dir, name)
        if os.path.exists(p):
            return send_file(p)

    abort(404)
"""

with open(path, "a", encoding="utf-8") as f:
    if not src.endswith("\\n"):
        f.write("\\n")
    f.write(block)

print("[PY] Đã append PM-STYLE REPORT ROUTE V2 vào app.py")
PY

echo "[DONE] patch_pm_report_route_v2.sh hoàn thành."
