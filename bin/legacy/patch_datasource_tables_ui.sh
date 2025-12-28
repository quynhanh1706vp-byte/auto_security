#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/datasource.html"
cp "$TPL" "$TPL.bak_table_$(date +%Y%m%d_%H%M%S)" || true

python3 - "$TPL" <<'PY'
from pathlib import Path

path = Path("templates/datasource.html")
data = path.read_text(encoding="utf-8")

# 1) Trong card RAW JSON (DEBUG), gắn id cho <pre> và thêm div để JS render bảng
marker = "RAW JSON (DEBUG)"
idx = data.find(marker)
if idx == -1:
    print("[WARN] Không thấy marker 'RAW JSON (DEBUG)' trong datasource.html")
else:
    pre_start = data.find("<pre", idx)
    if pre_start != -1:
        pre_end_open = data.find(">", pre_start)
        if pre_end_open != -1:
            before = data[:pre_start]
            pre_tag = data[pre_start:pre_end_open+1]
            after = data[pre_end_open+1:]
            if "id=" not in pre_tag:
                pre_tag = pre_tag[:-1] + ' id="ds-summary-json">'  # gắn id
                data = before + pre_tag + after
                print("[OK] Đã gắn id=\"ds-summary-json\" cho <pre> summary JSON")
    else:
        print("[WARN] Không tìm thấy <pre> sau RAW JSON (DEBUG)")

    # Thêm container cho bảng tóm tắt ngay TRƯỚC <pre>
    insert_pos = data.find('<pre id="ds-summary-json">', idx)
    if insert_pos != -1:
        block = """
        <div id="ds-summary-tables" class="sb-card-section">
          <h4>Summary tables (latest RUN)</h4>
          <div class="ds-summary-grid">
            <!-- JS sẽ render 2 bảng: Severity & By tool -->
          </div>
          <hr class="sb-separator" />
        </div>
"""
        data = data[:insert_pos] + block + data[insert_pos:]
        print("[OK] Đã thêm div#ds-summary-tables để hiển thị bảng.")

# 2) Gắn script JS
if "datasource_summary_tables.js" not in data:
    insert_pos = data.rfind("</body>")
    if insert_pos == -1:
        insert_pos = len(data)
    script_block = """
  <script src="/static/js/datasource_summary_tables.js?v=20251125"></script>
</body>"""
    if "</body>" in data:
        data = data[:insert_pos] + script_block + data[insert_pos+len("</body>"):]
    else:
        data = data + script_block
    print("[OK] Đã chèn script datasource_summary_tables.js vào datasource.html")
else:
    print("[INFO] datasource_summary_tables.js đã được include trước đó, bỏ qua.")

path.write_text(data, encoding="utf-8")
PY
