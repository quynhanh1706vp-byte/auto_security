#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

python3 - <<'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

lines = text.splitlines(keepends=True)

def is_if_main(line: str) -> bool:
    s = line.strip()
    return s.startswith("if __name__ == \"__main__\":") or s.startswith("if __name__ == '__main__':")

changed = False

for i, line in enumerate(lines):
    if is_if_main(line):
        # tìm dòng code thực sự tiếp theo (bỏ qua dòng trống / chỉ comment)
        j = i + 1
        while j < len(lines) and lines[j].strip() in ("", "#"):
            j += 1

        # Nếu ngay sau if đã có dòng thụt lề (4 spaces / tab) thì coi như OK
        if j < len(lines) and (lines[j].startswith("    ") or lines[j].startswith("\t")):
            continue

        # Nếu dòng ngay sau if đã là "pass" do patch trước thì bỏ qua
        if i + 1 < len(lines) and "auto-fix main block" in lines[i + 1]:
            continue

        # Chèn pass làm body cho if
        lines.insert(i + 1, "    pass  # auto-fix main block\n")
        changed = True
        print("[OK] Đã chèn 'pass' sau if __name__ == '__main__': ở dòng", i + 1)

if changed:
    new_text = "".join(lines)
    app_path.write_text(new_text, encoding="utf-8")
else:
    print("[INFO] Không cần chèn gì thêm vào if __name__ == '__main__':")
PY

# kiểm tra lại syntax
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_fix_if_main_pass.sh hoàn thành."
