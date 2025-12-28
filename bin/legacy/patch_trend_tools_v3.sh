#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/run_ui_server.py"
echo "[i] ROOT = $ROOT"
echo "[i] APP  = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã có v2 rồi thì bỏ qua
if "/api/runs_v2" in data and "/api/tools_config_v2" in data:
    print("[INFO] run_ui_server.py đã có API v2, bỏ qua.")
    sys.exit(0)

block = r'''

# === AUTO PATCH V3: API /api/runs_v2 + /api/tools_config_v2 ===
import json as _json_v3
from pathlib import Path as _Path_v3
from datetime import datetime as _dt_v3

try:
    app  # type: ignore[name-defined]
except NameError:
    # nếu không có biến app thì thôi, tránh lỗi import
    pass
else:
    def _sb_v3_get_out_dir():
        # gốc = thư mục SECURITY_BUNDLE
        return _Path_v3(__file__).resolve().parent.parent / "out"

    def _sb_v3_serialize_runs():
        out_dir = _sb_v3_get_out_dir()
        runs = []
        if not out_dir.is_dir():
            return runs

        for d in sorted(out_dir.glob("RUN_2*")):
            if not d.is_dir():
                continue
            name = d.name
            if name.startswith("RUN_GITLEAKS_EXT_") or name.startswith("RUN_DEMO_"):
                continue
            report_dir = d / "report"
            summary_path = report_dir / "summary_unified.json"
            if not summary_path.is_file():
                continue
            try:
                with summary_path.open("r", encoding="utf-8") as f:
                    s = _json_v3.load(f)
            except Exception:
                continue

            total = s.get("total")
            crit  = s.get("critical") or s.get("crit") or s.get("C") or 0
            high  = s.get("high") or s.get("H") or 0
            med   = s.get("medium") or s.get("M") or 0
            low   = s.get("low") or s.get("L") or 0

            mt = d.stat().st_mtime
            ts = _dt_v3.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M:%S")

            runs.append({
                "run": name,
                "time": ts,
                "total": total,
                "critical": crit,
                "high": high,
                "medium": med,
                "low": low,
            })

        runs.sort(key=lambda x: x.get("run") or "", reverse=True)
        return runs

    @app.route("/api/runs_v2", methods=["GET"])
    def api_runs_v2():
        return _sb_v3_serialize_runs()

    def _sb_v3_load_tool_config():
        cfg_path = _Path_v3(__file__).resolve().parent / "tool_config.json"
        if not cfg_path.is_file():
            return {"tools": []}
        try:
            with cfg_path.open("r", encoding="utf-8") as f:
                cfg = _json_v3.load(f)
        except Exception:
            return {"tools": []}

        if isinstance(cfg, dict):
            if isinstance(cfg.get("tools"), list):
                items = cfg["tools"]
            elif isinstance(cfg.get("config"), list):
                items = cfg["config"]
            else:
                vals = list(cfg.values())
                items = vals if vals and isinstance(vals[0], dict) else []
        elif isinstance(cfg, list):
            items = cfg
        else:
            items = []

        rows = []

        def _b(val):
            if isinstance(val, bool):
                return val
            if isinstance(val, (int, float)):
                return val != 0
            if isinstance(val, str):
                return val.strip().lower() in ("1", "true", "yes", "y", "on")
            return False

        for idx, item in enumerate(items):
            if not isinstance(item, dict):
                continue

            name = (
                item.get("tool")
                or item.get("name")
                or item.get("id")
                or f"tool_{idx+1}"
            )

            enabled = (
                _b(item.get("enabled"))
                or _b(item.get("enable"))
                or _b(item.get("ENABLED"))
                or _b(item.get("ENABLE"))
            )

            level = (
                item.get("profile")
                or item.get("level")
                or item.get("mode")
                or item.get("severity")
                or ""
            )

            modes = []
            for key, label in [
                ("mode_offline", "Offline"),
                ("mode_online", "Online"),
                ("mode_ci", "CI/CD"),
                ("offline", "Offline"),
                ("online", "Online"),
                ("ci_cd", "CI/CD"),
                ("ci", "CI/CD"),
            ]:
                if key in item and _b(item.get(key)):
                    modes.append(label)

            modes_str = ", ".join(sorted(set(modes))) if modes else ""

            rows.append({
                "tool": name,
                "enabled": enabled,
                "level": level,
                "modes": modes_str,
            })

        return {"tools": rows}

    @app.route("/api/tools_config_v2", methods=["GET"])
    def api_tools_config_v2():
        return _sb_v3_load_tool_config()

# === END AUTO PATCH V3 ===

'''

data = data.rstrip() + block
path.write_text(data, encoding="utf-8")
print("[OK] Đã append AUTO PATCH V3 vào", path)
PY

echo "[DONE] patch_trend_tools_v3.sh hoàn thành."
