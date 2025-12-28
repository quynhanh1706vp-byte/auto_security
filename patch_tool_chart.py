#!/usr/bin/env python3
import sys
from pathlib import Path

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
TPL_DIR = ROOT / "templates"

def find_template_with_heading():
    if not TPL_DIR.is_dir():
        print(f"[ERR] Không tìm thấy thư mục templates: {TPL_DIR}", file=sys.stderr)
        return None

    candidates = []
    for p in TPL_DIR.rglob("*.html"):
        try:
            txt = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        if "findings by tool" in txt.lower():
            candidates.append(p)

    if not candidates:
        print("[WARN] Không tìm thấy file .html nào chứa 'Findings by tool'", file=sys.stderr)
        return None

    # lấy file đầu tiên
    return candidates[0]

def patch_file(path: Path):
    txt = path.read_text(encoding="utf-8")
    if 'id="toolChart"' in txt or "id='toolChart'" in txt:
        print(f"[i] {path} đã có #toolChart, không cần chèn.")
        return

    low = txt.lower()
    needle = "findings by tool"
    idx = low.find(needle)
    if idx == -1:
        print(f"[WARN] Không thấy 'Findings by tool' trong {path}, bỏ qua.", file=sys.stderr)
        return

    # tìm cuối dòng chứa cụm đó
    line_end = txt.find("\n", idx)
    if line_end == -1:
        line_end = len(txt)

    insert_pos = line_end
    snippet = '\n    <div id="toolChart" class="tool-chart-block"></div>\n'

    new_txt = txt[:insert_pos] + snippet + txt[insert_pos:]
    backup = path.with_suffix(path.suffix + ".bak_toolchart")
    backup.write_text(txt, encoding="utf-8")
    path.write_text(new_txt, encoding="utf-8")

    print(f"[OK] Đã chèn #toolChart vào {path}")
    print(f"[i] Backup lưu tại {backup}")

def main():
    tpl = find_template_with_heading()
    if not tpl:
        sys.exit(1)
    print(f"[i] Template chọn: {tpl}")
    patch_file(tpl)

if __name__ == "__main__":
    main()
