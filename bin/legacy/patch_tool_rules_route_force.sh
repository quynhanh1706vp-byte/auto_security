#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

# 1) Đảm bảo có RULES_PATH
if "RULES_PATH" not in text:
    m = re.search(r"^ROOT\s*=.*$", text, flags=re.MULTILINE)
    if m:
        insert = m.group(0) + '\nRULES_PATH = ROOT / "tool_rules.json"'
        text = text[:m.start()] + insert + text[m.end():]
        print("[OK] Đã chèn RULES_PATH sau ROOT")
    else:
        text += '\nRULES_PATH = Path(__file__).resolve().parent.parent / "tool_rules.json"\n'
        print("[WARN] Không tìm thấy ROOT, thêm RULES_PATH ở cuối file")

# 2) Thêm block API nếu chưa có
if "api_get_tool_rules" not in text:
    block = r"""

# === Tool rules API (Data Source override rules) ===
@app.route("/api/tool_rules", methods=["GET"])
def api_get_tool_rules():
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
    payload = request.get_json(force=True, silent=True) or {}
    rules = payload.get("rules", [])
    if not isinstance(rules, list):
        return jsonify({"ok": False, "error": "rules must be a list"}), 400
    RULES_PATH.write_text(
        json.dumps(rules, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return jsonify({"ok": True, "saved": len(rules), "path": str(RULES_PATH)})
"""
    # chèn block này ngay trước if __name__ == '__main__'
    marker = None
    for cand in ("if __name__ == \"__main__\":", "if __name__ == '__main__':"):
        pos = text.find(cand)
        if pos != -1:
            marker = (cand, pos)
            break

    if marker is None:
        text = text + block + "\n"
        print("[OK] Đã append Tool rules API ở cuối file")
    else:
        cand, pos = marker
        text = text[:pos] + block + "\n" + text[pos:]
        print("[OK] Đã chèn Tool rules API trước", cand)
else:
    print("[INFO] Đã có api_get_tool_rules, không chèn thêm")

if text != orig:
    app_path.write_text(text, encoding="utf-8")
PY

echo "[DONE] Force-patch tool_rules API route."
