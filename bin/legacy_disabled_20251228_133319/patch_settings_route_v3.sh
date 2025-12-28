#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/app.py"

echo "[i] ROOT = $ROOT"
cd "$ROOT"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP" >&2
  exit 1
fi

cp "$APP" "${APP}.bak_settings_v3_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
import pathlib, re, textwrap, json

path = pathlib.Path("app.py")
data = path.read_text(encoding="utf-8")

def patch_route(pattern, new_block, label):
    global data
    m = re.search(pattern, data, flags=re.DOTALL)
    if not m:
        print(f"[WARN] Không tìm thấy route {label}, giữ nguyên.")
        return
    data = data[:m.start()] + textwrap.dedent(new_block).lstrip("\n") + "\n\n" + data[m.end():]
    print(f"[OK] Đã patch route {label}.")

# Patch lại route /settings với parser “dễ tính”
patch_route(
    r"@app\\.route\\(\"/settings\"[^\n]*\\)\\s+def\\s+settings\\([^)]*\\):.*?(?=\\n@app\\.route|\\nif __name__ == \"__main__\"|$)",
    '''
    @app.route("/settings", methods=["GET", "POST"])
    def settings():
        """
        Settings – đọc tool_config.json và render bảng.
        Hỗ trợ các format:
        - [ {...}, {...} ]
        - { "tools": [ {...}, {...} ] }
        - {..},{..},{..}  (không bọc trong [] – sẽ tự bọc lại)
        """
        from pathlib import Path as _Path

        cfg_path = _Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json")
        tools = []
        raw_text = ""
        if cfg_path.exists():
            raw_text = cfg_path.read_text(encoding="utf-8")

            # Thử parse JSON chuẩn trước
            parsed = None
            if raw_text.strip():
                try:
                    parsed = json.loads(raw_text)
                except Exception:
                    # Thử bọc lại thành list: [{...},{...},...]
                    hacked = "[" + raw_text.strip().rstrip(",") + "]"
                    try:
                        parsed = json.loads(hacked)
                    except Exception:
                        parsed = None

            if isinstance(parsed, dict) and isinstance(parsed.get("tools"), list):
                tools = parsed["tools"]
            elif isinstance(parsed, list):
                tools = parsed

        # Luôn show raw_text ở block debug
        raw_str = raw_text

        # TODO: xử lý POST -> lưu thay đổi nếu cần
        if request.method == "POST":
            pass

        return render_template(
            "settings.html",
            cfg_path=str(cfg_path),
            cfg_rows=tools,
            table_rows=tools,
            rows=tools,
            cfg_raw=raw_str,
        )
    ''',
    "settings"
)

path.write_text(data, encoding="utf-8")
print("[OK] app.py updated (settings v3).")
PY

echo "[DONE] patch_settings_route_v3.sh hoàn thành."
