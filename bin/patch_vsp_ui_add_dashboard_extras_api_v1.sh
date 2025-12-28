#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"

if [ ! -f "$APP" ]; then
  echo "[PATCH] Không tìm thấy $APP"
  exit 1
fi

cp "$APP" "$APP.bak_dashboard_extras_v1_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path
import re, textwrap

ROOT = Path(__file__).resolve().parents[1]
app_path = ROOT / "vsp_demo_app.py"
txt = app_path.read_text(encoding="utf-8")

if "def api_vsp_dashboard_extras_v2" in txt:
    print("[PATCH] Route api_vsp_dashboard_extras_v2 đã tồn tại, bỏ qua.")
else:
    snippet = '''
@app.route("/api/vsp/dashboard_extras_v2")
def api_vsp_dashboard_extras_v2():
    """
    Trả thêm dữ liệu cho chart dashboard: trend_by_run, top_cwe_list, by_tool.
    Đọc trực tiếp từ out/vsp_dashboard_v3_latest.json.
    """
    import json
    from pathlib import Path

    root = Path(__file__).resolve().parents[1]
    dash_path = root / "out" / "vsp_dashboard_v3_latest.json"
    if not dash_path.is_file():
        return jsonify({"ok": False, "error": f"Không tìm thấy {dash_path.name}"})

    try:
        data = json.loads(dash_path.read_text(encoding="utf-8"))
    except Exception as e:
        return jsonify({"ok": False, "error": f"Error reading dashboard_v3_latest.json: {e}"})

    return jsonify({
        "ok": True,
        "by_tool": data.get("by_tool"),
        "trend_by_run": data.get("trend_by_run"),
        "top_cwe_list": data.get("top_cwe_list"),
    })
'''
    m = re.search(r'if __name__ == .__main__.:', txt)
    if m:
        idx = m.start()
        new_txt = txt[:idx] + textwrap.dedent(snippet) + "\n\n" + txt[idx:]
    else:
        new_txt = txt + "\n\n" + textwrap.dedent(snippet) + "\n"

    app_path.write_text(new_txt, encoding="utf-8")
    print("[PATCH] Đã thêm route api_vsp_dashboard_extras_v2 vào", app_path)
PY
