#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

marker = 'if __name__ == "__main__":'
if marker not in data:
    print("[ERR] Không tìm thấy 'if __name__ == \"__main__\":' trong app.py")
    raise SystemExit(1)

block = '''
@app.route("/api/dashboard_data")
def api_dashboard_data():
    """
    Trả về JSON cho Dashboard.
    Luôn trả HTTP 200, kể cả khi lỗi, để front-end không dính 404.
    """
    import json, os
    from pathlib import Path

    ROOT = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    out_dir = ROOT / "out"

    result = {
        "ok": False,
        "error": None,
        "run": None,
        "data": None,
    }

    if not out_dir.is_dir():
        result["error"] = f"Not found: {out_dir}"
        return result

    latest_run = None
    for name in sorted(os.listdir(out_dir)):
        if name.startswith("RUN_"):
            latest_run = name

    if not latest_run:
        result["error"] = "No RUN_* found in out/"
        return result

    summary_path = out_dir / latest_run / "report" / "summary_unified.json"
    result["run"] = latest_run

    if not summary_path.is_file():
        result["error"] = f"Not found: {summary_path}"
        return result

    try:
        with summary_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        result["error"] = f"Load JSON error: {e}"
        return result

    result["ok"] = True
    result["data"] = data
    return result
'''

# Nếu đúng chính xác block này đã có thì thôi, không chèn lại
if block.strip() in data:
    print("[OK] Block /api/dashboard_data chuẩn đã tồn tại (trước hoặc sau), bỏ qua.")
    raise SystemExit(0)

# Chèn block TRƯỚC dòng 'if __name__ == "__main__":'
new_data = data.replace(marker, block + "\n\n" + marker, 1)
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn route /api/dashboard_data TRƯỚC if __main__ trong app.py")
PY
