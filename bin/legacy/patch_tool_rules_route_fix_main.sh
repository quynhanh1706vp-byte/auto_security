#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

# Nếu đã có route rồi thì thôi
if '@app.route("/api/tool_rules"' in text:
    print("[INFO] app.py đã có /api/tool_rules, không chèn thêm.")
else:
    print("[i] Chưa có /api/tool_rules – sẽ chèn trước block main.")

    block = r"""

# === Tool rules API (Data Source) ===
@app.route("/api/tool_rules", methods=["GET"])
def api_get_tool_rules():
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


@app.route("/api/tool_rules", methods=["POST"])
def api_save_tool_rules():
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

    # Tìm block if __name__ == '__main__':
    m = re.search(r"if __name__ == ['\\\"]__main__['\\\"]:", text)
    if not m:
        print("[WARN] Không tìm thấy if __name__ == '__main__':, sẽ append block ở cuối.")
        text = text.rstrip() + block + "\n"
    else:
        start = m.start()
        text = text[:start] + block + "\n\n" + text[start:]
        print("[OK] Đã chèn Tool rules API trước if __name__ == '__main__':")

if text != orig:
    app_path.write_text(text, encoding="utf-8")
PY

python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_tool_rules_route_fix_main.sh hoàn thành."
