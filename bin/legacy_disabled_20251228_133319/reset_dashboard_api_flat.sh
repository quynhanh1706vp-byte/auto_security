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

lines = data.splitlines(keepends=True)
out_lines = []
skip = False
saw_old = False

for line in lines:
    if not skip and '@app.route("/api/dashboard_data"' in line:
        # bắt đầu block cũ -> bỏ
        skip = True
        saw_old = True
        continue
    if skip:
        # kết thúc block khi gặp route mới hoặc if __main__
        stripped = line.lstrip()
        if stripped.startswith('@app.route(') or line.startswith('if __name__ == "__main__":'):
            skip = False
            out_lines.append(line)
        # còn đang trong block cũ thì bỏ qua
        continue
    else:
        out_lines.append(line)

cleaned = "".join(out_lines)

marker = 'if __name__ == "__main__":'
if marker not in cleaned:
    print("[ERR] Không tìm thấy 'if __name__ == \"__main__\":' trong app.py")
    raise SystemExit(1)

new_block = '''@app.route("/api/dashboard_data")
def api_dashboard_data():
    """
    Trả về JSON phẳng cho Dashboard.
    Trả y nguyên nội dung summary_unified.json của RUN_* mới nhất.
    """
    import json, os
    from pathlib import Path

    ROOT = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    out_dir = ROOT / "out"

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

    summary.setdefault("total", 0)
    summary.setdefault("critical", summary.get("crit", 0))
    summary.setdefault("high", 0)
    summary.setdefault("medium", 0)
    summary.setdefault("low", 0)
    summary.setdefault("info", 0)
    summary["run"] = latest_run

    return summary
'''

if not saw_old:
    print("[WARN] Không tìm thấy block cũ /api/dashboard_data, chỉ chèn mới.")
cleaned = cleaned.replace(marker, new_block + "\n\n" + marker, 1)
path.write_text(cleaned, encoding="utf-8")
print("[OK] Đã reset route /api/dashboard_data (chỉ còn 1 bản JSON phẳng).")
PY
