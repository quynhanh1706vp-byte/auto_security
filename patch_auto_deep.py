import re
from pathlib import Path

p = Path("app.py")
text = p.read_text(encoding="utf-8")

pattern = re.compile(
    r"# ====== AUTO PICK DEEP SRC ======\n.*?# ====== TEMPLATE HTML\+JS",
    re.DOTALL,
)

new_block = r"""# ====== AUTO PICK DEEP SRC ======
CODE_EXTS = {
    ".py",".js",".ts",".jsx",".tsx",".go",".java",".c",".cpp",".h",".hpp",
    ".cs",".rb",".php",".swift",".kt",".rs",".sql",
    ".yml",".yaml",".json",".tf",".sh",".bash",".ps1",".ini",".cfg",".conf"
}

def looks_like_code_files(files):
    for f in files:
        _, ext = os.path.splitext(f)
        if ext.lower() in CODE_EXTS:
            return True
    return False

def auto_pick_deep_src(src):
    \"\"\"Tự động chui sâu tối đa 3 tầng để tìm thư mục chứa code.

    Ưu tiên:
    1) Nếu thấy subdir tên code/src/srcs -> luôn vào đó trước.
    2) Nếu không có code/src mà đã thấy nhiều file code ở đây -> coi đây là root, dừng.
    3) Nếu không có file, chỉ có 1 thư mục con -> chui tiếp.
    4) Còn lại -> dừng.
    \"\"\"
    try:
        cur = os.path.abspath(src)
    except Exception:
        return src

    for _ in range(4):
        if not os.path.isdir(cur):
            break
        try:
            names = os.listdir(cur)
        except OSError:
            break

        entries = [os.path.join(cur, e) for e in names]
        dirs = [d for d in entries if os.path.isdir(d) and not os.path.basename(d).startswith(".")]
        files = [f for f in entries if os.path.isfile(f)]

        # 1) Ưu tiên thư mục code/src/srcs
        prefer = [d for d in dirs if os.path.basename(d).lower() in ("code", "src", "srcs")]
        if prefer:
            prefer.sort(key=lambda d: {"code":0,"src":1,"srcs":2}.get(os.path.basename(d).lower(), 99))
            next_dir = prefer[0]
            print(f"[UI] auto_pick_deep_src: prefer subdir '{os.path.basename(next_dir)}' -> {next_dir}")
            cur = next_dir
            continue

        # 2) Nếu thấy file code ở đây -> coi như root
        if looks_like_code_files(files):
            break

        # 3) Không có file, chỉ có 1 subdir -> chui tiếp
        if len(dirs) == 1 and not files:
            next_dir = dirs[0]
            print(f"[UI] auto_pick_deep_src: only subdir -> {next_dir}")
            cur = next_dir
            continue

        # 4) Các case còn lại -> dừng
        break

    return cur

# ====== TEMPLATE HTML+JS
"""

m = pattern.search(text)
if not m:
    raise SystemExit("Không tìm thấy block '# ====== AUTO PICK DEEP SRC ======' trong app.py")

new_text = text[:m.start()] + new_block + text[m.end():]
p.write_text(new_text, encoding="utf-8")
print("[OK] Đã patch auto_pick_deep_src() trong app.py")
