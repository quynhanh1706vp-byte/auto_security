from pathlib import Path

p = Path("app.py")
text = p.read_text(encoding="utf-8")

# 1) Sửa docstring \"\"\" -> """
if '\\"""' in text:
    text = text.replace('\\"""', '"""')
    print("[OK] Đã sửa docstring \"\"\" -> \"\"\" trong app.py")
else:
    print("[WARN] Không thấy chuỗi \\\"\"\" trong app.py (có thể đã được sửa trước)")

# 2) Sửa run_scan() để dùng auto_pick_deep_src()
old = '@app.route("/run", methods=["POST"])\n' \
'def run_scan():\n' \
'    src = (request.form.get("src_path") or "").strip()\n' \
'    profile = request.form.get("profile") or "aggr"\n' \
'    mode = request.form.get("mode") or "offline"\n' \
'    target_url = (request.form.get("target_url") or "").strip()\n' \
'\n' \
'    if not src:\n' \
'        # Thiếu SRC thì quay lại, không crash\n' \
'        return redirect(url_for("index"))\n' \
'\n' \
'    env = os.environ.copy()\n' \
'    env["SRC"] = src\n'

new = '@app.route("/run", methods=["POST"])\n' \
'def run_scan():\n' \
'    src_raw = (request.form.get("src_path") or "").strip()\n' \
'    profile = request.form.get("profile") or "aggr"\n' \
'    mode = (request.form.get("mode") or "offline").strip().lower()\n' \
'    target_url = (request.form.get("target_url") or "").strip()\n' \
'\n' \
'    if not src_raw:\n' \
'        # Thiếu SRC thì quay lại, không crash\n' \
'        return redirect(url_for("index"))\n' \
'\n' \
'    src = auto_pick_deep_src(src_raw)\n' \
'    try:\n' \
'        print(f"[UI] run_scan: SRC input = {src_raw}, picked = {src}")\n' \
'    except Exception:\n' \
'        pass\n' \
'\n' \
'    env = os.environ.copy()\n' \
'    env["SRC"] = src\n'

if old in text:
    text = text.replace(old, new)
    print("[OK] Đã patch run_scan() dùng auto_pick_deep_src()")
else:
    print("[WARN] Không tìm thấy block run_scan() cũ để thay (có thể đã sửa tay rồi)")

p.write_text(text, encoding="utf-8")
print("[DONE] fix_app_deep_src.py hoàn tất.")
