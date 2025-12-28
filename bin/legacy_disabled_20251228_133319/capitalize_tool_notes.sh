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

def cap_first(s: str) -> str:
    if not s:
        return s
    chars = list(s)
    for i, ch in enumerate(chars):
        if ch.isalpha():
            chars[i] = ch.upper()
            break
    return "".join(chars)

changed = 0

def walk(obj):
    global changed
    if isinstance(obj, dict):
        for k in TARGET_KEYS:
            v = obj.get(k)
            if isinstance(v, str):
                new_v = cap_first(v)
                if new_v != v:
                    obj[k] = new_v
                    changed += 1
        for v in obj.values():
            walk(v)
    elif isinstance(obj, list):
        for it in obj:
            walk(it)

walk(data)

if changed == 0:
    print("[WARN] Không có ghi chú nào cần capitalize.")
else:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"[DONE] Đã capitalize chữ đầu cho {changed} ghi chú.")
PY

echo "[DONE] capitalize_tool_notes.sh chạy xong."
