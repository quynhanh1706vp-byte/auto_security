#!/usr/bin/env python3
import re
from pathlib import Path

APP = Path(__file__).resolve().parent / "app.py"

def main() -> int:
    if not APP.is_file():
        print(f"[ERR] Không tìm thấy app.py tại {APP}")
        return 1

    text = APP.read_text(encoding="utf-8")

    if "tools_total" not in text or "tools_enabled" not in text:
        print("[WARN] Không thấy 'tools_total' hoặc 'tools_enabled' trong app.py, không patch.")
        return 0

    # Tìm dòng đầu tiên gán tools_total = ...
    m = re.search(r"^(?P<indent>\s*)tools_total\s*=\s*.+$", text, flags=re.MULTILINE)
    if not m:
        print("[WARN] Không tìm thấy dòng 'tools_total = ...' để chèn thêm logic.")
        return 0

    indent = m.group("indent")
    line = m.group(0)

    fix_line = f"{line}\n{indent}# Đảm bảo tổng tool >= số tool đang bật (tránh )\n{indent}tools_total = max(tools_total, tools_enabled)"

    new_text = text[:m.start()] + fix_line + text[m.end():]
    APP.write_text(new_text, encoding="utf-8")

    print(f"[OK] Đã chèn dòng max(tools_total, tools_enabled) sau dòng:")
    print(f"     {line.strip()}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
