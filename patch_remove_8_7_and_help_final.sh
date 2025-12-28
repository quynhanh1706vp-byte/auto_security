#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

python3 - <<'PY'
import os, re

root = "."

# 1) Regex bắt toàn bộ block help: từ "Mỗi dòng tương ứng..." đến "tool_config.json."
help_pattern = re.compile(
    r"Mỗi dòng tương ứng với 1 tool[\s\S]*?tool_config\.json\.",
    flags=re.UNICODE,
)

# 2) Regex bắt riêng chữ  độc lập
ratio_pattern = re.compile(r"\b8/7\b")

for dirpath, _, files in os.walk(root):
    for name in files:
        path = os.path.join(dirpath, name)
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except Exception:
            continue

        new = help_pattern.sub("", text)
        new2 = ratio_pattern.sub("", new)

        if new2 != text:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new2)
            print("[OK] Patched", path)
PY
