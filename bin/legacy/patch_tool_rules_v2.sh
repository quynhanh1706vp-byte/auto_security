#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$UI/app.py"
JS="$UI/static/js/datasource_tool_rules.js"

echo "[i] UI = $UI"

# 1) Sửa JS: dùng /api/tool_rules_v2 thay vì /api/tool_rules
if [ -f "$JS" ]; then
  python3 - <<'PY'
from pathlib import Path

js = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/datasource_tool_rules.js")
data = js.read_text(encoding="utf-8")
orig = data

data = data.replace("/api/tool_rules\"", "/api/tool_rules_v2\"")
data = data.replace("/api/tool_rules'", "/api/tool_rules_v2'")
data = data.replace("/api/tool_rules", "/api/tool_rules_v2")

if data != orig:
    js.write_text(data, encoding="utf-8")
    print("[OK] Đã chuyển JS sang dùng /api/tool_rules_v2")
else:
    print("[INFO] JS đã dùng /api/tool_rules_v2 hoặc không có chuỗi cần đổi")
PY
else
  echo "[WARN] Không tìm thấy $JS"
fi

# 2) Thêm route /api/tool_rules_v2 vào app.py (chèn TRƯỚC app.run)
python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

if '"/api/tool_rules_v2"' in text:
    print("[INFO] app.py đã có /api/tool_rules_v2, bỏ qua chèn route.")
else:
    block = r"""

# === Tool rules API v2 (Data Source) ===
@app.route("/api/tool_rules_v2", methods=["GET"])
def api_tool_rules_v2_get():
    from pathlib import Path as _Path
    import json
    from flask import jsonify
    rules_path = _Path(__file__).resolve().parent.parent / "tool_rules.json"
    if rules_path.exists():
        try:
            data = json.loads(rules_path.read_text(encoding="utf-8"))
        except Exception:
            data = []
    else:
        data = []
    if not isinstance(data, list):
        data = []
    return jsonify({"ok": True, "path": str(rules_path), "rules": data})


@app.route("/api/tool_rules_v2", methods=["POST"])
def api_tool_rules_v2_post():
    from pathlib import Path as _Path
    import json
    from flask import request, jsonify
    rules_path = _Path(__file__).resolve().parent.parent / "tool_rules.json"
    payload = request.get_json(force=True, silent=True) or {}
    rules = payload.get("rules", [])
    if not isinstance(rules, list):
        return jsonify({"ok": False, "error": "rules must be a list"}), 400
    rules_path.write_text(
        json.dumps(rules, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return jsonify({"ok": True, "saved": len(rules), "path": str(rules_path)})
"""

    m = re.search(r"app\.run\s*\(", text)
    if m:
        # chèn block ngay TRƯỚC dòng app.run (tức là trước if __name__ == '__main__' hoặc trong block đó)
        line_start = text.rfind("\n", 0, m.start())
        if line_start == -1:
            line_start = 0
        insert_pos = line_start
        text = text[:insert_pos] + block + "\n\n" + text[insert_pos:]
        print("[OK] Đã chèn Tool rules API v2 trước app.run(...)")
    else:
        # fallback: append ở cuối (trường hợp hiếm)
        text = text.rstrip() + block + "\n"
        print("[WARN] Không tìm thấy app.run(...), append block ở cuối file")

if text != orig:
    app_path.write_text(text, encoding="utf-8")
PY

# 3) Check syntax app.py
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_tool_rules_v2.sh hoàn thành."
