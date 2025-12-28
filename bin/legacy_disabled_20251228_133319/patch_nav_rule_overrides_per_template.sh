#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$UI"

python3 - <<'PY'
from pathlib import Path

root = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates")

targets = [
    "index.html",
    "runs.html",
    "settings.html",
    "datasource.html",
    "data_source.html",
    "tool_rules.html",
]

for name in targets:
    path = root / name
    if not path.exists():
        continue

    text = path.read_text(encoding="utf-8")
    if "Rule overrides" in text and "/tool_rules" in text:
        print(f"[INFO] {name}: đã có Rule overrides, bỏ qua.")
        continue

    lines = text.splitlines(keepends=True)
    out_lines = []
    inserted = False

    # Ưu tiên chèn ngay sau nav Data Source
    for ln in lines:
        out_lines.append(ln)
        if (not inserted) and 'href="/datasource"' in ln:
            out_lines.append(
                '          <div class="nav-item"><a href="/tool_rules">Rule overrides</a></div>\n'
            )
            inserted = True

    # Nếu không thấy /datasource, fallback chèn sau Settings
    if not inserted:
        tmp = []
        inserted2 = False
        for ln in out_lines:
            tmp.append(ln)
            if (not inserted2) and 'href="/settings"' in ln:
                tmp.append(
                    '          <div class="nav-item"><a href="/tool_rules">Rule overrides</a></div>\n'
                )
                inserted2 = True
        out_lines = tmp
        if inserted2:
            print(f"[OK] {name}: chèn Rule overrides sau Settings (fallback).")
        else:
            print(f"[WARN] {name}: không tìm thấy /datasource hoặc /settings để chèn nav.")

    else:
        print(f"[OK] {name}: chèn Rule overrides sau Data Source.")

    path.write_text("".join(out_lines), encoding="utf-8")

PY

echo "[DONE] patch_nav_rule_overrides_per_template.sh hoàn thành."
