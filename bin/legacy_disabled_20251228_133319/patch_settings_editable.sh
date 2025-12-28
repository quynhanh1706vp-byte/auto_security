#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
APP="app.py"

python3 - <<'PY'
from pathlib import Path
import textwrap

path = Path("app.py")
data = path.read_text(encoding="utf-8")

marker = '@app.route("/settings")'
idx = data.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy route /settings trong app.py")
    raise SystemExit(1)

end = data.find('@app.route("', idx+1)
if end == -1:
    end = data.find('if __name__ == "__main__"', idx+1)

new_block = textwrap.dedent('''
@app.route("/settings", methods=["GET", "POST"])
def settings():
    """Trang Settings – hiển thị tool_config.json + cho phép chỉnh Level / Modes / Enabled."""
    from pathlib import Path
    import json

    ROOT = Path(__file__).resolve().parent.parent
    cfg_path = ROOT / "ui" / "tool_config.json"

    tools = []
    raw_json = ""
    if cfg_path.exists():
        raw_json = cfg_path.read_text(encoding="utf-8")
        try:
            js = json.loads(raw_json)
            tools = js.get("tools") or js
        except Exception:
            tools = []

    # Handle update from form
    if request.method == "POST" and tools:
        changed = False
        for idx, t in enumerate(tools):
            prefix = f"tool-{idx}-"
            enabled_val = request.form.get(prefix + "enabled")
            level_val = request.form.get(prefix + "level")
            modes_val = request.form.get(prefix + "modes")

            if enabled_val is not None:
                new_enabled = enabled_val.upper() == "ON"
                if bool(t.get("enabled", True)) != new_enabled:
                    t["enabled"] = new_enabled
                    changed = True

            if level_val is not None and level_val != t.get("level"):
                t["level"] = level_val
                changed = True

            if modes_val is not None:
                modes_list = [m.strip() for m in modes_val.split(",") if m.strip()]
                if modes_list and modes_list != t.get("modes"):
                    t["modes"] = modes_list
                    changed = True

        if changed:
            out = {"tools": tools}
            cfg_path.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
            raw_json = cfg_path.read_text(encoding="utf-8")

    return render_template(
        "settings.html",
        tools=tools,
        cfg_path=str(cfg_path),
        raw_json=raw_json,
    )
''')

new_data = data[:idx] + new_block + data[end:]
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã patch route /settings (editable).")
PY
