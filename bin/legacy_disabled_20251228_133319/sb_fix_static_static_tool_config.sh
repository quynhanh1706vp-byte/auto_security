#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

echo "[i] ROOT = $ROOT"

python3 - <<'PY'
import os

ROOT = "/home/test/Data/SECURITY_BUNDLE/ui"
TARGET_OLD = "/static/static/tool_config.json"
TARGET_NEW = "/static/tool_config.json"

patched_any = False

for dirpath, dirnames, filenames in os.walk(ROOT):
    for name in filenames:
        if not name.endswith((".js", ".html", ".py")):
            continue
        path = os.path.join(dirpath, name)
        with open(path, encoding="utf-8") as f:
            data = f.read()
        if TARGET_OLD not in data:
            continue
        new = data.replace(TARGET_OLD, TARGET_NEW)
        if new != data:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new)
            patched_any = True
            print("[OK] Patched", path)

if not patched_any:
    print("[INFO] Không tìm thấy '/static/static/tool_config.json' nào để sửa.")
PY

echo "[DONE] sb_fix_static_static_tool_config.sh hoàn thành."
