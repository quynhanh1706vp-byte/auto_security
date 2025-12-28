#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
APP_PATH="$UI_ROOT/vsp_demo_app.py"

echo "[INFO] UI_ROOT  = $UI_ROOT"
echo "[INFO] APP_PATH = $APP_PATH"

if [ ! -f "$APP_PATH" ]; then
  echo "[ERR] Không tìm thấy vsp_demo_app.py tại $APP_PATH"
  exit 1
fi

export VSP_APP_PATH="$APP_PATH"

python - << 'PY'
import os, textwrap, io, shutil

app_path = os.environ["VSP_APP_PATH"]
print("[PATCH] Target:", app_path)

with open(app_path, "r", encoding="utf-8") as f:
    txt = f.read()

if "def vsp_rule_overrides_ui_v1" in txt:
    print("[SKIP] Đã có vsp_rule_overrides_ui_v1 trong vsp_demo_app.py (bỏ qua).")
else:
    print("[ADD] Thêm stub vsp_rule_overrides_ui_v1 ...")
    stub = textwrap.dedent(
        '''
        @app.route("/api/vsp/rule_overrides_ui_v1", methods=["GET", "POST", "OPTIONS"])
        def vsp_rule_overrides_ui_v1():
            """
            UI-only wrapper cho file config/rule_overrides_v1.json.
            Kết nối tab Rules trên UI với config/rule_overrides_v1.json.
            """
            import os, json, flask

            cfg_dir = os.path.join(os.path.dirname(__file__), "config")
            cfg_path = os.path.join(cfg_dir, "rule_overrides_v1.json")

            # POST: lưu dữ liệu từ UI
            if flask.request.method == "POST":
                try:
                    body = flask.request.get_json(force=True, silent=False)
                except Exception as exc:
                    return flask.jsonify(ok=False, error=str(exc)), 400

                # Hỗ trợ các format khác nhau
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

            # GET: đọc file, nếu chưa có thì trả [].
            if os.path.exists(cfg_path):
                try:
                    with open(cfg_path, "r", encoding="utf-8") as f:
                        raw = json.load(f)
                except Exception as exc:
                    return flask.jsonify(ok=False, error=str(exc), items=[], overrides=[], raw=None), 200
            else:
                raw = []

            # Chuẩn hóa cho UI: luôn có items + overrides
            if isinstance(raw, dict):
                items = raw.get("items") or raw.get("overrides") or raw
            else:
                items = raw

            return flask.jsonify(ok=True, items=items, overrides=items, raw=raw)
        '''
    )

    marker = 'if __name__ == "__main__":'
    if marker in txt:
        before, after = txt.split(marker, 1)
        new_txt = before.rstrip() + "\n\n" + stub + "\n\n" + marker + after
    else:
        new_txt = txt.rstrip() + "\n\n" + stub + "\n"

    backup = app_path + ".bak_rule_overrides_ui_stub"
    shutil.copy2(app_path, backup)
    print("[BACKUP]", backup)

    with open(app_path, "w", encoding="utf-8") as f:
        f.write(new_txt)

    print("[WRITE] Đã append stub vsp_rule_overrides_ui_v1.")

print("[DONE] Patch hoàn tất.")
PY

echo "[NEXT] Giờ bạn restart Flask: python vsp_demo_app.py"
echo "[HINT] Sau khi chạy app, thử: curl -i http://localhost:8910/api/vsp/rule_overrides_ui_v1"
