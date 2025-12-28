#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
echo "[i] ROOT = $ROOT"

# Quét toàn bộ file .html, .htm, .js trong ui/
python3 - <<'PY'
import os, io

root = os.path.abspath(".")
print("[PY] Scan trong:", root)

replacements = {
    "Lần quét & Báo cáo": "Run & Report",
    "Cấu hình tool (JSON)": "Settings",
    "Nguồn dữ liệu": "Data Source",
}

def should_process(name: str) -> bool:
    name = name.lower()
    return name.endswith(".html") or name.endswith(".htm") or name.endswith(".js")

changed_any = False

for dirpath, dirnames, filenames in os.walk(root):
    for fname in filenames:
        if not should_process(fname):
            continue
        fpath = os.path.join(dirpath, fname)
        try:
            with io.open(fpath, "r", encoding="utf-8") as f:
                data = f.read()
        except Exception as e:
            print(f"[PY] Bỏ qua {fpath} (không đọc được): {e}")
            continue

        orig = data
        hit = False
        for old, new in replacements.items():
            if old in data:
                data = data.replace(old, new)
                hit = True
                print(f"[PY] {fpath}: '{old}' -> '{new}'")

        if hit and data != orig:
            with io.open(fpath, "w", encoding="utf-8") as f:
                f.write(data)
            changed_any = True

if not changed_any:
    print("[PY] Không tìm thấy chuỗi nào để thay.")
else:
    print("[PY] Đã patch xong các label menu.")
PY

echo "[DONE] patch_sidebar_labels_en_v2.sh hoàn thành."
