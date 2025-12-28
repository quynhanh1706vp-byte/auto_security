#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

base = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/base.html")
text = base.read_text(encoding='utf-8')
orig = text

# 1) Xoá mọi nav Rule overrides cũ (nếu trước đó có patch lởm)
text = re.sub(
    r'\s*<div class="nav-item[^>]*>.*?Rule overrides.*?</div>',
    '',
    text,
    flags=re.S
)

# 2) Tìm block nav Data Source để làm mẫu
m = re.search(r'<div class="nav-item[^>]*>.*?Data Source.*?</div>', text, flags=re.S)
if not m:
    print("[ERR] Không tìm thấy nav Data Source trong base.html")
    raise SystemExit(1)

ds_block = m.group(0)
rule_block = ds_block

# Đổi text + route + active_page key (nếu có)
rule_block = rule_block.replace("Data Source", "Rule overrides")
rule_block = rule_block.replace("/datasource", "/tool_rules")
rule_block = rule_block.replace("datasource", "tool_rules")

# 3) Chèn Rule overrides ngay phía dưới Data Source
insert_pos = m.end()
text = text[:insert_pos] + "\n" + rule_block + text[insert_pos:]

if text != orig:
    base.write_text(text, encoding='utf-8')
    print("[OK] Đã thêm nav Rule overrides ngay dưới Data Source.")
else:
    print("[INFO] Không có thay đổi với base.html.")
PY

echo "[DONE] patch_nav_rule_overrides_final.sh hoàn thành."
