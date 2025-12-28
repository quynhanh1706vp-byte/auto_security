#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSS="$ROOT/static/css/security_resilient.css"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] CSS  = $CSS"
echo "[i] TPL  = $TPL"

#############################
# 1) Sửa scale chiều cao cột
#############################
if [ -f "$CSS" ]; then
  python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

old_lines = [
    "  height: calc(6px + min(var(--sev-count, 0) * 1px, 190px));",
    "  height: calc(12px + min(var(--sev-count, 0) * 0.02px, 180px));",
]

new_line = "  height: calc(30px + min(var(--sev-count, 0), 60) * 2px);  /* bão hoà từ ~60 issues, nhìn cân hơn */"

changed = False
for old in old_lines:
    if old in css:
        css = css.replace(old, new_line)
        changed = True

if not changed and "dash-sev-bar-inner" in css:
    # fallback: chèn luôn vào block .dash-sev-bar-inner nếu chưa có
    css = css.replace(
        ".dash-sev-bar-inner {",
        ".dash-sev-bar-inner {\n" + new_line + "\n"
    )
    changed = True

if changed:
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã cập nhật scale chiều cao cột severity (bão hoà 60 issues).")
else:
    print("[WARN] Không tìm thấy chỗ height của .dash-sev-bar-inner để sửa.")
PY
else
  echo "[WARN] Không tìm thấy $CSS – bỏ qua phần CSS."
fi

#############################################
# 2) Sửa lại phần note / log dưới biểu đồ
#############################################
if [ -f "$TPL" ]; then
  python3 - "$TPL" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

# Tìm đoạn note cũ gần chữ 'DASHBOARD – SEVERITY BUCKETS'
pattern = re.compile(
    r"(Critical\s*/\s*High\s*/\s*Medium\s*/\s*Low[^<]*</small>)",
    re.IGNORECASE,
)

note_new = (
    "<small class=\"dash-severity-note\">"
    "Critical / High / Medium / Low – các bucket được tính như sau: "
    "Critical, High, Medium là severity gốc; Low bao gồm cả Info & Unknown "
    "(và các cảnh báo nhẹ). Dữ liệu lấy từ <code>findings_unified.json</code> "
    "của RUN mới nhất."
    "</small>"
)

if pattern.search(html):
    html = pattern.sub(note_new, html)
    path.write_text(html, encoding="utf-8")
    print("[OK] Đã thay note / log dưới biểu đồ cho đúng thông tin.")
else:
    # Nếu không tìm thấy, thử chèn note mới ngay sau tiêu đề block DASHBOARD – SEVERITY BUCKETS
    marker = "DASHBOARD – SEVERITY BUCKETS: CRITICAL / HIGH / MEDIUM / LOW"
    idx = html.find(marker)
    if idx != -1:
        # tìm vị trí <div class="card-body"> gần đó rồi chèn note
        div_idx = html.find("<div", idx)
        if div_idx != -1:
            insert_pos = html.find("</div>", div_idx)
            if insert_pos != -1:
                insert_pos += len("</div>")
                html = html[:insert_pos] + "\n    " + note_new + html[insert_pos:]
                path.write_text(html, encoding="utf-8")
                print("[OK] Không thấy note cũ – đã chèn note mới sau heading.")
            else:
                print("[WARN] Không định vị được vị trí chèn note mới.")
        else:
            print("[WARN] Không tìm được block thẻ div sau heading để chèn note.")
    else:
        print("[WARN] Không tìm thấy heading 'DASHBOARD – SEVERITY BUCKETS' trong index.html.")
PY
else
  echo "[WARN] Không tìm thấy $TPL – bỏ qua phần note."
fi

echo "[DONE] patch_dashboard_severity_v4.sh hoàn thành."
