from pathlib import Path
import re

app_path = Path("app.py")
text = app_path.read_text(encoding="utf-8")

# 1) Thêm import cho dashboard_v3 & score_v1

imports_to_add = [
    "from api_vsp_dashboard_v3 import bp as vsp_dashboard_v3_bp",
    "from api_vsp_score_v1 import bp as vsp_score_v1_bp",
]

for imp in imports_to_add:
    if imp not in text:
        # chèn sau import vsp_dashboard_v2 nếu tìm được, else chèn sau nhóm import đầu tiên
        if "from api_vsp_dashboard_v2 import bp as vsp_dashboard_bp" in text:
            text = text.replace(
                "from api_vsp_dashboard_v2 import bp as vsp_dashboard_bp\n",
                "from api_vsp_dashboard_v2 import bp as vsp_dashboard_bp\n"
                + imp
                + "\n",
                1,
            )
        else:
            # fallback: tìm dòng import đầu tiên
            m = re.search(r"^(from .+|import .+)$", text, re.MULTILINE)
            if m:
                start = m.start()
                end_line = text.find("\n", m.end())
                if end_line == -1:
                    end_line = m.end()
                insert_pos = end_line + 1
                text = text[:insert_pos] + imp + "\n" + text[insert_pos:]
            else:
                # không thấy import nào, chèn đầu file
                text = imp + "\n" + text

# 2) Thêm register blueprint ngay trước 'return app' trong create_app()

if "vsp_dashboard_v3_bp" not in text or "vsp_score_v1_bp" not in text:
    # tìm block create_app
    pattern = r"(def create_app\([^)]*\):[\s\S]+?)(\n\s*return app\b)"
    m = re.search(pattern, text)
    if not m:
        print("[PATCH] WARN: không tìm thấy create_app(...) với 'return app', anh check tay.")
    else:
        body_before_return = m.group(1)
        return_stmt = m.group(2)

        # Kiểm tra đã có register chưa, tránh chèn trùng
        extra_lines = ""
        if "app.register_blueprint(vsp_dashboard_v3_bp)" not in body_before_return:
            extra_lines += "    app.register_blueprint(vsp_dashboard_v3_bp)\n"
        if "app.register_blueprint(vsp_score_v1_bp)" not in body_before_return:
            extra_lines += "    app.register_blueprint(vsp_score_v1_bp)\n"

        new_body = body_before_return + "\n" + extra_lines + return_stmt
        text = text[:m.start(1)] + new_body + text[m.end(2):]

app_path.write_text(text, encoding="utf-8")
print("[PATCH] DONE v2: Đã đảm bảo import + register vsp_dashboard_v3_bp / vsp_score_v1_bp")
