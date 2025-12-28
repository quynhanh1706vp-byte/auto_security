#!/usr/bin/env bash
set -euo pipefail

FILE="templates/settings.html"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy $FILE"
  exit 1
fi

python3 - <<'PY'
from pathlib import Path

p = Path("templates/settings.html")
text = p.read_text(encoding="utf-8")

lines = text.splitlines(True)
out = []
inserted = False

for ln in lines:
    out.append(ln)
    # Tìm đúng dòng chứa link Data Source trong sidebar của Settings
    if (not inserted) and 'href="/datasource"' in ln:
        # Clone nguyên dòng, chỉ đổi route + label
        new_ln = ln.replace('/datasource', '/tool_rules') \
                   .replace('Data Source', 'Rule overrides')
        out.append(new_ln)
        inserted = True

if not inserted:
    print('[WARN] Không tìm thấy dòng href="/datasource" trong settings.html – không sửa được.')
else:
    p.write_text("".join(out), encoding="utf-8")
    print('[OK] Đã thêm Rule overrides vào sidebar của settings.html.')

PY

echo "[DONE] fix_settings_nav_rule_overrides.sh hoàn thành."
