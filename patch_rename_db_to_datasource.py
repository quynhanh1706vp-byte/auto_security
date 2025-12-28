from pathlib import Path

p = Path("app.py")
text = p.read_text(encoding="utf-8")

new = text
# Đổi tên tab "DB" trên thanh menu → "DATA SOURCE"
new = new.replace(">DB<", ">DATA SOURCE<")
# Đổi tiêu đề khối bên trái
new = new.replace("DB / JSON SUMMARY", "DATA SOURCE / JSON SUMMARY")

if new == text:
    print("[WARN] Không tìm thấy chuỗi cần thay, app.py giữ nguyên.")
else:
    p.write_text(new, encoding="utf-8")
    print("[OK] Đã đổi DB → DATA SOURCE (tab + tiêu đề).")
