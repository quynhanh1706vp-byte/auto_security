#!/usr/bin/env python3
import os, json, pathlib, sys

APP_PATH = pathlib.Path("app.py")

def main():
    if not APP_PATH.exists():
        print("[ERR] Không tìm thấy app.py trong thư mục hiện tại")
        sys.exit(1)

    text = APP_PATH.read_text(encoding="utf-8")

    # Nếu đã patch rồi thì thôi
    if "def get_last_src(" in text and "src_default=get_last_src()" in text:
        print("[OK] app.py đã có get_last_src, không cần patch.")
        return

    marker = "# ====== FLASK ROUTES ======"
    if marker not in text:
        print("[ERR] Không tìm thấy marker FLASK ROUTES trong app.py")
        sys.exit(1)

    helper_block = """def get_last_src():
    \"\"\"Lấy SRC của RUN mới nhất từ meta.json, fallback về DEFAULT_SRC.\"\"\"
    if not os.path.isdir(OUT_DIR):
        return DEFAULT_SRC
    runs = [
        os.path.join(OUT_DIR, d)
        for d in os.listdir(OUT_DIR)
        if d.startswith("RUN_") and os.path.isdir(os.path.join(OUT_DIR, d))
    ]
    if not runs:
        return DEFAULT_SRC
    runs.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    run_dir = runs[0]
    meta_path = os.path.join(run_dir, "meta.json")
    if os.path.exists(meta_path):
        try:
            with open(meta_path, encoding="utf-8") as f:
                meta = json.load(f)
            return meta.get("src") or meta.get("SRC") or DEFAULT_SRC
        except Exception:
            pass
    return DEFAULT_SRC

""" + marker

    # Chèn hàm get_last_src() trước phần FLASK ROUTES
    text = text.replace(marker, helper_block, 1)

    # Đổi DEFAULT_SRC -> get_last_src() ở route index
    if "src_default=DEFAULT_SRC" not in text:
        print("[WARN] Không thấy chuỗi src_default=DEFAULT_SRC trong app.py, có thể đã được sửa tay.")
    text = text.replace("src_default=DEFAULT_SRC,", "src_default=get_last_src(),", 1)

    APP_PATH.write_text(text, encoding="utf-8")
    print("[OK] Đã patch app.py, SRC sẽ đọc từ meta.json của RUN mới nhất (fallback về DEFAULT_SRC).")

if __name__ == "__main__":
    main()
