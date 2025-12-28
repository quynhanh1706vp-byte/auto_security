#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

echo "[i] ROOT = $ROOT"

python3 - <<'PY'
import os

ROOT = "/home/test/Data/SECURITY_BUNDLE/ui"

repls = {
    "/tool_config.json": "/static/tool_config.json",
    "/ui/tool_config.json": "/static/tool_config.json",
    "/config/tool_config.json": "/static/tool_config.json",
    "/data/tool_config.json": "/static/tool_config.json",
}

patched_any = False

for dirpath, dirnames, filenames in os.walk(ROOT):
    for name in filenames:
        if not name.endswith((".js", ".html", ".py")):
            continue
        path = os.path.join(dirpath, name)
        with open(path, encoding="utf-8") as f:
            data = f.read()
        new = data
        for old, new_val in repls.items():
            new = new.replace(old, new_val)
        if new != data:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new)
            patched_any = True
            print("[OK] Patched", path)

if not patched_any:
    print("[INFO] Không tìm thấy path tool_config.json cũ nào để sửa.")
PY

echo "[DONE] sb_fix_tool_config_paths_all.sh hoàn thành."
