#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
echo "[i] UI = $UI"

python3 - <<'PY'
from pathlib import Path

ui = Path("/home/test/Data/SECURITY_BUNDLE/ui")

for p in ui.glob("templates/*.html"):
    txt = p.read_text(encoding="utf-8")
    orig = txt

    lines = txt.splitlines()
    new_lines = []
    changed = False

    # 1) Bỏ hết các dòng /tool_rules cũ (nếu có)
    for line in lines:
        if 'href="/tool_rules"' in line and "Rule overrides" in line:
            # bỏ dòng cũ
            changed = True
            print(f"[INFO] {p.name}: remove old /tool_rules nav line.")
            continue
        new_lines.append(line)

    lines = new_lines
    new_lines = []

    # 2) Clone dòng Data Source -> Rule overrides
    for line in lines:
        new_lines.append(line)
        if 'href="/datasource"' in line:
            clone = line
            clone = clone.replace('/datasource', '/tool_rules')
            clone = clone.replace('Data Source', 'Rule overrides')
            clone = clone.replace('datasource', 'tool_rules')
            clone = clone.replace('data_source', 'tool_rules')
            new_lines.append(clone)
            changed = True
            print(f"[OK] {p.name}: cloned Data Source nav -> Rule overrides.")

    if changed:
        p.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    else:
        print(f"[INFO] {p.name}: no change (no datasource nav found).")
PY

echo "[DONE] patch_rule_overrides_nav_clone.sh hoàn thành."
