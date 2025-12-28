import re
from pathlib import Path

app_path = Path("app.py")
text = app_path.read_text(encoding="utf-8")

# 1) Thêm import cho v3 + score nếu chưa có
if "api_vsp_dashboard_v3" not in text:
    pattern_import = r"(from api_vsp_dashboard_v2 import bp as vsp_dashboard_bp[^\n]*\n)"
    if re.search(pattern_import, text):
        text = re.sub(
            pattern_import,
            r"\1from api_vsp_dashboard_v3 import bp as vsp_dashboard_v3_bp\n"
            r"from api_vsp_score_v1 import bp as vsp_score_v1_bp\n",
            text,
            count=1,
        )
    else:
        # fallback: chèn sau bất kỳ import api_vsp_dashboard_v2 nào
        text = text.replace(
            "from api_vsp_dashboard_v2 import bp as vsp_dashboard_bp\n",
            "from api_vsp_dashboard_v2 import bp as vsp_dashboard_bp\n"
            "from api_vsp_dashboard_v3 import bp as vsp_dashboard_v3_bp\n"
            "from api_vsp_score_v1 import bp as vsp_score_v1_bp\n",
        )

# 2) Register blueprint trong create_app()
if "vsp_dashboard_v3_bp" not in text or "vsp_score_v1_bp" not in text:
    pattern_register = r"(def create_app\([^)]*\):\s*\n(?:\s+.*\n)*?\s+app\.register_blueprint\(vsp_dashboard_bp\)\s*\n)"
    m = re.search(pattern_register, text)
    if m:
        block = m.group(1)
        # chèn thêm 2 dòng register ngay sau register v2
        new_block = block + "    app.register_blueprint(vsp_dashboard_v3_bp)\n    app.register_blueprint(vsp_score_v1_bp)\n"
        text = text.replace(block, new_block, 1)
    else:
        # fallback đơn giản: chèn tìm chỗ có app.register_blueprint(vsp_dashboard_bp)
        text = text.replace(
            "app.register_blueprint(vsp_dashboard_bp)\n",
            "app.register_blueprint(vsp_dashboard_bp)\n"
            "    app.register_blueprint(vsp_dashboard_v3_bp)\n"
            "    app.register_blueprint(vsp_score_v1_bp)\n",
            1,
        )

app_path.write_text(text, encoding="utf-8")
print("[PATCH] DONE. Đã thêm import + register dashboard_v3 / score_v1 vào app.py")
