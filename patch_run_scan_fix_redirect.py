from pathlib import Path

path = Path("app.py")
text = path.read_text()

old = '    return redirect(url_for("index", profile=profile, mode=mode))'
new = '    return redirect(url_for("index", src=picked_src, profile=profile, mode=mode))'

if old not in text:
    print("[WARN] Không tìm thấy dòng redirect cũ, không sửa được (có thể code hơi khác).")
else:
    text = text.replace(old, new)
    path.write_text(text)
    print("[OK] Đã sửa redirect: giờ /run sẽ quay về /?src=<picked_src>&profile=&mode=")
