from pathlib import Path
import shutil

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
tpl_dir = root / "templates"

# Tìm các file backup có chữ "index" và "bak" trong tên
candidates = sorted([
    p for p in tpl_dir.iterdir()
    if p.is_file() and "index" in p.name and "bak" in p.name
])

if not candidates:
    print("[ERR] Không tìm thấy file backup nào cho index.*bak* trong templates/")
else:
    src = candidates[-1]  # chọn file mới nhất theo tên
    dst = tpl_dir / "index.html"
    shutil.copy2(src, dst)
    print(f"[OK] Đã khôi phục templates/index.html từ: {src.name}")
