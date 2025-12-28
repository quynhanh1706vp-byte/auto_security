#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
from pathlib import Path
import os, json

path = Path("app.py")
data = path.read_text(encoding="utf-8")
lines = data.splitlines(keepends=True)

out_lines = []
i = 0
removed_blocks = 0

while i < len(lines):
    line = lines[i]
    # Nếu gặp decorator của /api/dashboard_data -> bỏ cả block
    if '@app.route("/api/dashboard_data"' in line:
        removed_blocks += 1
        i += 1
        # skip đến trước route tiếp theo hoặc if __main__
        while i < len(lines):
            l2 = lines[i]
            stripped = l2.lstrip()
            if stripped.startswith('@app.route(') or stripped.startswith('if __name__ == "__main__":'):
                break
            i += 1
        # không append gì, chỉ continue với i hiện tại (route mới hoặc if __main__)
        continue
    else:
        out_lines.append(line)
        i += 1

cleaned = "".join(out_lines)

marker = 'if __name__ == "__main__":'
if marker not in cleaned:
    print("[ERR] Không tìm thấy 'if __name__ == \"__main__\":' trong app.py")
    raise SystemExit(1)

print(f"[INFO] Đã xoá {removed_blocks} block /api/dashboard_data cũ.")

new_block = '''@app.route("/api/dashboard_data")
def api_dashboard_data():
    """
    Trả về JSON phẳng cho Dashboard.
    Trả y nguyên nội dung summary_unified.json của RUN_* mới nhất
    (cộng thêm field 'run' để biết đang lấy RUN nào).
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

# chèn block mới TRƯỚC if __main__
new_data = cleaned.replace(marker, new_block + "\n\n" + marker, 1)
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã ghi lại app.py với đúng 1 route /api/dashboard_data.")
PY
