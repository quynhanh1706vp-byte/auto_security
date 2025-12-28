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

found = False

def touch_row(row):
    global found
    if not isinstance(row, dict):
        return
    # gom các field thường dùng để đặt tên tool
    text = " ".join(
        str(row.get(k, "")) for k in [
            "name", "tool", "id", "display_name", "label"
        ]
    ).lower()
    if "gitleaks" in text:
        old = row.get("level", "")
        row["level"] = "aggr"
        found = True
        print(f"[OK] Đổi Gitleaks level: '{old}' -> 'aggr' cho row: {text!r}")

def walk(obj):
    if isinstance(obj, dict):
        for v in obj.values():
            walk(v)
    elif isinstance(obj, list):
        for item in obj:
            if isinstance(item, dict):
                touch_row(item)
            walk(item)

walk(data)

if not found:
    print("[WARN] Không tìm thấy dòng Gitleaks trong tool_config.json")
else:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print("[DONE] Đã cập nhật tool_config.json")

PY

echo "[DONE] Script fix_gitleaks_level_aggr.sh chạy xong."
