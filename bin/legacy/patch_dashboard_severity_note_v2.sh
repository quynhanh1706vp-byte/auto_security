#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/index.html"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"
echo "[i] CSS  = $CSS"

############################
# 1) Sửa HTML (bố cục / note)
############################
if [ -f "$TPL" ]; then
  python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

# 1) Xoá đoạn giải thích dài đang nằm trong card TOTAL FINDINGS
long_note = (
    "Critical / High / Medium / Low – các bucket được tính như sau: "
    "Critical, High, Medium là severity gốc; Low bao gồm cả Info & Unknown "
    "(và các cảnh báo nhẹ). Dữ liệu lấy từ findings_unified.json của RUN mới nhất."
)

if long_note in html:
    html = html.replace(long_note, "")
    print("[OK] Đã xoá đoạn note dài trong card TOTAL FINDINGS.")
else:
    print("[WARN] Không tìm thấy đoạn note dài trong card (có thể đã sửa tay).")

# 2) Thêm một note ngắn gọn ngay dưới heading "DASHBOARD – SEVERITY BUCKETS..."
marker = "DASHBOARD – SEVERITY BUCKETS: CRITICAL / HIGH / MEDIUM / LOW"
idx = html.find(marker)
note_block = (
    '<div class="dash-severity-note">'
    'Critical / High / Medium là severity gốc. '
    'Low = Info + Unknown (và các cảnh báo nhẹ). '
    'Dữ liệu lấy từ <code>findings_unified.json</code> của RUN mới nhất.'
    '</div>'
)

if idx != -1:
    # Tìm thẻ đóng </div> đầu tiên sau marker (thường là thẻ chứa heading)
    close_idx = html.find("</", idx)
    if close_idx != -1:
        close_idx = html.find(">", close_idx)
    if close_idx != -1:
        close_idx += 1
        # Chỉ chèn nếu chưa có dash-severity-note
        if "dash-severity-note" not in html[idx: idx + 400]:
            html = html[:close_idx] + "\n        " + note_block + html[close_idx:]
            print("[OK] Đã chèn dash-severity-note ngay dưới heading.")
        else:
            print("[INFO] Đã có dash-severity-note, không chèn thêm.")
    else:
        print("[WARN] Không xác định được vị trí đóng heading để chèn note.")
else:
    print("[WARN] Không tìm thấy heading DASHBOARD – SEVERITY BUCKETS trong template.")

path.write_text(html, encoding="utf-8")
PY
else
  echo "[ERR] Không tìm thấy $TPL"
fi

############################
# 2) CSS cho dash-severity-note
############################
if [ -f "$CSS" ]; then
  python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

snippet = """
.dash-severity-note {
  margin-top: 4px;
  font-size: 11px;
  color: rgba(226,232,240,0.82);
  max-width: 520px;
}
"""

if ".dash-severity-note" in css:
    print("[INFO] CSS dash-severity-note đã tồn tại.")
else:
    # chèn gần cuối file để dễ override
    css = css.rstrip() + "\n\n/* Note mô tả bucket severity dưới heading */" + snippet + "\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã thêm CSS cho dash-severity-note.")
PY
else
  echo "[WARN] Không tìm thấy $CSS – bỏ qua phần CSS."
fi

echo "[DONE] patch_dashboard_severity_note_v2.sh hoàn thành."
