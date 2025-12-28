#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$UI_ROOT/vsp_demo_app.py"

echo "[INFO] UI_ROOT  = $UI_ROOT"
echo "[INFO] APP_PATH = $APP_PATH"

if [ ! -f "$APP_PATH" ]; then
  echo "[ERR] Không tìm thấy vsp_demo_app.py tại $APP_PATH"
  exit 1
fi

export VSP_APP_PATH="$APP_PATH"

python - << 'PY'
import os, re, shutil

app_path = os.environ["VSP_APP_PATH"]
print("[PATCH] Target:", app_path)

with open(app_path, "r", encoding="utf-8") as f:
    txt = f.read()

# Backup trước khi đụng vào
backup = app_path + ".bak_rules_fix_20251210"
shutil.copy2(app_path, backup)
print("[BACKUP]", backup)

# 1) Gỡ TẤT CẢ các block route cũ /api/vsp/rule_overrides_ui_v1
pattern = r'@app\.route\("/api/vsp/rule_overrides_ui_v1"[^)]*\)\s*def vsp_rule_overrides_ui_v1\([\s\S]+?(?=\n@|if __name__ == "__main__":|$)'
rx = re.compile(pattern, re.MULTILINE)
new_txt, n = rx.subn("\n", txt)
print(f"[CLEAN] Đã remove {n} block(s) rule_overrides_ui_v1 cũ")

# 2) Append stub mới chuẩn vào TRƯỚC main (nếu có), nếu không thì append cuối file
stub = '''
@app.route("/api/vsp/rule_overrides_ui_v1", methods=["GET", "POST", "OPTIONS"])
def vsp_rule_overrides_ui_v1():
    """
    UI-only wrapper cho file config/rule_overrides_v1.json.
    Dùng riêng cho tab Rules trên VSP_UI 2025.
    """
    import os, json, flask

    cfg_dir = os.path.join(os.path.dirname(__file__), "config")
    cfg_path = os.path.join(cfg_dir, "rule_overrides_v1.json")

    # POST: lưu overrides từ UI
    if flask.request.method == "POST":
        try:
            body = flask.request.get_json(force=True, silent=False)
        except Exception as exc:
            return flask.jsonify(ok=False, error=str(exc)), 400

        # Hỗ trợ các format:
        # - { "items": [...] }
        # - { "overrides": [...] }
        # - [ ... ]
        data = body
        if isinstance(body, dict):
            if "items" in body:
                data = body["items"]
            elif "overrides" in body:
                data = body["overrides"]

        os.makedirs(cfg_dir, exist_ok=True)
        with open(cfg_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

        return flask.jsonify(ok=True)

    # GET: đọc file, nếu chưa có thì trả [] để UI render bảng trống
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, "r", encoding="utf-8") as f:
                raw = json.load(f)
        except Exception as exc:
            return flask.jsonify(ok=False, error=str(exc), items=[], overrides=[], raw=None), 200
    else:
        raw = []

    # Chuẩn hóa: luôn có items + overrides
    if isinstance(raw, dict):
        items = raw.get("items") or raw.get("overrides") or raw
    else:
        items = raw

    return flask.jsonify(ok=True, items=items, overrides=items, raw=raw)
'''

marker = 'if __name__ == "__main__":'
if marker in new_txt:
    head, tail = new_txt.split(marker, 1)
    new_txt2 = head.rstrip() + "\\n\\n" + stub + "\\n\\n" + marker + tail
else:
    new_txt2 = new_txt.rstrip() + "\\n\\n" + stub + "\\n"

with open(app_path, "w", encoding="utf-8") as f:
    f.write(new_txt2)

print("[WRITE] Đã ghi lại vsp_demo_app.py với stub mới cho /api/vsp/rule_overrides_ui_v1.")
PY

echo "[DONE] Fix xong. Giờ restart Flask gateway (python vsp_demo_app.py)."
