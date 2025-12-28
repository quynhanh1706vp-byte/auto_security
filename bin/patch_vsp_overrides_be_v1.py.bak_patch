from pathlib import Path

ROOT = Path(".").resolve()

print("[PATCH][OVR_BE] ROOT =", ROOT)

# 1) Tìm file .py đang khai báo /api/vsp/dashboard_v3 (chính là file BP API VSP)
candidates = []
for p in ROOT.rglob("*.py"):
    try:
        text = p.read_text(encoding="utf-8")
    except Exception:
        continue
    if "/api/vsp/dashboard_v3" in text and "Blueprint" in text:
        candidates.append(p)

if not candidates:
    print("[PATCH][OVR_BE][ERR] Không tìm thấy file chứa /api/vsp/dashboard_v3.")
    raise SystemExit(1)

target = candidates[0]
print("[PATCH][OVR_BE] Target file =", target)

text = target.read_text(encoding="utf-8")

# 2) Nếu đã có route /api/vsp/overrides/list thì bỏ qua
if "/api/vsp/overrides/list" in text:
    print("[PATCH][OVR_BE] Đã có /api/vsp/overrides/list trong file, bỏ qua.")
    raise SystemExit(0)

# 3) Đảm bảo đã import jsonify
if "from flask import" in text and "jsonify" not in text:
    print("[PATCH][OVR_BE] Thêm jsonify vào import Flask.")
    text = text.replace(
        "from flask import ",
        "from flask import jsonify, ",
        1,
    )

# 4) Append route mới vào cuối file
patch = r"""

# ======================= VSP_OVERRIDES_BE_V1 =======================
# API: GET /api/vsp/overrides/list
# Mục tiêu: trả về danh sách rule overrides để UI Rule Overrides tab hiển thị.

@bp.route("/api/vsp/overrides/list", methods=["GET"])
def api_vsp_overrides_list():
    \"\"\"Stub overrides list – phase 1:
    Trả dữ liệu mẫu, sau này có thể thay bằng load từ file JSON hoặc DB.
    JSON schema:
      {
        "ok": true,
        "profile": "EXT+",
        "total_overrides": 2,
        "items": [ ... ]
      }
    \"\"\"
    sample = {
        "ok": True,
        "profile": "EXT+",
        "total_overrides": 2,
        "items": [
            {
                "id": "GITLEAKS_GENERIC_SECRET",
                "tool": "gitleaks",
                "current_severity": "HIGH",
                "override_severity": "LOW",
                "scope": "path:^tests/",
                "description": "Giảm mức cho test data",
                "active": True,
                "affected_count": 23,
            },
            {
                "id": "SEMGREP_PYTHON_SQL",
                "tool": "semgrep",
                "current_severity": "MEDIUM",
                "override_severity": "CRITICAL",
                "scope": None,
                "description": "Tăng mức cho SQL injection patterns",
                "active": True,
                "affected_count": 5,
            },
        ],
    }
    return jsonify(sample)
"""

target.write_text(text.rstrip() + patch + "\n", encoding="utf-8")
print("[PATCH][OVR_BE] Đã append route /api/vsp/overrides/list vào", target)
