from pathlib import Path

path = Path("app.py")
text = path.read_text()

old = '    return redirect(url_for("index"))'
new = '    return redirect(url_for("index", src=src_path, profile=profile, mode=mode))'

if old not in text:
    print("[WARN] Không tìm thấy dòng redirect cũ, không sửa được.")
else:
    text = text.replace(old, new)
    path.write_text(text)
    print("[OK] Đã sửa redirect /run -> / (giữ lại SRC/profile/mode).")
