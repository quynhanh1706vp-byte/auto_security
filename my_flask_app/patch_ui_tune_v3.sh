#!/usr/bin/env bash
set -euo pipefail

HTML="SECURITY_BUNDLE_FULL_5_PAGES.html"

if [ ! -f "$HTML" ]; then
  echo "[ERR] Không tìm thấy $HTML" >&2
  exit 1
fi

backup="$HTML.bak_$(date +%Y%m%d_%H%M%S)"
cp "$HTML" "$backup"
echo "[i] Đã backup: $backup"

python3 - "$HTML" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# 1) body padding nhỏ lại cho dễ full màn
old_body = """    body {
      display: flex;
      justify-content: center;
      align-items: stretch;
      padding: 16px;
    }
"""
new_body = """    body {
      display: flex;
      justify-content: center;
      align-items: stretch;
      padding: 8px;
    }
"""
if old_body in text:
    text = text.replace(old_body, new_body)
    print("[i] Đã chỉnh body padding 16 -> 8.")

# 2) filters-row: thêm margin top/bottom
old_filters = """    .filters-row {
      display: flex;
      gap: 10px;
      font-size: 11px;
      color: var(--text-muted);
    }
"""
new_filters = """    .filters-row {
      display: flex;
      gap: 10px;
      font-size: 11px;
      color: var(--text-muted);
      margin-top: 6px;
      margin-bottom: 4px;
    }
"""
if old_filters in text:
    text = text.replace(old_filters, new_filters)
    print("[i] Đã chỉnh filters-row margin.")

# 3) Ẩn dòng giải thích nhỏ trong filter-card (filter-meta) cho đỡ rác chữ
old_meta = """    .filter-meta {
      margin-top: 3px;
      font-size: 10px;
    }
"""
new_meta = """    .filter-meta {
      margin-top: 3px;
      font-size: 10px;
      display: none; /* ẩn bớt chữ giải thích cho gọn */
    }
"""
if old_meta in text:
    text = text.replace(old_meta, new_meta)
    print("[i] Đã ẩn filter-meta (bớt chữ cấu hình).")

# 4) Panel subtitle ở Settings: ghi rõ là read-only
text = text.replace(
    "High-level toggles for the EXT+ profile",
    "High-level toggles for the EXT+ profile (read-only – change in tool_config.json)"
)

# 5) Fix trục Y của severity chart để bắt đầu từ 0, có suggestedMax hợp lý
old_y = """            y: {
              grid: {
                color: "rgba(255,255,255,0.06)",
                drawBorder: false
              },
              ticks: {
                color: "rgba(255,255,255,0.4)",
                font: { size: 10 },
                beginAtZero: true
              }
            }
"""
new_y = """            y: {
              grid: {
                color: "rgba(255,255,255,0.06)",
                drawBorder: false
              },
              ticks: {
                color: "rgba(255,255,255,0.4)",
                font: { size: 10 },
                beginAtZero: true
              },
              suggestedMin: 0,
              suggestedMax: Math.max(1000, (Math.max(...data) || 0) * 1.1)
            }
"""
if old_y in text:
    text = text.replace(old_y, new_y)
    print("[i] Đã chỉnh Y axis severity chart (suggestedMin/Max).")

path.write_text(text, encoding="utf-8")
print("[i] Patch xong.")
PY

echo "[i] Done."
