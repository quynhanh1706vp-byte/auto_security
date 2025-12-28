#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${UI_ROOT}/vsp_demo_app.py"

if [ ! -f "$TARGET" ]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${TARGET}.bak_routes_${TS}"

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

# 1) Thêm import helper nếu chưa có
IMPORT_LINE = "from vsp_run_picker_v1 import pick_dashboard_run, OUT_DIR\n"

if IMPORT_LINE.strip() not in txt:
    m = re.search(r"from flask import [^\n]+\n", txt)
    if not m:
        raise SystemExit("[ERR] Không tìm thấy dòng 'from flask import ...' để chèn import.")
    insert_at = m.start()
    txt = txt[:insert_at] + IMPORT_LINE + txt[insert_at:]
    print("[PATCH] Đã chèn import vsp_run_picker_v1")

# 2) Thay route /api/vsp/dashboard_v3
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

pattern_dashboard = (
    r'@app\.route\("/api/vsp/dashboard_v3", methods=\["GET"\]\)\s+'
    r'def vsp_dashboard_v3\([^)]*\):.*?(?=\n@app\.route\("|$)'
)

txt_new, n_dash = re.subn(pattern_dashboard, new_dashboard_block + "\n\n", txt, flags=re.DOTALL)

if n_dash == 0:
    print("[WARN] Không tìm thấy route /api/vsp/dashboard_v3 để thay.")
else:
    print(f"[PATCH] Đã thay route dashboard_v3 ({n_dash} match)")

txt = txt_new

# 3) Thay route /api/vsp/run_fullscan_v1
new_run_block = '''
@app.route("/api/vsp/run_fullscan_v1", methods=["POST"])
def vsp_run_fullscan_v1():
    """
    Nhận source_root / target_url / profile / mode từ UI,
    gọi shell wrapper vsp_run_fullscan_from_api_v1.sh chạy background.
    """
    import subprocess
    from pathlib import Path
    from flask import request, jsonify

    payload = request.get_json(force=True) or {}
    source_root = payload.get("source_root") or ""
    target_url = payload.get("target_url") or ""
    profile = payload.get("profile") or "FULL_EXT"
    mode = payload.get("mode") or "EXT_ONLY"

    wrapper = Path(__file__).resolve().parent.parent / "bin" / "vsp_run_fullscan_from_api_v1.sh"

    proc = subprocess.Popen(
        [str(wrapper), profile, mode, source_root, target_url],
        cwd=str(wrapper.parent.parent),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    app.logger.info("[VSP_RUN_FULLSCAN_API] payload=%s pid=%s", payload, proc.pid)

    return jsonify({
        "ok": True,
        "pid": proc.pid,
        "profile": profile,
        "mode": mode,
    })
'''.lstrip('\n')

pattern_run = (
    r'@app\.route\("/api/vsp/run_fullscan_v1", methods=\["POST"\]\)\s+'
    r'def vsp_run_fullscan_v1\([^)]*\):.*?(?=\n@app\.route\("|$)'
)

txt_new, n_run = re.subn(pattern_run, new_run_block + "\n\n", txt, flags=re.DOTALL)

if n_run == 0:
    print("[WARN] Không tìm thấy route /api/vsp/run_fullscan_v1 để thay.")
else:
    print(f"[PATCH] Đã thay route run_fullscan_v1 ({n_run} match)")

target.write_text(txt_new, encoding="utf-8")
print("[DONE] Đã cập nhật vsp_demo_app.py")
PY
