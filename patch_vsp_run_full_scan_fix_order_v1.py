from pathlib import Path
import re

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
p = ROOT / "vsp_demo_app.py"

txt = p.read_text(encoding="utf-8")
orig = txt

# 0) Gỡ mọi dòng cũ liên quan run_full_scan blueprint để tránh trùng
txt = re.sub(r'.*vsp_run_full_scan_api_v1.*\n', '', txt)
txt = re.sub(r'.*bp_run_full_scan.*register_blueprint.*\n', '', txt)

changed = False

# 1) Thêm import blueprint ngay sau import Flask (nếu chưa có)
if "from api.vsp_run_full_scan_api_v1 import bp_run_full_scan" not in txt:
    m = re.search(r'from flask import .*?\n', txt)
    if m:
        insert_pos = m.end()
        txt = txt[:insert_pos] + "from api.vsp_run_full_scan_api_v1 import bp_run_full_scan\n" + txt[insert_pos:]
        print("[OK] Đã chèn import bp_run_full_scan sau import Flask")
        changed = True
    else:
        # fallback: chèn lên đầu file
        txt = "from api.vsp_run_full_scan_api_v1 import bp_run_full_scan\n" + txt
        print("[WARN] Không tìm thấy 'from flask import ...', chèn import lên đầu file")
        changed = True
else:
    print("[INFO] Import bp_run_full_scan đã tồn tại")


# 2) Thêm app.register_blueprint ngay sau dòng app = Flask(...)
if "app.register_blueprint(bp_run_full_scan)" not in txt:
    m2 = re.search(r'^(app\s*=\s*Flask\(.*?\))\s*$', txt, flags=re.MULTILINE)
    if m2:
        insert_pos2 = m2.end()
        txt = txt[:insert_pos2] + "\napp.register_blueprint(bp_run_full_scan)\n" + txt[insert_pos2:]
        print("[OK] Đã chèn app.register_blueprint(bp_run_full_scan) sau app = Flask(...)")
        changed = True
    else:
        print("[ERR] Không tìm thấy dòng 'app = Flask(...)' để chèn register blueprint")
else:
    print("[INFO] app.register_blueprint(bp_run_full_scan) đã tồn tại")


# 3) Đảm bảo mọi thứ này đều ở TRƯỚC block __main__
m_main = re.search(r'\nif __name__ == [\'"]__main__[\'"]:\s*', txt)
if m_main:
    main_index = m_main.start()
    # kiểm tra xem import & register có nằm trước main_index không
    if txt.find("from api.vsp_run_full_scan_api_v1 import bp_run_full_scan") > main_index \
       or txt.find("app.register_blueprint(bp_run_full_scan)") > main_index:
        print("[FIX] Dịch import/register lên trước block __main__")
        # Cắt phần trước __main__ và sau __main__
        before = txt[:main_index]
        after = txt[main_index:]

        # Gỡ import/register khỏi toàn bộ txt
        before_clean = before
        before_clean = re.sub(r'from api.vsp_run_full_scan_api_v1 import bp_run_full_scan\n', '', before_clean)
        before_clean = re.sub(r'app.register_blueprint\(bp_run_full_scan\)\n', '', before_clean)

        # Thêm import + register về cuối phần before_clean
        import_line = "from api.vsp_run_full_scan_api_v1 import bp_run_full_scan\n"
        reg_line = "app.register_blueprint(bp_run_full_scan)\n"
        if import_line not in before_clean:
            before_clean = before_clean + import_line
        if reg_line not in before_clean:
            before_clean = before_clean + reg_line

        txt = before_clean + after
        changed = True
else:
    print("[INFO] Không thấy block __main__, bỏ qua bước kiểm tra vị trí")


if changed:
    backup = p.with_suffix(p.suffix + ".bak_run_full_fix_order_v1")
    backup.write_text(orig, encoding="utf-8")
    p.write_text(txt, encoding="utf-8")
    print(f"[OK] Backup -> {backup.name}, updated vsp_demo_app.py")
else:
    print("[INFO] Không có thay đổi với vsp_demo_app.py")
