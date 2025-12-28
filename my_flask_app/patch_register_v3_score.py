from pathlib import Path
import re

app_path = Path("app.py")
text = app_path.read_text(encoding="utf-8")

# 1) Thêm import
if "from api_vsp_dashboard_v3 import bp as vsp_dashboard_v3_bp" not in text:
    text = text.replace(
        "from api_vsp_dashboard_v2 import bp as vsp_dashboard_bp\n",
        "from api_vsp_dashboard_v2 import bp as vsp_dashboard_bp\n"
        "from api_vsp_dashboard_v3 import bp as vsp_dashboard_v3_bp\n"
        "from api_vsp_score_v1 import bp as vsp_score_v1_bp\n",
    )

if "from api_vsp_score_v1 import bp as vsp_score_v1_bp" not in text:
    if "from api_vsp_dashboard_v3 import bp as vsp_dashboard_v3_bp" in text:
        # đã có dòng v3, nhưng chưa có score_v1
        text = text.replace(
            "from api_vsp_dashboard_v3 import bp as vsp_dashboard_v3_bp\n",
            "from api_vsp_dashboard_v3 import bp as vsp_dashboard_v3_bp\n"
            "from api_vsp_score_v1 import bp as vsp_score_v1_bp\n",
        )

# 2) Register blueprint sau vsp_dashboard_bp
if "app.register_blueprint(vsp_dashboard_v3_bp)" not in text or \
   "app.register_blueprint(vsp_score_v1_bp)" not in text:

    pattern = r"(app\.register_blueprint\(vsp_dashboard_bp\)\s*\n)"
    m = re.search(pattern, text)
    if m:
        block = m.group(1)
        extra = ""
        if "app.register_blueprint(vsp_dashboard_v3_bp)" not in text:
            extra += "    app.register_blueprint(vsp_dashboard_v3_bp)\n"
        if "app.register_blueprint(vsp_score_v1_bp)" not in text:
            extra += "    app.register_blueprint(vsp_score_v1_bp)\n"
        text = text.replace(block, block + extra, 1)

app_path.write_text(text, encoding="utf-8")
print("[PATCH] DONE. Đã đảm bảo import + register vsp_dashboard_v3_bp / vsp_score_v1_bp")
