#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CFG="$ROOT/tool_config.json"

echo "[i] CFG = $CFG"

if [ ! -f "$CFG" ]; then
  echo "[ERR] Không tìm thấy $CFG"
  exit 1
fi

python3 - "$CFG" <<'PY'
import sys, json, pathlib

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())

TARGET_KEYS = ("note", "ghi_chu", "notes", "explain")

def strip_prefix(s: str) -> str:
    if "Hoạt động bình thường" not in s:
        return s
    # cắt đến sau dấu ":" đầu tiên
    idx = s.find(":")
    if idx == -1:
        return s
    new = s[idx+1:].lstrip()
    return new or s

changed = 0

def walk(obj):
    global changed
    if isinstance(obj, dict):
        for k in TARGET_KEYS:
            if k in obj and isinstance(obj[k], str):
                old = obj[k]
                new = strip_prefix(old)
                if new != old:
                    obj[k] = new
                    changed += 1
        for v in obj.values():
            walk(v)
    elif isinstance(obj, list):
        for item in obj:
            walk(item)

walk(data)

if changed == 0:
    print("[WARN] Không tìm thấy ghi chú nào có prefix 'Hoạt động bình thường'.")
else:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"[DONE] Đã bỏ prefix cho {changed} ghi chú trong tool_config.json")
PY

echo "[DONE] strip_tool_notes_prefix.sh chạy xong."
