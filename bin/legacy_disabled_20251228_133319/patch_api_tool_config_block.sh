#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

marker = "# 4) BY TOOL / CONFIG từ ui/tool_config.json"
start = code.find(marker)
if start == -1:
    print("[ERR] Không tìm thấy marker BY TOOL / CONFIG trong app.py")
    sys.exit(1)

resp_idx = code.find("resp = {", start)
if resp_idx == -1:
    print("[ERR] Không tìm thấy 'resp = {' sau marker trong api_dashboard_data")
    sys.exit(1)

before = code[:start]
after = code[resp_idx:]

new_block = '''# 4) BY TOOL / CONFIG từ ui/tool_config.json
    try:
        cfg_path = pathlib.Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json")
        if cfg_path.is_file():
            import json as _json3
            with cfg_path.open("r", encoding="utf-8") as f:
                cfg = _json3.load(f)

            rows = []
            tools_list = []
            raw = cfg

            # Hỗ trợ 3 dạng:
            # 1) [ {...}, {...} ]
            # 2) { "tools": [ {...}, {...} ] }
            # 3) { "semgrep": {...}, "trivy": {...}, ... }
            if isinstance(raw, list):
                tools_list = raw
            elif isinstance(raw, dict):
                if isinstance(raw.get("tools"), list):
                    tools_list = raw["tools"]
                else:
                    for k, v in raw.items():
                        if isinstance(v, dict):
                            item = dict(v)
                            item.setdefault("name", k)
                            tools_list.append(item)

            for t in tools_list:
                if not isinstance(t, dict):
                    continue
                name = t.get("name") or t.get("tool") or "—"
                enabled = bool(t.get("enabled", True))
                level = t.get("level") or t.get("profile") or "—"
                modes = t.get("modes") or t.get("mode") or {}
                modes_str = "—"
                if isinstance(modes, dict):
                    on_modes = [str(k).upper() for k, v in modes.items() if v]
                    modes_str = ", ".join(on_modes) if on_modes else "—"
                elif isinstance(modes, (list, tuple)):
                    modes_str = ", ".join(str(x).upper() for x in modes) or "—"
                elif modes:
                    modes_str = str(modes)

                rows.append({
                    "name": name,
                    "enabled": enabled,
                    "level": level,
                    "modes": modes_str,
                })
            tool_rows = rows
    except Exception as e:
        print(f"[WARN][API] Lỗi đọc tool_config.json: {e}")
'''

code_new = before + new_block + "\n" + after
path.write_text(code_new, encoding="utf-8")
print("[OK] Đã patch block BY TOOL / CONFIG trong /api/dashboard_data.")
PY
