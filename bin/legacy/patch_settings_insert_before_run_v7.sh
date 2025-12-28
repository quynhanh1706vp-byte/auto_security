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

cp "$APP" "${APP}.bak_settings_v7_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
from pathlib import Path
import json as _json

path = Path("app.py")
data = path.read_text(encoding="utf-8")

if '"/settings_latest"' in data:
    print("[INFO] Route /settings_latest đã tồn tại, bỏ qua append.")
else:
    idx = data.find("app.run(")
    if idx == -1:
        print("[ERR] Không tìm thấy 'app.run(' trong app.py")
        raise SystemExit(1)

    block = '''
# ==== SETTINGS_LATEST_INSERT_V7 ====
@app.route("/settings_latest", methods=["GET", "POST"])
def settings_latest():
    """
    Settings LATEST – đọc /ui/tool_config.json và render bảng BY TOOL / CONFIG.
    Hỗ trợ:
    - [ {...}, {...} ]
    - { "tools": [ {...}, {...} ] }
    - {..},{..},{..} (nhiều object không bọc [])
    """
    from pathlib import Path as _Path
    import json as _json

    cfg_path = _Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json")
    print(f"[INFO][SETTINGS_LATEST] cfg_path={cfg_path} exists={cfg_path.exists()}")

    tools = []
    raw_text = ""
    if cfg_path.exists():
        try:
            raw_text = cfg_path.read_text(encoding="utf-8")
            print(f"[INFO][SETTINGS_LATEST] len(raw_text)={len(raw_text)}")
        except Exception as e:
            print(f"[ERR][SETTINGS_LATEST] read_text failed: {e}")
    else:
        print("[WARN][SETTINGS_LATEST] tool_config.json not found")

    parsed = None
    txt = raw_text.strip()

    if txt:
        # 1) Thử JSON chuẩn
        try:
            parsed = _json.loads(txt)
            print("[INFO][SETTINGS_LATEST] json.loads OK (chuẩn).")
        except Exception as e1:
            print(f"[WARN][SETTINGS_LATEST] json.loads failed: {e1}")
            # 2) Tự tách thành các block { ... } theo depth
            chunks = []
            cur = ""
            depth = 0
            for ch in txt:
                cur += ch
                if ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                    if depth == 0 and cur.strip():
                        chunks.append(cur)
                        cur = ""
            items = []
            for c in chunks:
                s = c.strip()
                if s.endswith(','):
                    s = s[:-1]
                try:
                    items.append(_json.loads(s))
                except Exception as e2:
                    print(f"[ERR][SETTINGS_LATEST] parse chunk failed: {e2}")
            if items:
                parsed = items
                print(f"[INFO][SETTINGS_LATEST] parsed {len(items)} tool objects từ chunks.")

    if isinstance(parsed, dict) and isinstance(parsed.get("tools"), list):
        tools = parsed["tools"]
    elif isinstance(parsed, list):
        tools = parsed

    print(f"[INFO][SETTINGS_LATEST] rows={len(tools)}")

    return render_template(
        "settings.html",
        cfg_path=str(cfg_path),
        cfg_rows=tools,
        table_rows=tools,
        rows=tools,
        cfg_raw=raw_text,
    )
# ==== END SETTINGS_LATEST_INSERT_V7 ====

'''
    data = data[:idx] + block + "\n" + data[idx:]
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn block SETTINGS_LATEST_INSERT_V7 trước app.run().")
PY

echo "[DONE] patch_settings_insert_before_run_v7.sh hoàn thành."
