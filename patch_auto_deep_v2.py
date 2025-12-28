from pathlib import Path
import textwrap

p = Path("app.py")
text = p.read_text(encoding="utf-8")

marker_start = "def auto_pick_deep_src(src):"
marker_end = "# ====== TEMPLATE HTML+JS"

i = text.find(marker_start)
j = text.find(marker_end)
if i == -1 or j == -1 or j < i:
    print("[ERR] Không tìm thấy block auto_pick_deep_src trong app.py")
    raise SystemExit(1)

before = text[:i]
after = text[j:]

new_block = '''
def auto_pick_deep_src(src):
    """Tự động chui sâu tối đa 3 tầng để tìm thư mục chứa code.

    Ưu tiên:
    1) Nếu thấy subdir tên code/src/srcs/source -> luôn vào đó trước.
    2) Nếu không có code/src mà đã thấy nhiều file code ở đây -> coi đây là root, dừng.
    3) Nếu không có file, chỉ có 1 thư mục con -> chui tiếp.
    4) Còn lại -> dừng.
    """
    try:
        cur = os.path.abspath(src)
    except Exception:
        print(f"[UI] auto_pick_deep_src: invalid path {src!r}")
        return src

    print(f"[UI] auto_pick_deep_src: start at {cur}")
    preferred = ("code", "src", "srcs", "source")

    for depth in range(4):
        if not os.path.isdir(cur):
            print(f"[UI] auto_pick_deep_src: not a dir → stop at {cur}")
            break

        jumped = False
        for name in preferred:
            cand = os.path.join(cur, name)
            if os.path.isdir(cand):
                print(f"[UI] auto_pick_deep_src: depth {depth} prefer '{name}' -> {cand}")
                cur = cand
                jumped = True
                break
        if jumped:
            continue

        try:
            names = [n for n in os.listdir(cur) if not n.startswith(".")]
        except OSError as e:
            print(f"[UI] auto_pick_deep_src: os.listdir failed at {cur}: {e}")
            break

        entries = [os.path.join(cur, n) for n in names]
        dirs = [d for d in entries if os.path.isdir(d)]
        files = [f for f in entries if os.path.isfile(f)]

        if looks_like_code_files(files):
            print(f"[UI] auto_pick_deep_src: found code files at {cur}, stop")
            break

        if len(dirs) == 1 and not files:
            cur = dirs[0]
            print(f"[UI] auto_pick_deep_src: depth {depth} descend only-dir -> {cur}")
            continue

        print(f"[UI] auto_pick_deep_src: stop at {cur} (dirs={len(dirs)}, files={len(files)})")
        break

    print(f"[UI] auto_pick_deep_src: final -> {cur}")
    return cur

'''

text = before + textwrap.dedent(new_block) + after
p.write_text(text, encoding="utf-8")
print("[OK] Đã cập nhật auto_pick_deep_src() trong app.py")
