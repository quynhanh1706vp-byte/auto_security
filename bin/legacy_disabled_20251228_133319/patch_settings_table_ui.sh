#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/settings.html"
cp "$TPL" "$TPL.bak_table_$(date +%Y%m%d_%H%M%S)" || true

python3 - "$TPL" <<'PY'
from pathlib import Path

path = Path("templates/settings.html")
data = path.read_text(encoding="utf-8")

# 1) Thay table BY TOOL / CONFIG bằng bảng có tbody id="tool-config-body"
marker = "BY TOOL / CONFIG"
idx = data.find(marker)
if idx == -1:
    print("[WARN] Không thấy marker 'BY TOOL / CONFIG' trong settings.html")
else:
    tbl_start = data.find("<table", idx)
    if tbl_start != -1:
        tbl_end = data.find("</table>", tbl_start)
        if tbl_end != -1:
            tbl_end += len("</table>")
            new_table = """        <table class="sb-table sb-table-compact">
          <thead>
            <tr>
              <th style="width: 120px;">Tool</th>
              <th style="width: 70px;">Enabled</th>
              <th style="width: 80px;">Level</th>
              <th style="width: 160px;">Modes</th>
              <th>Notes</th>
            </tr>
          </thead>
          <tbody id="tool-config-body">
            <tr>
              <td colspan="5">No tool configuration loaded.</td>
            </tr>
          </tbody>
        </table>"""
            data = data[:tbl_start] + new_table + data[tbl_end:]
            print("[OK] Đã patch bảng BY TOOL / CONFIG trong settings.html")
        else:
            print("[WARN] Không tìm thấy </table> sau marker BY TOOL / CONFIG")
    else:
        print("[WARN] Không tìm thấy <table> sau marker BY TOOL / CONFIG")

# 2) Thêm id vào <pre> RAW JSON (DEBUG) để JS có thể đọc
marker2 = "RAW JSON (DEBUG)"
idx2 = data.find(marker2)
if idx2 == -1:
    print("[WARN] Không thấy marker 'RAW JSON (DEBUG)'")
else:
    pre_start = data.find("<pre", idx2)
    if pre_start != -1:
        pre_end_open = data.find(">", pre_start)
        if pre_end_open != -1:
            before = data[:pre_start]
            pre_tag = data[pre_start:pre_end_open+1]
            after = data[pre_end_open+1:]
            if "id=" not in pre_tag:
                pre_tag = pre_tag[:-1] + ' id="tool-config-json">'  # thay '>' cuối
                data = before + pre_tag + after
                print("[OK] Đã gắn id=\"tool-config-json\" cho <pre> RAW JSON")
    else:
        print("[WARN] Không tìm thấy <pre> sau marker RAW JSON (DEBUG)")

# 3) Gắn script JS (nếu chưa có)
if "settings_tool_table.js" not in data:
    insert_pos = data.rfind("</body>")
    if insert_pos == -1:
        insert_pos = len(data)
    script_block = """
  <script src="/static/js/settings_tool_table.js?v=20251125"></script>
</body>"""
    if "</body>" in data:
        data = data[:insert_pos] + script_block + data[insert_pos+len("</body>"):]
    else:
        data = data + script_block
    print("[OK] Đã chèn script settings_tool_table.js vào settings.html")
else:
    print("[INFO] settings_tool_table.js đã được include trước đó, bỏ qua.")

path.write_text(data, encoding="utf-8")
PY
