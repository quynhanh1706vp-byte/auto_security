#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
echo "[i] ROOT = $ROOT"

for APP in "$ROOT/run_ui_server.py" "$ROOT/app.py"; do
  if [ ! -f "$APP" ]; then
    echo "[INFO] Bỏ qua $APP (không tồn tại)."
    continue
  fi

  echo "[i] Patch $APP ..."
  python3 - "$APP" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã có /api/runs_brief và /api/tools_by_config thì bỏ qua
if "/api/runs_brief" in data and "/api/tools_by_config" in data:
    print(f"[INFO] {path.name} đã có API runs_brief + tools_by_config, bỏ qua.")
    sys.exit(0)

block = r'''

# === AUTO PATCH: API runs_brief + tools_by_config ===
import json as _json
import os as _os
from pathlib import Path as _Path
from datetime import datetime as _dt


try:
    _OUT_DIR = OUT_DIR  # type: ignore[name-defined]
except Exception:
    _OUT_DIR = _Path(__file__).resolve().parent.parent / "out"


def _sb_serialize_runs_brief():
    runs = []
    out_dir = _OUT_DIR
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
                s = _json.load(f)
        except Exception:
            continue

        total = s.get("total")
        crit  = s.get("critical") or s.get("crit") or s.get("C") or 0
        high  = s.get("high") or s.get("H") or 0
        med   = s.get("medium") or s.get("M") or 0
        low   = s.get("low") or s.get("L") or 0

        mt = d.stat().st_mtime
        ts = _dt.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M:%S")

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


try:
    app  # type: ignore[name-defined]
except NameError:
    # Nếu file này không có biến app, bỏ qua block dưới (để tránh lỗi import)
    pass
else:

    @app.route("/api/runs_brief", methods=["GET"])
    def api_runs_brief():
        # Flask 2.x cho phép return list/dict -> tự jsonify
        return _sb_serialize_runs_brief()

    @app.route("/api/runs", methods=["GET"])
    def api_runs():
        return _sb_serialize_runs_brief()

    _TOOL_CFG_PATH = _Path(__file__).resolve().parent / "tool_config.json"


    def _sb_load_tool_config_summary():
        cfg_path = _TOOL_CFG_PATH
        if not cfg_path.is_file():
            return {"tools": []}

        try:
            with cfg_path.open("r", encoding="utf-8") as f:
                cfg = _json.load(f)
        except Exception:
            return {"tools": []}

        if isinstance(cfg, dict):
            if isinstance(cfg.get("tools"), list):
                items = cfg["tools"]
            elif isinstance(cfg.get("config"), list):
                items = cfg["config"]
            else:
                # dạng dict {name: {...}}
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

    @app.route("/api/tools_by_config", methods=["GET"])
    def api_tools_by_config():
        return _sb_load_tool_config_summary()

# === END AUTO PATCH ===

'''

# Append block vào cuối file
data = data.rstrip() + block
path.write_text(data, encoding="utf-8")
print(f"[OK] Đã append API runs_brief + tools_by_config vào {path}")
PY

done

echo "[DONE] patch_api_runs_and_tools_v2.sh hoàn thành."
