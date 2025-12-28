#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

base = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/base.html")
txt = base.read_text(encoding="utf-8")
orig = txt

# 1) Tìm dòng chứa Data Source để làm mẫu
m_ds = re.search(r'^.*href="/datasource".*$', txt, flags=re.M)
if not m_ds:
    print("[ERR] Không tìm thấy dòng menu Data Source trong base.html")
    raise SystemExit(1)

ds_line = m_ds.group(0)
print("[i] Dòng Data Source mẫu:")
print(ds_line)

# 2) Sinh dòng Rule overrides từ dòng Data Source
tool_line = ds_line
tool_line = tool_line.replace('/datasource', '/tool_rules')
tool_line = tool_line.replace('Data Source', 'Rule overrides')
tool_line = tool_line.replace("active_page=='datasource'", "active_page=='tool_rules'")
tool_line = tool_line.replace('active_page == "datasource"', 'active_page == "tool_rules"')

# 3) Nếu đã có dòng /tool_rules thì thay thế, nếu chưa thì chèn sau Data Source
if 'href="/tool_rules"' in txt:
    txt_new = re.sub(r'^.*href="/tool_rules".*$',
                     tool_line,
                     txt,
                     flags=re.M)
    print("[OK] Đã thay thế dòng menu Rule overrides bằng bản đồng bộ.")
else:
    # chèn ngay sau dòng Data Source
    pos = m_ds.end()
    txt_new = txt[:pos] + "\n" + tool_line + txt[pos:]
    print("[OK] Đã chèn thêm dòng menu Rule overrides ngay sau Data Source.")

if txt_new != orig:
    base.write_text(txt_new, encoding="utf-8")
    print("[DONE] Đã ghi lại templates/base.html với menu Rule overrides đồng bộ.")
else:
    print("[INFO] Không có thay đổi gì với base.html.")
PY

echo "[DONE] patch_sidebar_rule_overrides_color.sh hoàn thành."
