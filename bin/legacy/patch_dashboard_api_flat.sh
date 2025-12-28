#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, os, json
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

start = data.find('@app.route("/api/dashboard_data")')
if start == -1:
    print("[ERR] Không tìm thấy route /api/dashboard_data trong app.py")
    raise SystemExit(1)

# Tìm điểm kết thúc block cũ: trước route tiếp theo hoặc trước if __main__
end = data.find('@app.route(', start + 1)
if end == -1:
    end = data.find('if __name__ == "__main__":', start + 1)
if end == -1:
    end = len(data)

new_block = '''@app.route("/api/dashboard_data")
def api_dashboard_data():
    """
    Trả về JSON phẳng cho Dashboard.
    Mặc định: trả y nguyên nội dung summary_unified.json của RUN mới nhất.
    """
    ROOT = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    out_dir = ROOT / "out"

    # giá trị mặc định (khi chưa có dữ liệu)
    default = {
        "run": None,
        "total": 0,
        "critical": 0,
        "high": 0,
        "medium": 0,
        "low": 0,
        "info": 0,
    }

    if not out_dir.is_dir():
        return default

    latest_run = None
    for name in sorted(os.listdir(out_dir)):
        if name.startswith("RUN_2"):  # chỉ lấy RUN_YYYYmmdd_...
            latest_run = name

    if not latest_run:
        return default

    summary_path = out_dir / latest_run / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return default

    try:
        with summary_path.open("r", encoding="utf-8") as f:
            summary = json.load(f)
    except Exception:
        return default

    # đảm bảo có các key chính, và thêm run id
    summary.setdefault("total", 0)
    summary.setdefault("critical", summary.get("crit", 0))
    summary.setdefault("high", 0)
    summary.setdefault("medium", 0)
    summary.setdefault("low", 0)
    summary.setdefault("info", 0)
    summary["run"] = latest_run

    return summary
'''

new_data = data[:start] + new_block + "\n\n" + data[end:]
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã thay thế route /api/dashboard_data bằng phiên bản trả JSON phẳng.")
PY
