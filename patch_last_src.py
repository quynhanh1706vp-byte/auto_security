#!/usr/bin/env python3
import os, json, pathlib, sys, re

APP_PATH = pathlib.Path("app.py")

def inject_last_src_file_var(text: str) -> str:
    if "LAST_SRC_FILE" in text:
        return text
    # chèn sau dòng DEFAULT_SRC
    pat = re.compile(r'(DEFAULT_SRC\s*=\s*.+\n)')
    m = pat.search(text)
    if not m:
        return text
    insert = m.group(1) + 'LAST_SRC_FILE = os.path.join(ROOT, "ui", ".last_src.json")\n'
    return text[:m.start()] + insert + text[m.end():]

def inject_helpers(text: str) -> str:
    if "def read_last_src(" in text:
        return text
    marker = "# ====== FLASK ROUTES ======"
    if marker not in text:
        print("[ERR] Không tìm thấy marker FLASK ROUTES trong app.py", file=sys.stderr)
        return text
    helper = '''def read_last_src():
    """Lấy SRC của lần scan gần nhất từ file .last_src.json, fallback về DEFAULT_SRC."""
    try:
        if os.path.exists(LAST_SRC_FILE):
            with open(LAST_SRC_FILE, encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                s = data.get("src") or data.get("SRC")
                if isinstance(s, str) and s.strip():
                    return s.strip()
    except Exception:
        pass
    return DEFAULT_SRC

def write_last_src(src: str):
    """Ghi SRC gần nhất ra file .last_src.json (không làm gãy app nếu lỗi)."""
    try:
        os.makedirs(os.path.dirname(LAST_SRC_FILE), exist_ok=True)
        with open(LAST_SRC_FILE, "w", encoding="utf-8") as f:
            json.dump({"src": src}, f, ensure_ascii=False)
    except Exception:
        pass

''' + marker
    return text.replace(marker, helper, 1)

def patch_index_src_default(text: str) -> str:
    # thay mọi kiểu src_default=... thành read_last_src()
    text = text.replace("src_default=DEFAULT_SRC,", "src_default=read_last_src(),")
    text = text.replace("src_default=get_last_src(),", "src_default=read_last_src(),")
    return text

def inject_write_last_src_call(text: str) -> str:
    if "write_last_src(src)" in text:
        return text
    # chèn sau đoạn set TARGET_URL nếu có
    anchor = '    if target_url:\n        env["TARGET_URL"] = target_url\n'
    repl = anchor + '    write_last_src(src)\n'
    if anchor in text:
        return text.replace(anchor, repl, 1)
    # fallback: chèn sau env["NO_NET"]
    anchor2 = '    env["NO_NET"] = "1" if mode == "offline" else "0"\n'
    repl2 = anchor2 + '    write_last_src(src)\n'
    if anchor2 in text:
        return text.replace(anchor2, repl2, 1)
    return text

def main():
    if not APP_PATH.exists():
        print("[ERR] Không tìm thấy app.py trong thư mục hiện tại", file=sys.stderr)
        sys.exit(1)

    text = APP_PATH.read_text(encoding="utf-8")

    text = inject_last_src_file_var(text)
    text = inject_helpers(text)
    text = patch_index_src_default(text)
    text = inject_write_last_src_call(text)

    APP_PATH.write_text(text, encoding="utf-8")
    print("[OK] Đã patch app.py để lưu & đọc SRC gần nhất từ ui/.last_src.json")

if __name__ == "__main__":
    main()
