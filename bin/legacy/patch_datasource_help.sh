#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/datasource.html"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
data = open(path, "r", encoding="utf-8").read()

marker = "Data Source của UI"
idx = data.find(marker)
if idx == -1:
    print("[WARN] Không tìm thấy marker 'Data Source của UI' trong template, bỏ qua.", file=sys.stderr)
    sys.exit(0)

start_pre = data.find("<pre", idx)
if start_pre == -1:
    print("[WARN] Không tìm thấy <pre> sau marker, bỏ qua.", file=sys.stderr)
    sys.exit(0)

pre_open_end = data.find(">", start_pre)
if pre_open_end == -1:
    print("[WARN] Không tìm thấy '>' mở <pre>, bỏ qua.", file=sys.stderr)
    sys.exit(0)

end_pre = data.find("</pre>", pre_open_end)
if end_pre == -1:
    print("[WARN] Không tìm thấy </pre>, bỏ qua.", file=sys.stderr)
    sys.exit(0)

new_body = """Data Source của UI

• Thư mục run: /home/test/Data/SECURITY_BUNDLE/out 
  (mỗi run = 1 thư mục RUN_YYYYmmdd_HHMMSS).

• UI dir: /home/test/Data/SECURITY_BUNDLE/ui 
  (chứa app.py, templates và static assets).

• Mỗi run nên có:
  - summary_unified.json hoặc summary.json.
  - Thư mục report/ chứa:
    + security_resilient.html
    + pm_style_report.html
    + pm_style_report_print.html
    + simple_report.html (nếu có).

• Cách UI đọc dữ liệu:
  - UI quét thư mục out/ và lấy tất cả thư mục có tên bắt đầu bằng "RUN_".
  - RUN mới nhất (theo tên thư mục) được dùng cho phần "Last run" trên Dashboard.
  - Tab "Run & Report" hiển thị danh sách các RUN + link mở từng report HTML/PDF.

• Lưu ý vận hành:
  - Nếu chưa thấy dữ liệu, hãy chạy scan ít nhất một lần
    (ví dụ: bin/run_all_tools_v2.sh) để tạo thư mục RUN_YYYYmmdd_HHMMSS.
  - Có thể dời các RUN_DEMO_* hoặc RUN quá cũ sang thư mục khác
    (ví dụ: out_demo/, out_archive/) để UI chỉ hiển thị các lần scan thực tế.
  - Khi cần mang bundle sang máy khác để xem lại report, chỉ cần copy 2 thư mục:
    /home/test/Data/SECURITY_BUNDLE/out
    /home/test/Data/SECURITY_BUNDLE/ui
    Không bắt buộc phải chạy scan lại.
"""

new_data = data[:pre_open_end+1] + "\n" + new_body + "\n" + data[end_pre:]
open(path, "w", encoding="utf-8").write(new_data)
print("[OK] Đã cập nhật nội dung Data Source.")
PY
