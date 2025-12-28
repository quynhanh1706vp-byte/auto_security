#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${UI_ROOT}/vsp_demo_app.py"

if [ ! -f "$TARGET" ]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${TARGET}.bak_dashboard_${TS}"

cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

export UI_ROOT

python - << 'PY'
import os
import re
import pathlib

ui_root = pathlib.Path(os.environ["UI_ROOT"])
target = ui_root / "vsp_demo_app.py"

txt = target.read_text(encoding="utf-8")

# Khối mới cho dashboard_v3
new_dashboard_block = '''
@app.route("/api/vsp/dashboard_v3", methods=["GET"])
def vsp_dashboard_v3():
    """
    Dashboard V3:
      - Chọn run theo:
        + Pin trong vsp_dashboard_pin_v1.json, hoặc
        + FULL_EXT mới nhất có summary_unified.json
      - Trả total_findings + by_severity + by_tool
    """
    import json
    from flask import request, jsonify

    run_id = request.args.get("run_id") or pick_dashboard_run()

    if not run_id:
        return jsonify({
            "ok": False,
            "error": "No FULL_EXT run with summary_unified.json found",
            "latest_run_id": None,
        }), 500

    summary_file = (OUT_DIR / run_id / "report" / "summary_unified.json")

    if not summary_file.is_file():
        return jsonify({
            "ok": False,
            "error": f"summary_unified.json not found for {run_id}",
            "latest_run_id": run_id,
        }), 500

    summary = json.loads(summary_file.read_text(encoding="utf-8"))

    data = {
        "ok": True,
        "latest_run_id": run_id,
        "total_findings": summary["summary_all"]["total_findings"],
        "by_severity": summary["summary_by_severity"],
        "by_tool": summary.get("by_tool", {}),
    }
    return jsonify(data)
'''.lstrip('\n')

# Regex đơn giản: tìm bất kỳ @app.route("/api/vsp/dashboard_v3"...)
pattern_dashboard = (
    r'@app\.route\("/api/vsp/dashboard_v3"[^)]*\)\s*'
    r'def vsp_dashboard_v3\([^)]*\):'
    r'.*?(?=\n@\w+\.route\(|\Z)'
)

txt_new, n_dash = re.subn(pattern_dashboard, new_dashboard_block + "\n\n", txt, flags=re.DOTALL)

if n_dash == 0:
    print("[WARN] Vẫn không tìm thấy route /api/vsp/dashboard_v3, sẽ chèn thêm block mới ở cuối file.")
    if '@app.route("/api/vsp/dashboard_v3"' in txt:
        print("[WARN] ĐÃ tồn tại decorator dashboard_v3, có thể bị trùng. Cần soi tay.")
    txt_new = txt.rstrip() + "\n\n" + new_dashboard_block + "\n"
    n_dash = 1
    print("[PATCH] Đã chèn thêm block dashboard_v3 mới ở cuối file.")

print(f"[PATCH] dashboard_v3: {n_dash} block(s) cập nhật/chèn")

target.write_text(txt_new, encoding="utf-8")
print("[DONE] Đã cập nhật vsp_demo_app.py (dashboard_v3)")
PY
