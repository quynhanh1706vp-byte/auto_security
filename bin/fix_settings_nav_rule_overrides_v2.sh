#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

path = Path("templates/settings.html")
if not path.exists():
    print("[ERR] Không tìm thấy templates/settings.html")
    raise SystemExit(1)

text = path.read_text(encoding="utf-8")
orig = text

# Nếu đã có Rule overrides thì thôi
if "Rule overrides" in text and "/tool_rules" in text:
    print("[INFO] settings.html đã có Rule overrides, bỏ qua.")
else:
    # Bắt nguyên block nav Data Source trong sidebar Settings
    m = re.search(r'(<div class="nav-item[\s\S]*?Data Source[\s\S]*?</div>)', text)
    if not m:
        print("[ERR] Không tìm thấy block nav Data Source trong settings.html")
    else:
        block = m.group(1)
        rule_block = block.replace("Data Source", "Rule overrides") \
                          .replace("/datasource", "/tool_rules") \
                          .replace("datasource", "tool_rules")
        text = text.replace(block, block + "\n" + rule_block)
        path.write_text(text, encoding="utf-8")
        print("[OK] Đã clone block Data Source -> Rule overrides trong settings.html")
PY

echo "[DONE] fix_settings_nav_rule_overrides_v2.sh hoàn thành."
