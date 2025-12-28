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

cp "$APP" "${APP}.bak_settings_v4_$(date +%Y%m%d_%H%M%S)" || true
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

# -------- Patch /settings với parser dễ tính + debug rõ ràng ----------
patch_route(
    r"@app\\.route\\(\"/settings\"[^\n]*\\)\\s+def\\s+settings\\([^)]*\\):.*?(?=\\n@app\\.route|\\nif __name__ == \"__main__\"|$)",
    '''
    @app.route("/settings", methods=["GET", "POST"])
    def settings():
        """
        Settings – đọc tool_config.json và render bảng.
        Hỗ trợ:
        - [ {...}, {...} ]
        - { "tools": [ {...}, {...} ] }
        - {..},{..},{..} (không bọc trong [] – sẽ tự bọc lại)
        """
        from pathlib import Path as _Path

        cfg_path = _Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json")
        print(f"[INFO][SETTINGS] cfg_path={cfg_path} exists={cfg_path.exists()}")

        tools = []
        raw_text = ""
        if cfg_path.exists():
            try:
                raw_text = cfg_path.read_text(encoding="utf-8")
                print(f"[INFO][SETTINGS] len(raw_text)={len(raw_text)}")
            except Exception as e:
                print(f"[ERR][SETTINGS] read_text failed: {e}")
        else:
            print("[WARN][SETTINGS] tool_config.json not found")

        parsed = None
        if raw_text.strip():
            try:
                parsed = json.loads(raw_text)
                print("[INFO][SETTINGS] json.loads OK (format chuẩn).")
            except Exception as e1:
                print(f"[WARN][SETTINGS] json.loads failed once: {e1}")
                hacked = "[" + raw_text.strip().rstrip(",") + "]"
                try:
                    parsed = json.loads(hacked)
                    print("[INFO][SETTINGS] json.loads hacked OK (bọc bằng []).")
                except Exception as e2:
                    print(f"[ERR][SETTINGS] json parse failed: {e2}")

        if isinstance(parsed, dict) and isinstance(parsed.get("tools"), list):
            tools = parsed["tools"]
        elif isinstance(parsed, list):
            tools = parsed

        print(f"[INFO][SETTINGS] rows={len(tools)}")

        raw_str = raw_text  # luôn show nguyên văn file

        # TODO: xử lý POST (Save changes) sau, giờ chỉ đọc.
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
    "settings",
)

path.write_text(data, encoding="utf-8")
print("[OK] app.py updated (settings v4).")
PY

echo "[DONE] patch_settings_route_v4.sh hoàn thành."
