from pathlib import Path

path = Path("app.py")
text = path.read_text()

old = '    return redirect(url_for("index", src=src_path, profile=profile, mode=mode))'
new = '''    return redirect(url_for(
        "index",
        src=request.form.get("src", DEFAULT_SRC),
        profile=request.form.get("profile", "Aggressive"),
        mode=request.form.get("mode", "Offline"),
    ))'''

if old not in text:
    print("[WARN] Không tìm thấy dòng redirect cũ, không sửa được (đã khác rồi?).")
else:
    text = text.replace(old, new)
    path.write_text(text)
    print("[OK] Đã sửa redirect /run -> / dùng request.form, giữ SRC/profile/mode.")
