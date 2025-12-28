#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

python3 - <<'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

# Nếu chưa có route /api/tool_rules thì append block mới ở cuối file
if '@app.route("/api/tool_rules"' not in text:
    block = '''

# === Tool rules API (appended block) ===
try:
    RULES_PATH
except NameError:
    from pathlib import Path as _Path
    RULES_PATH = _Path(__file__).resolve().parent.parent / "tool_rules.json"


@app.route("/api/tool_rules", methods=["GET"])
def api_get_tool_rules():
    import json
    from flask import jsonify
    if RULES_PATH.exists():
        try:
            data = json.loads(RULES_PATH.read_text(encoding="utf-8"))
        except Exception:
            data = []
    else:
        data = []
    if not isinstance(data, list):
        data = []
    return jsonify({"ok": True, "path": str(RULES_PATH), "rules": data})


@app.route("/api/tool_rules", methods=["POST"])
def api_save_tool_rules():
    import json
    from flask import request, jsonify
    payload = request.get_json(force=True, silent=True) or {}
    rules = payload.get("rules", [])
    if not isinstance(rules, list):
        return jsonify({"ok": False, "error": "rules must be a list"}), 400
    RULES_PATH.write_text(
        json.dumps(rules, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return jsonify({"ok": True, "saved": len(rules), "path": str(RULES_PATH)})
'''
    text = text.rstrip() + block + "\n"
    print("[OK] Appended tool_rules block at end of app.py")
else:
    print("[INFO] app.py đã có route /api/tool_rules, không động đến.")

if text != orig:
    app_path.write_text(text, encoding="utf-8")
PY

# Check syntax xem app.py có lỗi không
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_tool_rules_route_append.sh hoàn thành."
